import Foundation

struct APIClient {
    static let shared = APIClient()

    private func baseURL() throws -> URL {
        let value = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        guard let url = URL(string: value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            throw APIError.invalidURL
        }
        return url
    }

    private func request(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        authenticated: Bool = true
    ) throws -> URLRequest {
        let url = try baseURL().appending(path: path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard let token = UserDefaults.standard.string(forKey: "agentToken"), !token.isEmpty else {
                throw APIError.missingPairing
            }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private func perform<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.decode }
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.badResponse(http.statusCode, message)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decode }
    }

    func pair(serverURL: String, code: String) async throws -> PairResponse {
        UserDefaults.standard.set(serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forKey: "serverURL")
        let req = try request(path: "agent/pair", method: "POST", body: ["code": code], authenticated: false)
        return try await perform(req, as: PairResponse.self)
    }

    func heartbeat(deviceID: String) async throws {
        let req = try request(path: "agent/\(deviceID)/heartbeat", method: "POST", body: [:])
        _ = try await perform(req, as: SimpleOK.self)
    }

    func desiredState(deviceID: String) async throws -> DesiredState {
        let req = try request(path: "agent/\(deviceID)/desired-state")
        return try await perform(req, as: DesiredState.self)
    }

    func registerControl(deviceID: String, name: String, selectionB64: String) async throws -> RegisteredControl {
        let req = try request(
            path: "agent/\(deviceID)/controls",
            method: "POST",
            body: ["name": name, "selection_b64": selectionB64, "icon": "📱"]
        )
        return try await perform(req, as: RegisteredControl.self)
    }

    func uploadPushToken(deviceID: String, token: String) async throws {
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let req = try request(
            path: "agent/\(deviceID)/push-token",
            method: "POST",
            body: ["token": token, "environment": environment]
        )
        _ = try await perform(req, as: SimpleOK.self)
    }
}
