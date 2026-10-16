// OSC 7501 field semantics in JSON. Accounting has no dependency on LED hardware.
import Foundation
import CoreFoundation

enum ProgramStatusError: Error { case invalid }
struct ProgramFields: Codable, Equatable {
    var state: String
    var id: String?
    var app: String?
    var kind: String?
    var progress: Int?
    var title: String?
    var msg: String?
}
struct ProgramRecord: Codable, Equatable {
    var status: ProgramFields
    var updated_at: Int64
}
struct ProgramScope: Codable, Equatable { var seq: Int64; var records: [ProgramRecord] }
struct ProgramSnapshot: Codable, Equatable {
    var v = 1
    var type = "program_status_snapshot"
    var publisher: String
    var revision: Int64
    var scopes: [String: ProgramScope]

    static func parse(_ value: [String: Any]) throws -> ProgramSnapshot {
        func fail() throws -> Never { throw ProgramStatusError.invalid }
        func text(_ value: Any?, _ limit: Int, nonempty: Bool = false) throws -> String {
            guard let s = value as? String, s.utf8.count <= limit, (!nonempty || !s.isEmpty),
                  !s.unicodeScalars.contains(where: { $0.value < 32 || (127...159).contains($0.value) }) else { try fail() }
            return s
        }
        func integer(_ value: Any?) throws -> Int64 {
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                  !["f", "d"].contains(String(cString: n.objCType)), n.int64Value >= 0, n.int64Value <= 9_007_199_254_740_991 else { try fail() }
            return n.int64Value
        }
        func segment(_ s: String) -> Bool { s.range(of: "^[A-Za-z0-9_.+-]{1,32}$", options: .regularExpression) != nil }
        guard JSONSerialization.isValidJSONObject(value), try JSONSerialization.data(withJSONObject: value.filter { $0.key != "shared_key" }, options: [.withoutEscapingSlashes]).count <= 65536,
              try integer(value["v"]) == 1, value["type"] as? String == "program_status_snapshot",
              let scopes = value["scopes"] as? [String: Any], scopes.count <= 64 else { try fail() }
        var out = ProgramSnapshot(publisher: try text(value["publisher"], 128, nonempty: true), revision: try integer(value["revision"]), scopes: [:])
        var count = 0
        for (scope, value) in scopes {
            _ = try text(scope, 128, nonempty: true)
            guard let item = value as? [String: Any], let records = item["records"] as? [[String: Any]] else { try fail() }
            var parsed: [ProgramRecord] = []; var ids = Set<String>()
            for record in records {
                guard let raw = record["status"] as? [String: Any], let state = raw["state"] as? String,
                      ["idle", "working", "blocked", "done", "error"].contains(state) else { try fail() }
                var status = ProgramFields(state: state)
                if let value = raw["id"] {
                    let id = try text(value, 128)
                    let parts = id.split(separator: "/", omittingEmptySubsequences: false)
                    guard parts.count <= 8, parts.allSatisfy({ segment(String($0)) }) else { try fail() }
                    status.id = id
                }
                guard ids.insert(status.id ?? "").inserted else { try fail() }
                if let value = raw["app"] { let app = try text(value, 32); if segment(app) { status.app = app } }
                if let value = raw["title"] { status.title = try text(value, 192) }
                if let value = raw["msg"] { status.msg = try text(value, 2048) }
                if state == "blocked", let kind = raw["kind"] as? String, ["permission", "question", "auth"].contains(kind) { status.kind = kind }
                if ["working", "blocked"].contains(state), let progress = try? integer(raw["progress"]), progress <= 100 { status.progress = Int(progress) }
                let updated = try integer(record["updated_at"])
                guard updated <= 253402300799999 else { try fail() }
                parsed.append(ProgramRecord(status: status, updated_at: updated)); count += 1
            }
            out.scopes[scope] = ProgramScope(seq: try integer(item["seq"]), records: parsed)
        }
        guard count <= 256 else { try fail() }
        return out
    }
}

