import Foundation
import OSLog

enum EventLog {
    private static let logger = Logger(subsystem: "io.sidepulse.app", category: "SidePulse")
    private static let defaultsKey = "eventLog"
    private static let maxEntries = 40

    static func append(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)"
        logger.info("\(line, privacy: .public)")

        let defaults = UserDefaults.standard
        var entries = defaults.stringArray(forKey: defaultsKey) ?? []
        entries.append(line)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        defaults.set(entries, forKey: defaultsKey)
    }

    static func entries() -> [String] {
        UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
