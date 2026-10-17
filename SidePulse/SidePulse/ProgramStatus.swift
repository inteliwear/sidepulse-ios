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

struct ProgramUpdate {
    let publisher: String
    let scope: String
    let seq: Int64
    let record: ProgramRecord

    private static func text(_ value: Any?, _ limit: Int, nonempty: Bool = false) throws -> String {
        guard let s = value as? String, s.utf8.count <= limit, (!nonempty || !s.isEmpty),
              !s.unicodeScalars.contains(where: { $0.value < 32 || (127...159).contains($0.value) }) else { throw ProgramStatusError.invalid }
        return s
    }
    private static func integer(_ value: Any?) throws -> Int64 {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: n.objCType)), n.int64Value >= 0,
              n.int64Value <= 9_007_199_254_740_991 else { throw ProgramStatusError.invalid }
        return n.int64Value
    }
    static func parse(_ raw: [String: Any]) throws -> ProgramUpdate {
        guard JSONSerialization.isValidJSONObject(raw),
              try JSONSerialization.data(withJSONObject: raw, options: [.withoutEscapingSlashes]).count <= 65536,
              try integer(raw["v"]) == 1, raw["type"] as? String == "program_status" else { throw ProgramStatusError.invalid }
        let publisher = try text(raw["publisher"], 128, nonempty: true)
        let scope = try text(raw["scope"], 128, nonempty: true)
        let seq = try integer(raw["seq"]), updated = try integer(raw["updated_at"])
        guard seq > 0, updated <= 253402300799999 else { throw ProgramStatusError.invalid }
        guard let fields = raw["status"] as? [String: Any], let state = fields["state"] as? String,
              ["idle", "working", "blocked", "done", "error", "clear"].contains(state) else { throw ProgramStatusError.invalid }
        func segment(_ s: String) -> Bool { s.range(of: "^[A-Za-z0-9_.+-]{1,32}$", options: .regularExpression) != nil }
        var status = ProgramFields(state: state)
        if let value = fields["id"] {
            let id = try text(value, 128), parts = id.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count <= 8, parts.allSatisfy({ segment(String($0)) }) else { throw ProgramStatusError.invalid }
            status.id = id
        }
        if let value = fields["app"] { let app = try text(value, 32); if segment(app) { status.app = app } }
        if let value = fields["title"] { status.title = try text(value, 192) }
        if let value = fields["msg"] { status.msg = try text(value, 2048) }
        if state == "blocked", let kind = fields["kind"] as? String, ["permission", "question", "auth"].contains(kind) { status.kind = kind }
        if ["working", "blocked"].contains(state), let progress = try? integer(fields["progress"]), progress <= 100 { status.progress = Int(progress) }
        let record = ProgramRecord(status: status, updated_at: updated)
        return ProgramUpdate(publisher: publisher, scope: scope, seq: seq, record: record)
    }
    /// The bridge delivers data as an object (APNs/recovery) or JSON string (FCM).
    private static func pushedData(_ payload: [AnyHashable: Any]) -> [String: Any]? {
        let data: [String: Any]?
        if let object = payload["data"] as? [String: Any] { data = object }
        else if let text = payload["data"] as? String, let bytes = text.data(using: .utf8) {
            data = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
        } else { data = nil }
        return data
    }
    static func isStatusPayload(_ payload: [AnyHashable: Any]) -> Bool {
        guard let type = pushedData(payload)?["type"] as? String else { return false }
        return type.hasPrefix("program_status") || type.hasPrefix("scope_")
    }
    static func pushedUpdate(_ payload: [AnyHashable: Any]) -> [String: Any]? {
        guard let data = pushedData(payload), data["type"] as? String == "program_status" else { return nil }
        return data
    }
}

struct TrackedProgramSession: Codable {
    let sender: String
    let publisher: String
    let scope: String
    var seq: Int64
    var record: ProgramRecord?
    var id: String { sender + "\u{0}" + publisher + "\u{0}" + scope }
}

