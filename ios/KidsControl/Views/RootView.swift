import SwiftUI
import FamilyControls

struct RootView: View {
    @EnvironmentObject private var store: ControlStore
    @AppStorage("serverURL") private var serverURL = "http://79.99.40.230"
    @State private var pairCode = ""
    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection()
    @State private var controlName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color.black, Color(red: 0.055, green: 0.06, blue: 0.085)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        authorizationCard
                        if store.isPaired { pairedCard } else { pairingCard }
                        if !store.notice.isEmpty { noticeCard }
                    }
                    .padding(18)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .onChange(of: showPicker) { _, showing in
            if !showing && !selection.applicationTokens.isEmpty && controlName.isEmpty {
                controlName = selection.applicationTokens.count == 1 ? "Selected app" : "App group"
            }
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "checkmark.shield.fill").font(.title2)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 2) {
                Text("Kids Control").font(.title2.bold())
                Text("Child helper").font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if store.isPaired {
                Text("PAIRED")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.12), in: Capsule())
            }
        }
    }

    private var authorizationCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Apple authorization", systemImage: "lock.shield").font(.headline)
                Text("Status: \(String(describing: store.authorizationStatus))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Authorize this child iPad") {
                    Task { await store.requestChildAuthorization() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(store.busy)
            }
        }
    }

    private var pairingCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pair to your dashboard").font(.headline)
                TextField("https://kids.example.com", text: $serverURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                TextField("6-digit code", text: $pairCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                Button("Pair helper") {
                    Task { await store.pair(serverURL: serverURL, code: pairCode) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(pairCode.count != 6 || store.busy)
            }
        }
    }

    private var pairedCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(store.pairedDeviceName).font(.headline)
                        Text("Remote shield endpoint").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle().fill(.green).frame(width: 9, height: 9)
                }

                Divider().overlay(.white.opacity(0.08))

                Button {
                    Task { try? await store.syncAndApply() }
                } label: {
                    Label("Sync & apply now", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button {
                    selection = FamilyActivitySelection()
                    controlName = ""
                    showPicker = true
                } label: {
                    Label("Choose app / group", systemImage: "plus.app")
                }
                .buttonStyle(.bordered)

                if !selection.applicationTokens.isEmpty || !selection.webDomainTokens.isEmpty {
                    TextField("Dashboard name, e.g. Disney+", text: $controlName)
                        .textFieldStyle(.roundedBorder)
                    Text("Selected: \(selection.applicationTokens.count) apps, \(selection.webDomainTokens.count) websites")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Add live dashboard control") {
                        Task {
                            do {
                                try await store.registerControl(
                                    name: controlName.trimmingCharacters(in: .whitespacesAndNewlines),
                                    selection: selection
                                )
                                selection = FamilyActivitySelection()
                                controlName = ""
                            } catch {
                                store.setNotice(error.localizedDescription)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(controlName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let state = store.desiredState {
                    Divider().overlay(.white.opacity(0.08))
                    Text("Revision \(state.revision) • \(state.blockAll ? "BLOCK ALL" : "Custom controls")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(state.controls) { c in
                        HStack {
                            Text(c.name)
                            Spacer()
                            Text(c.blocked ? "BLOCKED" : "ALLOWED")
                                .font(.caption2.bold())
                                .foregroundStyle(c.blocked ? .red : .green)
                        }
                    }
                }

                Button("Unpair & clear shields", role: .destructive) {
                    store.unpair()
                }
                .font(.caption)
            }
        }
    }

    private var noticeCard: some View {
        Text(store.notice)
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(.secondary)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.07)))
    }
}
