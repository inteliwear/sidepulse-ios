import XCTest
@testable import SidePulseTokenFormatting
final class ProgramStatusTests: XCTestCase {
    func testSharedFixturesAndPersistence() throws {
        let url = Bundle.module.url(forResource: "program-status", withExtension: "json", subdirectory: "Fixtures")!
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        for value in fixture["cases"] as! [[String: Any]] {
            var store = ProgramAccounting()
            for (raw, expected) in zip(value["snapshots"] as! [[String: Any]], value["expected"] as! [String]) {
                _ = try store.receive(ProgramSnapshot.parse(raw), sender: "sender")
                store = try JSONDecoder().decode(ProgramAccounting.self, from: JSONEncoder().encode(store))
                XCTAssertEqual(store.representative(now: 2_000_000)?.state ?? "idle", expected, value["name"] as! String)
            }
            if let app = value["expected_app"] as? String { XCTAssertEqual(store.representative(now: 2_000_000)?.app, app) }
            if value["expected_app"] is NSNull { XCTAssertNil(store.representative(now: 2_000_000)?.app) }
            if let msg = value["expected_msg"] as? String { XCTAssertEqual(store.representative(now: 2_000_000)?.msg, msg) }
            store.retainSenders([]); XCTAssertNil(store.representative())
        }
        for value in fixture["normalization"] as! [[String: Any]] {
            let raw: [String: Any] = ["v": 1, "type": "program_status_snapshot", "publisher": "p", "revision": 1, "scopes": ["s": ["seq": 1, "records": [["status": value["input"]!, "updated_at": 1]]]]]
            let parsed = try ProgramSnapshot.parse(raw).scopes["s"]!.records[0].status
            let normalized = try JSONSerialization.jsonObject(with: JSONEncoder().encode(parsed)) as! NSDictionary
            XCTAssertEqual(normalized, value["expected"] as! NSDictionary)
        }
        for value in fixture["invalid"] as! [[String: Any]] { XCTAssertThrowsError(try ProgramSnapshot.parse(value["snapshot"] as! [String: Any]), value["name"] as! String) }
    }
}
extension ProgramStatusTests {
    func testPresentationOverrideRetryAndReconnect() {
        var p = ProgramPresentation()
        XCTAssertFalse(p.needsWrite("working"))
        p.statusChanged(); XCTAssertTrue(p.needsWrite("working"))
        // A failed write does not advance presentation; the next attempt retries.
        XCTAssertTrue(p.needsWrite("working"))
        p.didWrite("working"); XCTAssertFalse(p.needsWrite("working"))
        p.statusChanged(); XCTAssertFalse(p.needsWrite("working"))
        p.manualWrite(); XCTAssertFalse(p.needsWrite("working"))
        p.deviceChanged(); XCTAssertFalse(p.needsWrite("working"))
        p.statusChanged(); XCTAssertTrue(p.needsWrite("working"))
        p.didWrite("working"); p.deviceChanged(); XCTAssertTrue(p.needsWrite("working"))
        XCTAssertTrue(p.needsWrite("blocked"))
    }
}
extension ProgramStatusTests {
    func testSamePublisherIsIsolatedBySenderAndRevocation() throws {
        let snapshot = try ProgramSnapshot.parse(["v": 1, "type": "program_status_snapshot", "publisher": "shared", "revision": 1, "scopes": ["s": ["seq": 1, "records": [["status": ["state": "working"], "updated_at": 1]]]]])
        var store = ProgramAccounting()
        XCTAssertTrue(try store.receive(snapshot, sender: "a"))
        XCTAssertTrue(try store.receive(snapshot, sender: "b"))
        var cleared = snapshot; cleared.revision = 2; cleared.scopes = [:]
        XCTAssertTrue(try store.receive(cleared, sender: "a"))
        XCTAssertEqual(store.representative()?.state, "working")
        XCTAssertFalse(try store.receive(snapshot, sender: "a"))
        store.retainSenders(["a"]); XCTAssertNil(store.representative())
    }
}

