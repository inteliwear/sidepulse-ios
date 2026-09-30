import XCTest
@testable import SidePulseTokenFormatting

final class PushNotificationCleanupTests: XCTestCase {
    func testWriteReceiptsAreScopedToSenderAndMessage() throws {
        let sender = UUID()
        let receipt = ReceivedPush(source: "Push", title: "Update", body: "", ledText: "off",
                                   payloadSummary: "", writeStatus: .wrote,
                                   pushID: "first", senderKeyID: sender)
        let first = PushPayloadResolver.resolve(userInfo: ["sidepulse_push_id": "first", "leds": "off"])
        let second = PushPayloadResolver.resolve(userInfo: ["sidepulse_push_id": "second", "leds": "off"])
        XCTAssertTrue(receipt.matchesReceipt(first, senderID: sender))
        XCTAssertFalse(receipt.matchesReceipt(first, senderID: UUID()))
        XCTAssertFalse(receipt.matchesReceipt(first, senderID: nil))
        XCTAssertFalse(receipt.matchesReceipt(second, senderID: sender))
        XCTAssertFalse(receipt.matchesReceipt(PushPayloadResolver.resolve(userInfo: ["leds": "off"]), senderID: sender))
        let restored = try JSONDecoder().decode(ReceivedPush.self, from: JSONEncoder().encode(receipt))
        XCTAssertTrue(restored.matchesReceipt(first, senderID: sender))
    }

    func testOlderInboxRemainsReadableWithoutReceiptIdentity() throws {
        let receipt = ReceivedPush(source: "Push", title: "Update", body: "", ledText: "off",
                                   payloadSummary: "", writeStatus: .wrote)
        let restored = try JSONDecoder().decode(ReceivedPush.self, from: JSONEncoder().encode(receipt))
        XCTAssertNil(restored.pushID)
        XCTAssertNil(restored.senderKeyID)
    }

    func testUnauthorizedNotificationsAreClearedEvenWithoutLEDData() {
        var registry = PushKeyRegistry()
        let active = registry.issue(name: "Mac")
        let removed = registry.issue(name: "Removed")
        registry.remove(id: removed.id)
        for key in [nil, "unknown", removed.value] {
            var payload: [AnyHashable: Any] = ["aps": ["alert": "Ignored notification"]]
            if let key { payload["shared_key"] = key }
            let resolution = PushPayloadResolver.resolve(userInfo: payload)
            XCTAssertTrue(resolution.shouldClearNotification(isAuthorized: registry.accepts(resolution.sharedKey)))
        }
        let resolution = PushPayloadResolver.resolve(userInfo: ["shared_key": active.value, "leds": "off"])
        XCTAssertFalse(resolution.shouldClearNotification(isAuthorized: registry.accepts(resolution.sharedKey)))
    }

    func testMatchingDoesNotClearAnotherSenderOrAnotherMessage() {
        let rejected = PushPayloadResolver.resolve(userInfo: ["shared_key": "removed", "sidepulse_push_id": "one", "leds": "off"])
        XCTAssertTrue(rejected.matchesNotification(PushPayloadResolver.resolve(userInfo: ["shared_key": "removed", "sidepulse_push_id": "one", "leds": "off"])))
        XCTAssertFalse(rejected.matchesNotification(PushPayloadResolver.resolve(userInfo: ["shared_key": "active", "sidepulse_push_id": "one", "leds": "off"])))
        XCTAssertFalse(rejected.matchesNotification(PushPayloadResolver.resolve(userInfo: ["shared_key": "removed", "sidepulse_push_id": "two", "leds": "off"])))
        XCTAssertFalse(rejected.matchesNotification(PushPayloadResolver.resolve(userInfo: ["shared_key": "removed", "leds": "off"])))
    }

    func testEventMetadataMatchesAcrossAPNsAndRecovery() {
        let push = PushPayloadResolver.resolve(userInfo: ["shared_key": "sender", "data": ["sidepulse_event_id": "event"], "aps": ["alert": ["title": "Update"]]])
        let recovery = PushPayloadResolver.resolve(userInfo: ["shared_key": "sender", "data": ["sidepulse_event_id": "event"], "title": "Update"])
        XCTAssertTrue(push.matchesNotification(recovery))
    }

    func testLegacyMatchingUsesContentAndIncludesUnsupportedPatterns() {
        let first = PushPayloadResolver.resolve(userInfo: ["pattern": "unsupported", "title": "Update"])
        XCTAssertTrue(first.isLEDUpdate)
        XCTAssertTrue(first.matchesNotification(PushPayloadResolver.resolve(userInfo: ["pattern": "unsupported", "title": "Update"])))
        XCTAssertFalse(first.matchesNotification(PushPayloadResolver.resolve(userInfo: ["pattern": "other", "title": "Update"])))
        for alias in ["LEDS.txt", "LEDS.TXT"] {
            let resolution = PushPayloadResolver.resolve(userInfo: [AnyHashable(alias): "off"])
            XCTAssertTrue(resolution.isLEDUpdate)
            XCTAssertEqual(resolution.resolvedLEDText, "off")
        }
    }
}
