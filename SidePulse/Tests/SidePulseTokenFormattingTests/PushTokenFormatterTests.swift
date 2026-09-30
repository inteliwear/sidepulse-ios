import Foundation
import XCTest
@testable import SidePulseTokenFormatting

final class PushTokenFormatterTests: XCTestCase {
    func testDevelopmentTokenUsesLowercaseHexAndPrefix() {
        XCTAssertEqual(
            PushTokenFormatter.format(Data([0x00, 0x0A, 0xAF, 0xFF]), environment: .development),
            "dev_000aafff"
        )
    }

    func testProductionTokenHasNoPrefix() {
        XCTAssertEqual(
            PushTokenFormatter.format(Data([0x00, 0x0A, 0xAF, 0xFF]), environment: .production),
            "000aafff"
        )
    }

    func testMissingAndInvalidEnvironmentAreRejected() {
        XCTAssertThrowsError(try APNsEnvironment.configured(nil))
        XCTAssertThrowsError(try APNsEnvironment.configured("Development"))
        XCTAssertThrowsError(try APNsEnvironment.configured("sandbox"))
    }

    func testDevelopmentRecoveryEndpointPreservesPrefix() throws {
        let server = try XCTUnwrap(URL(string: "https://bridge.example"))
        XCTAssertEqual(
            PushRecoveryEndpoint.queued(server: server, token: "dev_000aafff").path,
            "/api/leds/apns_dev_000aafff/queued"
        )
    }
}
