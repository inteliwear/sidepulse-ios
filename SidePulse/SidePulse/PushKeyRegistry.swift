import Foundation

struct PushKeyRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let value: String
    let name: String
    let createdAt: Date
    var lastActiveAt: Date?
    var totalReceived: Int = 0
    var recentMessageIDs: [String] = []

    var suffix: String { String(value.suffix(4)) }
    var maskedKey: String { "…" + suffix }

    func token(for deviceToken: String) -> String {
        deviceToken + "_" + value
    }
}

/// Only locally issued keys are trusted. Removing a record permanently stops
/// accepting that key; receiving a push never creates or reactivates a record.
struct PushKeyRegistry: Codable, Equatable {
    enum Receipt: Equatable { case rejected, duplicate, accepted }
    private(set) var records: [PushKeyRecord] = []

    @discardableResult
    mutating func issue(name: String, now: Date = Date()) -> PushKeyRecord {
        let record = PushKeyRecord(
            id: UUID(),
            value: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            name: name,
            createdAt: now
        )
        records.append(record)
        return record
    }

    mutating func remove(id: UUID) {
        records.removeAll { $0.id == id }
    }

    func accepts(_ key: String?) -> Bool {
        guard let key else { return false }
        return records.contains { $0.value == key }
    }

    mutating func receive(key: String?, messageID: String?, now: Date = Date()) -> Receipt {
        guard let key, let index = records.firstIndex(where: { $0.value == key }) else {
            return .rejected
        }
        if let messageID, records[index].recentMessageIDs.contains(messageID) {
            return .duplicate
        }
        records[index].lastActiveAt = now
        records[index].totalReceived += 1
        if let messageID {
            records[index].recentMessageIDs.append(messageID)
            // Bound storage while deduplicating recent APNs callbacks and recovery.
            records[index].recentMessageIDs = Array(records[index].recentMessageIDs.suffix(256))
        }
        return .accepted
    }
}