extension ProgramStatusTests {
    func testFullLedgerRejectsOnlyNewPublishersAndPersistsUpdates() throws {
        var store = ProgramAccounting()
        for i in 0..<64 { XCTAssertTrue(try store.receive(ProgramSnapshot(publisher: "p\(i)", revision: 1, scopes: [:]), sender: "sender")) }
        XCTAssertFalse(try store.receive(ProgramSnapshot(publisher: "overflow", revision: 1, scopes: [:]), sender: "sender"))
        XCTAssertTrue(try store.receive(ProgramSnapshot(publisher: "p0", revision: 2, scopes: [:]), sender: "sender"))
        store = try JSONDecoder().decode(ProgramAccounting.self, from: JSONEncoder().encode(store))
        XCTAssertEqual(store.snapshots.count, 64)
        XCTAssertEqual(store.snapshots["sender\u{0}p0"]?.revision, 2)
        store.retainSenders([])
        XCTAssertTrue(try store.receive(ProgramSnapshot(publisher: "overflow", revision: 1, scopes: [:]), sender: "new"))
    }
    func testExistingPushAndRecoveryCarryCompleteSnapshots() throws {
        let snapshot: [String: Any] = ["v": 1, "type": "program_status_snapshot", "publisher": "p", "revision": 1, "scopes": [:]]
        let text = String(data: try JSONSerialization.data(withJSONObject: snapshot), encoding: .utf8)!
        var accounting = ProgramAccounting()
        for data in [snapshot as Any, text as Any] {
            let payload: [AnyHashable: Any] = ["data": data, "shared_key": "paired-sender"]
            let parsed = try ProgramSnapshot.parse(XCTUnwrap(ProgramAccounting.pushedSnapshot(payload)))
            _ = try accounting.receive(parsed, sender: "paired-sender")
        }
        XCTAssertEqual(accounting.snapshots.count, 1)
        XCTAssertNil(ProgramAccounting.pushedSnapshot(["leds": "off"]))
        XCTAssertNil(ProgramAccounting.pushedSnapshot(["data": "invalid json"]))
        XCTAssertNil(ProgramAccounting.pushedSnapshot(["data": ["type": "unknown"]]))
    }
}

extension ProgramStatusTests {
    func testSessionListGroupsChildrenAndSurvivesRecovery() throws {
        let url = Bundle.module.url(forResource: "program-status", withExtension: "json", subdirectory: "Fixtures")!
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let snapshot = try ProgramSnapshot.parse(fixture["session_list"] as! [String: Any])
        var store = ProgramAccounting()
        _ = try store.receive(snapshot, sender: "a")
        let sessions = store.sessions(now: 2_000_000)
        XCTAssertEqual(sessions.map(\.scope), ["error", "build", "tests", "done"])
        XCTAssertEqual(sessions[1].title, "Checkout flow")
        XCTAssertEqual(sessions[1].statusLabel, "Needs approval")
        XCTAssertEqual(sessions[1].appName, "Claude")
        XCTAssertEqual(sessions[1].status.msg, "Approve database migration")
        XCTAssertEqual(sessions[2].status.progress, 72)
        XCTAssertEqual(store.representative(now: 2_000_000), sessions.first?.status)
        XCTAssertNil(store.snapshots["a\u{0}sessions-fixture"]?.scopes["build"]?.records[1].status.app)
        _ = try store.receive(snapshot, sender: "b")
        XCTAssertEqual(Set(store.sessions(now: 2_000_000).map(\.id)).count, 8)
        store = try JSONDecoder().decode(ProgramAccounting.self, from: JSONEncoder().encode(store))
        store.retainSenders(["a"])
        XCTAssertEqual(store.sessions(now: 2_000_000), sessions)
        var cleared = snapshot; cleared.revision = 2; cleared.scopes.removeValue(forKey: "build")
        XCTAssertTrue(try store.receive(cleared, sender: "a"))
        XCTAssertFalse(try store.receive(snapshot, sender: "a"))
        XCTAssertEqual(store.sessions(now: 2_000_000).map(\.scope), ["error", "tests", "done"])
        store.retainSenders([])
        XCTAssertTrue(store.sessions().isEmpty)
    }
}

extension ProgramStatusTests {
    func testSessionLEDPatternPreferencesPersistenceAndMissingPatternFallback() throws {
        var settings = SessionLEDSettings()
        for (state, _) in SessionLEDSettings.conditions {
            XCTAssertEqual(settings.program(for: state, library: []), ProgramAccounting.program(for: state))
        }
        var pattern = LibraryPattern(name: "My attention pattern", source: "#FF00FF 1s pulse\nrepeat")
        settings.patterns["blocked"] = pattern.id
        settings.enabled = false
        settings = try JSONDecoder().decode(SessionLEDSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(settings.enabled)
        XCTAssertEqual(settings.program(for: "blocked", library: [pattern]), pattern.ledText)
        XCTAssertEqual(settings.program(for: "working", library: [pattern]), ProgramAccounting.program(for: "working"))
        XCTAssertEqual(settings.program(for: "blocked", library: []), ProgramAccounting.program(for: "blocked"))
        pattern.source = "#00FF00 1s pulse\nrepeat"
        XCTAssertEqual(settings.program(for: "blocked", library: [pattern]), pattern.ledText)
        settings.patterns.removeValue(forKey: "blocked")
        XCTAssertEqual(settings.program(for: "blocked", library: [pattern]), ProgramAccounting.program(for: "blocked"))
    }
    func testPatternChangeAtSameStateWritesOnceAndPreservesManualOverride() {
        var presentation = ProgramPresentation(enabled: true)
        let previous = "working\u{0}old pattern"
        let changed = "working\u{0}new pattern"
        presentation.didWrite(previous)
        XCTAssertFalse(presentation.needsWrite(previous))
        XCTAssertTrue(presentation.needsWrite(changed))
        presentation.didWrite(changed)
        XCTAssertFalse(presentation.needsWrite(changed))
        presentation.manualWrite()
        XCTAssertFalse(presentation.needsWrite(previous))
    }
}
