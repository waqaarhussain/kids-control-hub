import Foundation
import FamilyControls
import ManagedSettings
import UIKit

extension ManagedSettingsStore.Name {
    static let kidsControl = Self("KidsControl")
}

@MainActor
final class ControlStore: ObservableObject {
    static let shared = ControlStore()

    @Published var authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    @Published var pairedDeviceName = UserDefaults.standard.string(forKey: "deviceName") ?? ""
    @Published var desiredState: DesiredState?
    @Published var notice = ""
    @Published var busy = false

    private let managed = ManagedSettingsStore(named: .kidsControl)

    var isPaired: Bool {
        !(UserDefaults.standard.string(forKey: "agentToken") ?? "").isEmpty &&
        !(UserDefaults.standard.string(forKey: "deviceID") ?? "").isEmpty
    }

    private init() {}

    func setNotice(_ message: String) { notice = message }

    func requestChildAuthorization() async {
        busy = true
        defer { busy = false }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .child)
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            notice = "Parental-control authorization approved."
        } catch {
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            notice = "Authorization failed: \(error.localizedDescription)"
        }
    }

    func pair(serverURL: String, code: String) async {
        busy = true
        defer { busy = false }
        do {
            let pair = try await APIClient.shared.pair(serverURL: serverURL, code: code)
            UserDefaults.standard.set(pair.deviceID, forKey: "deviceID")
            UserDefaults.standard.set(pair.deviceName, forKey: "deviceName")
            UserDefaults.standard.set(pair.token, forKey: "agentToken")
            pairedDeviceName = pair.deviceName
            UIApplication.shared.registerForRemoteNotifications()
            if let pending = AppDelegate.pendingPushToken { await uploadPushTokenIfPossible(pending) }
            try await syncAndApply(silent: true)
            notice = "Paired with \(pair.deviceName)."
        } catch {
            notice = error.localizedDescription
        }
    }

    func unpair() {
        managed.clearAllSettings()
        ["deviceID", "deviceName", "agentToken"].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        pairedDeviceName = ""
        desiredState = nil
        notice = "Helper unpaired and local shields cleared."
    }

    func uploadPushTokenIfPossible(_ token: String) async {
        guard let deviceID = UserDefaults.standard.string(forKey: "deviceID"), isPaired else { return }
        do { try await APIClient.shared.uploadPushToken(deviceID: deviceID, token: token) }
        catch { notice = "Push token not uploaded yet: \(error.localizedDescription)" }
    }

    func registerControl(name: String, selection: FamilyActivitySelection) async throws {
        guard let deviceID = UserDefaults.standard.string(forKey: "deviceID") else { throw APIError.missingPairing }
        let encoded = try JSONEncoder().encode(selection).base64EncodedString()
        _ = try await APIClient.shared.registerControl(deviceID: deviceID, name: name, selectionB64: encoded)
        try await syncAndApply(silent: true)
        notice = "\(name) is now a live dashboard control."
    }

    func syncAndApply(silent: Bool = false) async throws {
        guard let deviceID = UserDefaults.standard.string(forKey: "deviceID") else { throw APIError.missingPairing }
        if !silent { busy = true }
        defer { if !silent { busy = false } }

        let state = try await APIClient.shared.desiredState(deviceID: deviceID)
        desiredState = state
        apply(state)
        try? await APIClient.shared.heartbeat(deviceID: deviceID)
        if !silent { notice = "Synced revision \(state.revision)." }
    }

    private func apply(_ state: DesiredState) {
        guard AuthorizationCenter.shared.authorizationStatus == .approved ||
              String(describing: AuthorizationCenter.shared.authorizationStatus).contains("approved") else {
            notice = "Apple Family Controls authorization is not approved yet."
            return
        }

        if state.blockAll {
            managed.shield.applications = nil
            managed.shield.webDomains = nil
            managed.shield.applicationCategories = .all()
            managed.shield.webDomainCategories = .all()
            return
        }

        var applicationTokens = Set<ApplicationToken>()
        var webTokens = Set<WebDomainToken>()

        for control in state.controls where control.blocked {
            guard let data = Data(base64Encoded: control.selectionB64),
                  let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { continue }
            applicationTokens.formUnion(selection.applicationTokens)
            webTokens.formUnion(selection.webDomainTokens)
        }

        managed.shield.applicationCategories = nil
        managed.shield.webDomainCategories = nil
        managed.shield.applications = applicationTokens.isEmpty ? nil : applicationTokens
        managed.shield.webDomains = webTokens.isEmpty ? nil : webTokens
    }
}
