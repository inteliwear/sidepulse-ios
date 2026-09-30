import Foundation

enum APNsEnvironment: String {
    case development
    case production

    static func configured(_ value: String?) throws -> APNsEnvironment {
        guard let value, let environment = APNsEnvironment(rawValue: value) else {
            throw APNsEnvironmentError.invalidConfiguration(value)
        }
        return environment
    }
}

enum APNsEnvironmentError: LocalizedError {
    case invalidConfiguration(String?)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let value):
            let detail = value.map { " (‘\($0)’)." } ?? "."
            return "The app’s APNs environment is missing or invalid\(detail) Reinstall a correctly configured build."
        }
    }
}

enum PushTokenFormatter {
    static func format(_ token: Data, environment: APNsEnvironment) -> String {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        switch environment {
        case .development:
            return "dev_\(hex)"
        case .production:
            return hex
        }
    }
}

enum PushRecoveryEndpoint {
    static func queued(server: URL, token: String) -> URL {
        server
            .appendingPathComponent("api")
            .appendingPathComponent("leds")
            .appendingPathComponent("apns_\(token)")
            .appendingPathComponent("queued")
    }
}