struct ProgramAccounting: Codable {
    private(set) var snapshots: [String: ProgramSnapshot] = [:]
    private(set) var senders: [String: String] = [:]
    init() {}
    private enum CodingKeys: String, CodingKey { case snapshots, senders }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let restored = try values.decode([String: ProgramSnapshot].self, forKey: .snapshots)
        let owners = try values.decode([String: String].self, forKey: .senders)
        for key in restored.keys.sorted().prefix(64) {
            guard let sender = owners[key], let data = try? JSONEncoder().encode(restored[key]!),
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let snapshot = try? ProgramSnapshot.parse(value) else { continue }
            _ = try receive(snapshot, sender: sender)
        }
    }
    mutating func receive(_ snapshot: ProgramSnapshot, sender: String) throws -> Bool {
        let key = sender + "\u{0}" + snapshot.publisher
        if let old = snapshots[key], old.revision >= snapshot.revision { return false }
        // Reject only the extra publisher; preserve other updates in this recovery batch.
        guard snapshots[key] != nil || snapshots.count < 64 else { return false }
        snapshots[key] = snapshot; senders[key] = sender
        return true
    }
    @discardableResult mutating func retainSenders(_ allowed: Set<String>) -> Bool {
        let removed = snapshots.keys.filter { !allowed.contains(senders[$0] ?? "") }
        for key in removed { snapshots.removeValue(forKey: key); senders.removeValue(forKey: key) }
        return !removed.isEmpty
    }
    /// One row per scope; child permission/tool records determine the session's status.
    func sessions(now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> [ProgramSession] {
        var result: [ProgramSession] = []
        for key in snapshots.keys.sorted() {
            for scope in snapshots[key]!.scopes.keys.sorted() {
                let records = snapshots[key]!.scopes[scope]!.records
                var visible: [ProgramRecord] = []
                for var record in records where record.status.state != "done" || now - record.updated_at <= 1_200_000 {
                    var parent = record.status.id ?? ""
                    while record.status.app == nil && !parent.isEmpty {
                        parent = parent.contains("/") ? String(parent.prefix(upTo: parent.lastIndex(of: "/")!)) : ""
                        record.status.app = records.first(where: { ($0.status.id ?? "") == parent })?.status.app
                    }
                    visible.append(record)
                }
                guard let selected = visible.sorted(by: {
                    if ProgramSession.priority($0.status.state) != ProgramSession.priority($1.status.state) {
                        return ProgramSession.priority($0.status.state) < ProgramSession.priority($1.status.state)
                    }
                    if $0.updated_at != $1.updated_at { return $0.updated_at > $1.updated_at }
                    return ($0.status.id ?? "") < ($1.status.id ?? "")
                }).first else { continue }
                let rootTitle = records.first(where: { $0.status.id == nil })?.status.title
                let title = [rootTitle, selected.status.title].compactMap { $0 }.first { !$0.isEmpty }
                result.append(ProgramSession(id: key + "\u{0}" + scope, sender: senders[key] ?? "", scope: scope,
                    title: title ?? "Session " + String(scope.prefix(8)), status: selected.status, updatedAt: selected.updated_at))
            }
        }
        return result.sorted {
            if ProgramSession.priority($0.status.state) != ProgramSession.priority($1.status.state) {
                return ProgramSession.priority($0.status.state) < ProgramSession.priority($1.status.state)
            }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }
    func representative(now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> ProgramFields? {
        sessions(now: now).first?.status
    }
    /// The existing bridge delivers `data` as an object (APNs/recovery) or JSON string (FCM).
    static func pushedSnapshot(_ payload: [AnyHashable: Any]) -> [String: Any]? {
        let data: [String: Any]?
        if let object = payload["data"] as? [String: Any] { data = object }
        else if let text = payload["data"] as? String, let bytes = text.data(using: .utf8) {
            data = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
        } else { data = nil }
        guard data?["type"] as? String == "program_status_snapshot" else { return nil }
        return data
    }
    static func program(for state: String) -> String {
        switch state {
        case "working": return "off\n#00E5FF 900ms pulse\nrepeat"
        case "blocked", "error": return "off\n#FF3A00 1.6s pulse\nrepeat"
        case "done": return "#00FF66 320ms cosine"
        default: return "off 2s\n#006060 2s pulse\nrepeat"
        }
    }
}

/// A successful direct write owns presentation until a newer status is accepted.
/// Duplicate snapshots cannot resume automation or replay an animation.
struct ProgramPresentation {
    private(set) var enabled: Bool
    private var lastWrittenState: String?
    init(enabled: Bool = false) { self.enabled = enabled }
    mutating func statusChanged() { if !enabled { lastWrittenState = nil }; enabled = true }
    mutating func manualWrite() { enabled = false; lastWrittenState = nil }
    mutating func deviceChanged() { lastWrittenState = nil }
    func needsWrite(_ state: String) -> Bool { enabled && lastWrittenState != state }
    mutating func didWrite(_ state: String) { lastWrittenState = state }
}


/// Display data derived from the ledger; never a second source of session state.
struct ProgramSession: Identifiable, Equatable {
    let id: String
    let sender: String
    let scope: String
    let title: String
    let status: ProgramFields
    let updatedAt: Int64

    static func priority(_ state: String) -> Int {
        ["error": 0, "blocked": 1, "working": 2, "done": 3, "idle": 4][state] ?? 4
    }
    var statusLabel: String {
        switch status.state {
        case "blocked":
            switch status.kind {
            case "permission": return "Needs approval"
            case "question": return "Needs input"
            case "auth": return "Needs sign-in"
            default: return "Blocked"
            }
        case "working": return "Working"
        case "error": return "Error"
        case "done": return "Done"
        default: return "Idle"
        }
    }
    var appName: String {
        switch status.app {
        case "claude-code", "claude": return "Claude"
        case "codex": return "Codex"
        case "cursor": return "Cursor"
        case "gemini": return "Gemini"
        default: return status.app ?? "Agent"
        }
    }
}

/// User-selected library patterns affect LED output only, never session accounting.
struct SessionLEDSettings: Codable, Equatable {
    static let conditions = [("working", "Working"), ("blocked", "Needs attention"),
                             ("error", "Error"), ("done", "Done"), ("idle", "Idle")]
    var enabled = true
    var patterns: [String: UUID] = [:]

    func program(for state: String, library: [LibraryPattern]) -> String {
        if let id = patterns[state], let pattern = library.first(where: { $0.id == id }) {
            return pattern.ledText
        }
        return ProgramAccounting.program(for: state)
    }
    func patternName(for state: String, library: [LibraryPattern]) -> String {
        guard let id = patterns[state] else { return "Default" }
        return library.first(where: { $0.id == id })?.name ?? "Default (pattern removed)"
    }
}
