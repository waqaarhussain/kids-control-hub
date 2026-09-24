import Foundation

struct PairResponse: Decodable {
    let deviceID: String
    let deviceName: String
    let token: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case deviceName = "device_name"
        case token
    }
}

struct RemoteControl: Decodable, Identifiable {
    let id: String
    let name: String
    let blocked: Bool
    let selectionB64: String

    enum CodingKeys: String, CodingKey {
        case id, name, blocked
        case selectionB64 = "selection_b64"
    }
}

struct DesiredState: Decodable {
    let deviceID: String
    let revision: Int
    let blockAll: Bool
    let controls: [RemoteControl]

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case revision
        case blockAll = "block_all"
        case controls
    }
}

struct RegisteredControl: Decodable {
    let ok: Bool
    let id: String
    let name: String
}

struct SimpleOK: Decodable {
    let ok: Bool
}

enum APIError: LocalizedError {
    case invalidURL
    case badResponse(Int, String)
    case missingPairing
    case decode

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The server URL is invalid."
        case .badResponse(let code, let message): return "Server returned \(code): \(message)"
        case .missingPairing: return "Pair this iPad first."
        case .decode: return "The server response could not be read."
        }
    }
}
