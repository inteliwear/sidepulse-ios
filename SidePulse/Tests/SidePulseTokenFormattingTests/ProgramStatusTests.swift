import XCTest
@testable import SidePulseTokenFormatting
final class ProgramStatusTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let url = Bundle.module.url(forResource: "program-updates", withExtension: "json", subdirectory: "Fixtures")!
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }
    func testSharedUpdateFixturesAndPersistence() throws {
        let f = try fixture()
        for value in f["cases"] as! [[String: Any]] {
            var store = ProgramAccounting()
            for (updates, expected) in zip(value["updates"] as! [[[String: Any]]], value["expected"] as! [String]) {
                for raw in updates { _ = try store.receiveMessage(raw, sender: "sender") }
                store = try JSONDecoder().decode(ProgramAccounting.self, from: JSONEncoder().encode(store))
                XCTAssertEqual(store.representative(now: 2_000_000)?.state ?? "idle", expected, value["name"] as! String)
            }
            if let app = value["expected_app"] as? String { XCTAssertEqual(store.representative(now: 2_000_000)?.app, app) }
            if value["expected_app"] is NSNull { XCTAssertNil(store.representative(now: 2_000_000)?.app) }
            if let msg = value["expected_msg"] as? String { XCTAssertEqual(store.representative(now: 2_000_000)?.msg, msg) }
            store.retainSenders([]); XCTAssertNil(store.representative())
        }
        for value in f["normalization"] as! [[String: Any]] {
            var raw = event(); raw["status"] = value["input"]
            let status = try ProgramUpdate.parse(raw).record.status
            let fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as! NSDictionary
            XCTAssertEqual(fields, value["expected"] as! NSDictionary)
        }
        for value in f["invalid"] as! [[String: Any]] {
            XCTAssertThrowsError(try ProgramUpdate.parse(value["update"] as! [String: Any]), value["name"] as! String)
        }
    }
    func testSessionListUsesCompleteUpdatesAndSurvivesRestart() throws {
        let updates = try fixture()["session_list"] as! [[String: Any]]
        var store = ProgramAccounting()
        for sender in ["a", "b"] { for raw in updates { XCTAssertTrue(try store.receiveMessage(raw, sender: sender)) } }
        XCTAssertEqual(Set(store.sessions(now: 2_000_000).map(\.id)).count, 8)
        store = try JSONDecoder().decode(ProgramAccounting.self, from: JSONEncoder().encode(store))
        store.retainSenders(["a"])
        let sessions = store.sessions(now: 2_000_000)
        XCTAssertEqual(sessions.map(\.scope), ["error", "build", "tests", "done"])
        XCTAssertEqual(sessions[1].title, "Checkout flow")
        XCTAssertEqual(sessions[1].statusLabel, "Needs approval")
        XCTAssertEqual(sessions[1].appName, "Claude")
        XCTAssertEqual(sessions[1].status.msg, "Approve database migration")
        XCTAssertEqual(sessions[2].status.progress, 72)
        XCTAssertTrue(try store.receiveMessage(event("clear", seq: 2, scope: "build", publisher: "sessions-fixture"), sender: "a"))
        XCTAssertEqual(store.sessions(now: 2_000_000).map(\.scope), ["error", "tests", "done"])
    }
    func testSnapshotWireIsAlwaysRejectedAndCannotBecomeAnLEDWrite() throws {
        let old: [String: Any] = ["v": 1, "type": "program_status_snapshot", "publisher": "p", "revision": 1, "scopes": [:]]
        var store = ProgramAccounting()
        XCTAssertThrowsError(try store.receiveMessage(old, sender: "a"))
        XCTAssertNil(ProgramUpdate.pushedUpdate(["data": old]))
        XCTAssertTrue(store.sessions().isEmpty)
    }
    func testObjectAndStringEnvelopesUseSameUpdateParser() throws {
        let raw = event()
        let text = String(data: try JSONSerialization.data(withJSONObject: raw), encoding: .utf8)!
        for data: Any in [raw, text] {
            XCTAssertNotNil(ProgramUpdate.pushedUpdate(["data": data]))
        }
        XCTAssertNil(ProgramUpdate.pushedUpdate(["data": "invalid json"]))
        XCTAssertNil(ProgramUpdate.pushedUpdate(["leds": "off"]))
    }
    func testPresentationRetryReconnectAndDuplicateUpdates() {
        var p = ProgramPresentation()
        XCTAssertFalse(p.needsWrite("working"))
        p.statusChanged(); XCTAssertTrue(p.needsWrite("working"))
        XCTAssertTrue(p.needsWrite("working"))
        p.didWrite("working"); XCTAssertFalse(p.needsWrite("working"))
        p.statusChanged(); XCTAssertFalse(p.needsWrite("working"))
        p.manualWrite(); p.deviceChanged(); XCTAssertFalse(p.needsWrite("working"))
        p.statusChanged(); XCTAssertTrue(p.needsWrite("working"))
        p.didWrite("working"); p.deviceChanged(); XCTAssertTrue(p.needsWrite("working"))
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
        XCTAssertEqual(settings.program(for: "error", library: [pattern]), pattern.ledText)
        settings.disabledStates.insert("blocked")
        XCTAssertEqual(settings.program(for: "error", library: [pattern]), "off\n")
        settings.disabledStates.remove("blocked")
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
    func testLEDMasterOffStopsSessionsWithoutTakingManualOwnership() throws {
        var store = ProgramAccounting()
        XCTAssertTrue(try store.receiveMessage(event(), sender: "mac"))
        var settings = SessionLEDSettings()
        var presentation = ProgramPresentation(enabled: true)
        presentation.didWrite("working")
        settings.enabled = false
        XCTAssertNil(settings.ledState(in: store.sessions(now: 2_000_000)))
        XCTAssertEqual(store.sessions(now: 2_000_000).count, 1)
        XCTAssertTrue(presentation.needsWrite("off"))
        presentation.didWrite("off")
        XCTAssertFalse(presentation.needsWrite("off"))

        presentation.manualWrite()
        XCTAssertTrue(try store.receiveMessage(event("blocked", seq: 2), sender: "mac"))
        presentation.statusChanged(ledsEnabled: settings.enabled)
        presentation.deviceChanged()
        XCTAssertFalse(presentation.needsWrite("off"))
        XCTAssertEqual(store.sessions(now: 2_000_000).first?.status.state, "blocked")

        settings.enabled = true
        presentation.statusChanged(ledsEnabled: settings.enabled)
        XCTAssertEqual(settings.ledState(in: store.sessions(now: 2_000_000)), "blocked")
        XCTAssertTrue(presentation.needsWrite("blocked"))
    }
    func testDisplaySwitchesPreserveExistingPreferencesAndSelectedPatterns() throws {
        let pattern = LibraryPattern(name: "Done", source: "#00FF00 1s")
        let previous: [String: Any] = ["enabled": false, "patterns": ["done": pattern.id.uuidString]]
        var settings = try JSONDecoder().decode(SessionLEDSettings.self, from: JSONSerialization.data(withJSONObject: previous))
        XCTAssertFalse(settings.enabled)
        XCTAssertTrue(SessionLEDSettings.conditions.allSatisfy { settings.shows($0.0) })
        XCTAssertEqual(settings.program(for: "done", library: [pattern]), pattern.ledText)
        settings.disabledStates = ["working", "done"]
        settings = try JSONDecoder().decode(SessionLEDSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(settings.disabledStates, ["working", "done"])
        XCTAssertEqual(settings.program(for: "done", library: [pattern]), "off\n")
        XCTAssertEqual(settings.patterns["done"], pattern.id)
        settings.disabledStates.remove("done")
        XCTAssertEqual(settings.program(for: "done", library: [pattern]), pattern.ledText)
    }
}

extension ProgramStatusTests {
    private func event(_ state: String = "working", seq: Int = 1, scope: String = "session", publisher: String = "mac", id: String? = nil) -> [String: Any] {
        var status: [String: Any] = ["state": state, "app": "codex", "title": "Example"]
        if let id { status["id"] = id }
        return ["v": 1, "type": "program_status", "publisher": publisher, "scope": scope,
                "seq": seq, "updated_at": 2_000_000, "status": status]
    }
    func testOnlyDoneAndInputArePresentedWithoutFilteringLedger() throws {
        var store = ProgramAccounting()
        for (sender, state) in [("a", "error"), ("b", "working"), ("c", "blocked"), ("d", "done")] {
            _ = try store.receiveMessage(event(state), sender: sender)
        }
        let sessions = store.sessions(now: 2_000_000)
        var settings = SessionLEDSettings()
        settings.disabledStates = ["working"]
        XCTAssertEqual(settings.ledState(in: sessions), "error")
        let displayed = settings.displayedSessions(in: sessions)
        XCTAssertEqual(displayed.map { $0.status.state }, ["error", "blocked", "done"])
        let summary = try XCTUnwrap(SessionActivitySummary(sessions: displayed))
        XCTAssertEqual(summary.total, 3); XCTAssertEqual(summary.working, 0)
        XCTAssertEqual(summary.attention, 2); XCTAssertEqual(summary.done, 1)
        settings.enabled = false // LED master switch does not hide the Live Activity.
        XCTAssertEqual(settings.displayedSessions(in: sessions).count, 3)
        XCTAssertNil(settings.ledState(in: sessions))
        settings.enabled = true
        settings.disabledStates.insert("blocked")
        XCTAssertEqual(settings.ledState(in: sessions), "done")
        settings.disabledStates.insert("done")
        XCTAssertNil(settings.ledState(in: sessions))
        XCTAssertNil(SessionActivitySummary(sessions: settings.displayedSessions(in: sessions)))
        XCTAssertEqual(store.sessions(now: 2_000_000), sessions)
        XCTAssertNil(settings.ledState(in: []))
        XCTAssertFalse(settings.shows("idle"))
        XCTAssertEqual(settings.program(for: "idle", library: []), "off\n")
        XCTAssertNil(settings.ledState(in: sessions)) // Hidden sessions must not fall back to Idle.
    }
    func testAcknowledgedDoneAndNewReportsRespectDisplaySwitches() throws {
        var store = ProgramAccounting()
        var settings = SessionLEDSettings()
        settings.disabledStates = ["working", "blocked"]
        _ = try store.receiveMessage(event("done"), sender: "a")
        let done = try XCTUnwrap(store.sessions(now: 2_000_000).first)
        XCTAssertEqual(settings.ledState(in: [done]), "done")
        XCTAssertTrue(store.acknowledgeSession(id: done.id, seq: done.seq))
        XCTAssertEqual(store.sessions().first?.status.state, "idle")
        XCTAssertNil(settings.ledState(in: store.sessions()))
        XCTAssertNil(SessionActivitySummary(sessions: settings.displayedSessions(in: store.sessions())))
        _ = try store.receiveMessage(event("working", seq: 2), sender: "a")
        XCTAssertNil(settings.ledState(in: store.sessions()))
        _ = try store.receiveMessage(event("done", seq: 3), sender: "a")
        XCTAssertEqual(settings.ledState(in: store.sessions(now: 2_000_000)), "done")
    }
    func testAcknowledgedDoneStaysIdleAcrossRestartAndRejectsReplays() throws {
        var store = ProgramAccounting()
        var done = event("done", seq: 10)
        done["status"] = ["state": "done", "title": "Example", "app": "codex", "msg": "Finished"]
        XCTAssertTrue(try store.receiveMessage(done, sender: "a"))
        let session = try XCTUnwrap(store.sessions(now: 2_000_000).first)
        XCTAssertTrue(store.acknowledgeSession(id: session.id, seq: session.seq))
        XCTAssertFalse(store.acknowledgeSession(id: session.id, seq: session.seq))
        store = try JSONDecoder().decode(ProgramAccounting.self, from: JSONEncoder().encode(store))
        let idle = try XCTUnwrap(store.sessions().first)
        XCTAssertEqual(idle.statusLabel, "Idle")
        XCTAssertEqual(idle.title, session.title)
        XCTAssertEqual(idle.updatedAt, session.updatedAt)
        XCTAssertEqual(idle.seq, session.seq)
        XCTAssertNil(idle.status.msg)
        XCTAssertEqual(SessionActivitySummary(sessions: store.sessions())?.done, 0)
        XCTAssertEqual(SessionActivitySummary(sessions: store.sessions())?.state, "idle")
        XCTAssertFalse(try store.receiveMessage(done, sender: "a"))
        XCTAssertFalse(try store.receiveMessage(event("done", seq: 9), sender: "a"))
        XCTAssertEqual(store.representative()?.state, "idle")
        XCTAssertTrue(try store.receiveMessage(event("done", seq: 11), sender: "a"))
        XCTAssertFalse(store.acknowledgeSession(id: session.id, seq: session.seq))
        XCTAssertEqual(store.representative(now: 2_000_000)?.state, "done")
        XCTAssertTrue(try store.receiveMessage(event("working", seq: 12), sender: "a"))
        XCTAssertFalse(store.acknowledgeSession(id: session.id, seq: 12))
        XCTAssertEqual(store.representative()?.state, "working")
    }
    func testAcknowledgementKeepsOtherSourcesPriorityAndDoesNotRefreshCapacity() throws {
        var store = ProgramAccounting()
        XCTAssertTrue(try store.receiveMessage(event("done"), sender: "a"))
        let done = try XCTUnwrap(store.sessions(now: 2_000_000).first)
        for (sender, publisher, scope) in [("b", "mac", "session"), ("a", "other", "session"), ("a", "mac", "other")] {
            XCTAssertTrue(try store.receiveMessage(event("blocked", scope: scope, publisher: publisher), sender: sender))
        }
        XCTAssertTrue(store.acknowledgeSession(id: done.id, seq: done.seq))
        XCTAssertEqual(store.sessions().count, 4)
        XCTAssertEqual(store.representative()?.state, "blocked")
        XCTAssertFalse(store.acknowledgeSession(id: "missing", seq: 1))
        for i in 0..<61 { _ = try store.receiveMessage(event(scope: "extra-\(i)"), sender: "a") }
        XCTAssertEqual(store.sessions().count, 64)
        XCTAssertFalse(store.sessions().contains { $0.id == done.id })
        XCTAssertFalse(try store.receiveMessage(event("done"), sender: "a"))
    }
    func testLocalSessionClearPersistsUntilANewerMatchingUpdate() throws {
        var store = ProgramAccounting()
        XCTAssertTrue(try store.receiveMessage(event(seq: 10), sender: "a"))
        let session = try XCTUnwrap(store.sessions().first)
        XCTAssertTrue(store.clearSession(id: session.id))
        XCTAssertFalse(store.clearSession(id: session.id))
        XCTAssertTrue(store.sessions().isEmpty)
        store = try JSONDecoder().decode(ProgramAccounting.self, from: JSONEncoder().encode(store))
        XCTAssertFalse(try store.receiveMessage(event(seq: 10), sender: "a"))
        XCTAssertFalse(try store.receiveMessage(event("blocked", seq: 9), sender: "a"))
        XCTAssertTrue(store.sessions().isEmpty)
        // A fresh report restores the row even when its state value is unchanged.
        XCTAssertTrue(try store.receiveMessage(event(seq: 11), sender: "a"))
        XCTAssertEqual(store.sessions().map(\.id), [session.id])
        XCTAssertEqual(store.representative()?.state, "working")
    }
    func testLocalClearIsIsolatedFromOtherSourcesAndSessions() throws {
        var store = ProgramAccounting()
        XCTAssertTrue(try store.receiveMessage(event("error"), sender: "a"))
        let session = try XCTUnwrap(store.sessions().first)
        for (sender, publisher, scope) in [("b", "mac", "session"), ("a", "other", "session"), ("a", "mac", "other")] {
            XCTAssertTrue(try store.receiveMessage(event(scope: scope, publisher: publisher), sender: sender))
        }
        XCTAssertTrue(store.clearSession(id: session.id))
        XCTAssertEqual(store.sessions().count, 3)
        XCTAssertEqual(store.representative()?.state, "working")
        XCTAssertFalse(store.clearSession(id: "unknown"))
        XCTAssertTrue(try store.receiveMessage(event("blocked", seq: 2), sender: "b"))
        XCTAssertFalse(store.sessions().contains { $0.id == session.id })
        XCTAssertTrue(try store.receiveMessage(event("blocked", seq: 2), sender: "a"))
        XCTAssertEqual(store.sessions().count, 4)
        XCTAssertEqual(store.sessions().first { $0.id == session.id }?.status.state, "blocked")
    }
    func testIndividualUpdatesIsolateSourcesAndPersistClearGuards() throws {
        var store = ProgramAccounting()
        for (sender, publisher) in [("sender-a", "mac"), ("sender-b", "mac"), ("sender-a", "other")] {
            XCTAssertTrue(try store.receiveMessage(event(seq: 50, publisher: publisher), sender: sender))
        }
        XCTAssertEqual(store.sessions(now: 2_000_000).count, 3)
        XCTAssertTrue(try store.receiveMessage(event("clear", seq: 51), sender: "sender-a"))
        XCTAssertEqual(store.sessions(now: 2_000_000).count, 2)
        XCTAssertFalse(try store.receiveMessage(event(seq: 50), sender: "sender-a"))
        XCTAssertTrue(try store.receiveMessage(event(scope: "another"), sender: "sender-a"))
        XCTAssertEqual(store.sessions(now: 2_000_000).count, 3)
        store = try JSONDecoder().decode(ProgramAccounting.self, from: JSONEncoder().encode(store))
        XCTAssertFalse(try store.receiveMessage(event(seq: 50), sender: "sender-a"))
        XCTAssertEqual(store.sessions(now: 2_000_000).count, 3)
        store.retainSenders(["sender-a"])
        XCTAssertEqual(store.sessions(now: 2_000_000).count, 2)
    }
    func testIndividualUpdatesExceedOldScopeLimitAndRejectMalformedAtomically() throws {
        var store = ProgramAccounting()
        for i in 0..<100 { XCTAssertTrue(try store.receiveMessage(event(scope: "s-\(i)"), sender: "sender")) }
        store = try JSONDecoder().decode(ProgramAccounting.self, from: JSONEncoder().encode(store))
        XCTAssertEqual(store.sessions().count, 64)
        var bad = event("error", seq: 2, scope: "s-0"); bad["seq"] = true
        XCTAssertThrowsError(try store.receiveMessage(bad, sender: "sender"))
        XCTAssertEqual(store.representative()?.state, "working")
        XCTAssertThrowsError(try store.receiveMessage(event("bogus", seq: 2), sender: "sender"))
        XCTAssertEqual(store.sessions().count, 64)
    }
    func testWholeSessionClearKeepsOtherSources() throws {
        var store = ProgramAccounting()
        _ = try store.receiveMessage(event(), sender: "a")
        _ = try store.receiveMessage(event("blocked", seq: 2, id: "permissions/one"), sender: "a")
        _ = try store.receiveMessage(event("blocked", seq: 3, id: "permissions2/two"), sender: "a")
        _ = try store.receiveMessage(event("clear", seq: 4, id: "permissions"), sender: "a")
        XCTAssertTrue(store.sessions().isEmpty)
        _ = try store.receiveMessage(event("error"), sender: "b")
        _ = try store.receiveMessage(event("clear", seq: 5), sender: "a")
        XCTAssertEqual(store.sessions().count, 1)
        XCTAssertEqual(store.sessions().first?.sender, "b")
        _ = try store.receiveMessage(event("clear", seq: 6), sender: "b")
        XCTAssertTrue(store.sessions().isEmpty)
    }
    func testUpdateEnvelopesAndDuplicateDoNotResumeManualPattern() throws {
        var store = ProgramAccounting(); var presentation = ProgramPresentation()
        for data: Any in [event(), String(data: try JSONSerialization.data(withJSONObject: event()), encoding: .utf8)!] {
            let payload: [AnyHashable: Any] = ["data": data, "shared_key": "outer"]
            let raw = ProgramUpdate.pushedUpdate(payload)!
            if try store.receiveMessage(raw, sender: "sender") { presentation.statusChanged() }
            presentation.manualWrite()
            if try store.receiveMessage(raw, sender: "sender") { presentation.statusChanged() }
            XCTAssertFalse(presentation.enabled)
        }
    }
}



extension ProgramStatusTests {
    func testCapacityPrefersAcceptedArrivalAcrossSourcesAndRestart() throws {
        var store = ProgramAccounting()
        for i in 0..<64 { XCTAssertTrue(try store.receiveMessage(event(), sender: "sender-\(i)")) }
        var fresh = event(seq: 2); fresh["updated_at"] = 1
        XCTAssertTrue(try store.receiveMessage(fresh, sender: "sender-0"))
        XCTAssertFalse(try store.receiveMessage(event(), sender: "sender-1"))
        store = try JSONDecoder().decode(ProgramAccounting.self, from: JSONEncoder().encode(store))
        XCTAssertTrue(try store.receiveMessage(event(), sender: "new-sender"))
        XCTAssertEqual(store.sessions().count, 64)
        XCTAssertTrue(store.sessions().contains { $0.sender == "sender-0" })
        XCTAssertFalse(store.sessions().contains { $0.sender == "sender-1" })
        XCTAssertFalse(try store.receiveMessage(event(), sender: "sender-1"))
        XCTAssertTrue(try store.receiveMessage(event(seq: 2), sender: "sender-1"))
        XCTAssertTrue(store.sessions().contains { $0.sender == "sender-1" })
        XCTAssertFalse(store.sessions().contains { $0.sender == "sender-2" })
        XCTAssertEqual(store.sessions().count, 64)
    }
}

extension ProgramStatusTests {
    func testCombinedActivityUsesLedgerPriorityCountsAndBoundedText() throws {
        var store = ProgramAccounting()
        _ = try store.receiveMessage(event(), sender: "a")
        var blocked = event("blocked", scope: "approval"); blocked["status"] = ["state": "blocked", "kind": "permission", "title": "Release", "msg": String(repeating: "🙂", count: 512), "progress": 50]
        _ = try store.receiveMessage(blocked, sender: "b")
        _ = try store.receiveMessage(event("done", scope: "finished"), sender: "a")
        let summary = try XCTUnwrap(SessionActivitySummary(sessions: store.sessions(now: 2_000_000)))
        XCTAssertEqual(summary.total, 3); XCTAssertEqual(summary.working, 1); XCTAssertEqual(summary.attention, 1); XCTAssertEqual(summary.done, 1)
        XCTAssertEqual(summary.title, "Release"); XCTAssertEqual(summary.statusLabel, "Needs approval"); XCTAssertEqual(summary.progress, 50)
        XCTAssertLessThanOrEqual(summary.message!.utf8.count, 512)
        XCTAssertLessThan(try JSONEncoder().encode(summary).count, 4096)
        store.retainSenders([]); XCTAssertNil(SessionActivitySummary(sessions: store.sessions()))
    }
    func testStatusEnvelopesCannotFallThroughToDirectLEDRouting() {
        for type in ["program_status_snapshot", "program_status_unknown", "scope_end", "scope_reset"] {
            let payload: [AnyHashable: Any] = ["data": ["type": type], "leds": "off"]
            XCTAssertTrue(ProgramUpdate.isStatusPayload(payload))
            XCTAssertNil(ProgramUpdate.pushedUpdate(payload))
        }
        XCTAssertFalse(ProgramUpdate.isStatusPayload(["data": ["leds": "off"]]))
    }
}