struct ProgramAccounting: Codable {
    private(set) var entries: [String: TrackedProgramSession] = [:]
    private var recentSessions: [String] = []
    init() {}
    private enum CodingKeys: String, CodingKey { case entries, recentSessions }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let saved = try values.decode([String: TrackedProgramSession].self, forKey: .entries)
        for entry in saved.values { if let checked = Self.checked(entry) { entries[checked.id] = checked } }
        recentSessions = try values.decodeIfPresent([String].self, forKey: .recentSessions) ?? []
        retainRecentSessions()
    }
    private static func checked(_ entry: TrackedProgramSession) -> TrackedProgramSession? {
        let fields = entry.record.flatMap { try? JSONSerialization.jsonObject(with: JSONEncoder().encode($0.status)) } ?? ["state": "clear"]
        guard let parsed = try? ProgramUpdate.parse(["v": 1, "type": "program_status", "publisher": entry.publisher,
            "scope": entry.scope, "seq": entry.seq, "updated_at": entry.record?.updated_at ?? 0, "status": fields]) else { return nil }
        return TrackedProgramSession(sender: entry.sender, publisher: parsed.publisher, scope: parsed.scope,
                                     seq: parsed.seq, record: parsed.record.status.state == "clear" ? nil : parsed.record)
    }
    private mutating func retainRecentSessions(touched: String? = nil) {
        let active = entries.filter { $0.value.record != nil }
        var seen = Set<String>()
        recentSessions = recentSessions.filter { active[$0] != nil && seen.insert($0).inserted }
        let missing = active.keys.filter { !seen.contains($0) }.sorted {
            let a = active[$0]!.record!.updated_at, b = active[$1]!.record!.updated_at
            return a == b ? $0 < $1 : a < b
        }
        recentSessions = missing + recentSessions
        if let touched, active[touched] != nil { recentSessions.removeAll { $0 == touched }; recentSessions.append(touched) }
        while recentSessions.count > 64 { entries[recentSessions.removeFirst()]!.record = nil }
    }
    mutating func receiveMessage(_ raw: [String: Any], sender: String) throws -> Bool {
        let update = try ProgramUpdate.parse(raw)
        var entry = TrackedProgramSession(sender: sender, publisher: update.publisher, scope: update.scope, seq: update.seq, record: update.record)
        let previous = entries[entry.id]
        guard update.seq > (previous?.seq ?? 0) else { return false }
        if entry.record?.status.state == "clear" { entry.record = nil }
        entries[entry.id] = entry
        retainRecentSessions(touched: entry.id)
        return true
    }
    @discardableResult mutating func clearSession(id: String) -> Bool {
        guard entries[id]?.record != nil else { return false }
        entries[id]!.record = nil // Keep sequence protection until a newer report arrives.
        retainRecentSessions()
        return true
    }
    @discardableResult mutating func retainSenders(_ allowed: Set<String>) -> Bool {
        let removed = entries.keys.filter { !allowed.contains(entries[$0]!.sender) }
        for key in removed { entries.removeValue(forKey: key) }
        retainRecentSessions()
        return !removed.isEmpty
    }
    func sessions(now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> [ProgramSession] {
        entries.values.compactMap { entry -> ProgramSession? in
            guard let record = entry.record, record.status.state != "done" || now - record.updated_at <= 1_200_000 else { return nil }
            let title = record.status.title.flatMap { $0.isEmpty ? nil : $0 }
            return ProgramSession(id: entry.id, sender: entry.sender, scope: entry.scope,
                                  title: title ?? "Session " + String(entry.scope.prefix(8)), status: record.status, updatedAt: record.updated_at)
        }.sorted {
            if ProgramSession.priority($0.status.state) != ProgramSession.priority($1.status.state) { return ProgramSession.priority($0.status.state) < ProgramSession.priority($1.status.state) }
            return $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt
        }
    }
    func representative(now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> ProgramFields? { sessions(now: now).first?.status }
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
/// Duplicate updates cannot resume automation or replay an animation.
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

extension SessionActivitySummary {
    init?(sessions: [ProgramSession]) {
        guard let first = sessions.first else { return nil }
        total = sessions.count
        working = sessions.filter { $0.status.state == "working" }.count
        attention = sessions.filter { ["blocked", "error"].contains($0.status.state) }.count
        done = sessions.filter { $0.status.state == "done" }.count
        state = first.status.state; title = first.title; statusLabel = first.statusLabel
        appName = first.appName; progress = first.status.progress
        // ActivityKit has a small content budget. Keep exact session text in the app.
        message = first.status.msg.map { text in
            var bytes = Array(text.utf8.prefix(512))
            while String(bytes: bytes, encoding: .utf8) == nil { bytes.removeLast() }
            return String(bytes: bytes, encoding: .utf8)!
        }
        updatedAt = Date(timeIntervalSince1970: Double(sessions.map(\.updatedAt).max()!) / 1000)
    }
}
