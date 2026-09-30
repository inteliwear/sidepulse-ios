import Foundation
import XCTest
@testable import SidePulseTokenFormatting

final class PushKeyRegistryTests: XCTestCase {
    func testAgentLinkContainsCompleteChannelOnlyInFragment() throws {
        var registry = PushKeyRegistry()
        let key = registry.issue(name: "AI agent")
        for prefix in ["", "dev_"] {
            let deviceToken = prefix + String(repeating: "ab", count: 32)
            let link = try XCTUnwrap(key.agentControlURL(for: deviceToken))
            XCTAssertEqual(link.scheme, "https")
            XCTAssertEqual(link.host, "bridge.sidepulse.io")
            XCTAssertEqual(link.path, "/agents")
            XCTAssertNil(link.query)
            XCTAssertEqual(link.fragment, "apns_" + deviceToken + "_" + key.value)
            XCTAssertEqual(link, key.agentControlURL(for: deviceToken))
        }
        XCTAssertEqual(registry.records.count, 1)
        XCTAssertTrue(registry.accepts(key.value))
        registry.remove(id: key.id)
        XCTAssertFalse(registry.accepts(key.value))
        for invalid in ["", "dev_", "not-a-token", String(repeating: "a", count: 63), "ab#fragment"] {
            XCTAssertNil(key.agentControlURL(for: invalid))
        }
    }

    func testIssuedKeysAreDistinctAndOnlyShowFourCharacterSuffix() {
        var registry = PushKeyRegistry()
        let first = registry.issue(name: "Mac")
        let second = registry.issue(name: "Server")
        XCTAssertNotEqual(first.value, second.value)
        XCTAssertEqual(first.value.count, 32)
        XCTAssertEqual(first.maskedKey, "…" + String(first.value.suffix(4)))
        XCTAssertEqual(first.token(for: "dev_abc"), "dev_abc_" + first.value)
        XCTAssertNil(first.lastActiveAt)
        XCTAssertEqual(first.totalReceived, 0)
    }

    func testRemovedUnknownAndMissingKeysNeverReactivateAfterReload() throws {
        var registry = PushKeyRegistry()
        let removed = registry.issue(name: "Removed")
        let active = registry.issue(name: "Active")
        registry.remove(id: removed.id)
        registry = try JSONDecoder().decode(PushKeyRegistry.self, from: JSONEncoder().encode(registry))
        for key in [nil, "", "unknown", removed.value] {
            XCTAssertFalse(registry.accepts(key))
            XCTAssertEqual(registry.receive(key: key, messageID: "message"), .rejected)
        }
        XCTAssertEqual(registry.records.map(\.id), [active.id])
        XCTAssertEqual(registry.records[0].totalReceived, 0)
        XCTAssertNil(registry.records[0].lastActiveAt)
    }

    func testCountsAndLastActivityPersistAndDeduplicateAcrossPushAndRecovery() throws {
        var registry = PushKeyRegistry()
        let first = registry.issue(name: "Mac")
        let second = registry.issue(name: "Other Mac")
        let receivedAt = Date(timeIntervalSince1970: 1234)
        XCTAssertEqual(registry.receive(key: first.value, messageID: "same-event", now: receivedAt), .accepted)
        registry = try JSONDecoder().decode(PushKeyRegistry.self, from: JSONEncoder().encode(registry))
        XCTAssertEqual(registry.receive(key: first.value, messageID: "same-event"), .duplicate)
        XCTAssertEqual(registry.records[0].totalReceived, 1)
        XCTAssertEqual(registry.records[0].lastActiveAt, receivedAt)
        XCTAssertEqual(registry.receive(key: second.value, messageID: "same-event"), .accepted)
        XCTAssertEqual(registry.records[1].totalReceived, 1)
        XCTAssertEqual(registry.receive(key: first.value, messageID: "next-event"), .accepted)
        XCTAssertEqual(registry.records[0].totalReceived, 2)
    }

    func testSharedKeyMustComeFromTopLevelAndIsNotTrimmedOrChanged() {
        let key = "AbCd_sender-1234"
        let resolution = PushPayloadResolver.resolve(userInfo: [
            "shared_key": key,
            "sidepulse_push_id": "bridge-message",
            "data": ["sidepulse_event_id": "sender-event", "shared_key": "spoofed"],
            "leds": "off"
        ])
        XCTAssertEqual(resolution.sharedKey, key)
        XCTAssertEqual(resolution.pushID, "bridge-message")
        XCTAssertEqual(resolution.receiptID, "sender-event")
        XCTAssertEqual(resolution.resolvedLEDText, "off")
        XCTAssertNil(PushPayloadResolver.resolve(userInfo: ["data": ["shared_key": key]]).sharedKey)
        XCTAssertEqual(PushPayloadResolver.resolve(userInfo: ["shared_key": " \(key)"]).sharedKey, " \(key)")
    }

    func testPayloadSummaryMasksFullKeysIncludingNestedFields() {
        let key = "SECRET_VALUE_1234"
        let resolution = PushPayloadResolver.resolve(userInfo: [
            "shared_key": key,
            "data": ["shared_key": key],
            "items": [["shared_key": key]]
        ])
        XCTAssertFalse(resolution.payloadSummary.contains(key))
        XCTAssertTrue(resolution.payloadSummary.contains("…1234"))
    }
}
