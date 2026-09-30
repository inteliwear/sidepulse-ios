import XCTest
@testable import SidePulseTokenFormatting

final class PairingRegistrationGateTests: XCTestCase {
    func testCachedTokenCannotSubmitUntilFreshCallback() {
        let cachedToken = "previously-cached-token"
        XCTAssertFalse(cachedToken.isEmpty)

        var gate = PairingRegistrationGate()
        let attempt = gate.beginAttempt()
        XCTAssertEqual(gate.readiness, .authorizing)
        XCTAssertFalse(gate.registrationSucceeded(currentToken: cachedToken))
        XCTAssertFalse(gate.canSubmit(for: attempt))

        XCTAssertTrue(gate.registrationRequested(for: attempt))
        XCTAssertEqual(gate.readiness, .registering)
        XCTAssertFalse(gate.canSubmit(for: attempt))

        XCTAssertFalse(gate.registrationSucceeded(currentToken: cachedToken))
        XCTAssertTrue(gate.canSubmit(for: attempt))
    }

    func testRegistrationFailureAndTimeoutStopSubmission() {
        var failedGate = PairingRegistrationGate()
        let failedAttempt = failedGate.beginAttempt()
        XCTAssertTrue(failedGate.registrationRequested(for: failedAttempt))
        XCTAssertTrue(failedGate.failRegistration(for: failedAttempt))
        XCTAssertEqual(failedGate.readiness, .failed)
        XCTAssertFalse(failedGate.canSubmit(for: failedAttempt))

        var timedOutGate = PairingRegistrationGate()
        let timedOutAttempt = timedOutGate.beginAttempt()
        XCTAssertTrue(timedOutGate.registrationRequested(for: timedOutAttempt))
        XCTAssertTrue(timedOutGate.failRegistration(for: timedOutAttempt))
        XCTAssertFalse(timedOutGate.canSubmit(for: timedOutAttempt))
    }

    func testCancellationAndSupersededAttemptCannotSubmit() {
        var gate = PairingRegistrationGate()
        let cancelledAttempt = gate.beginAttempt()
        gate.cancel(cancelledAttempt)
        let currentAttempt = gate.beginAttempt()
        XCTAssertTrue(gate.registrationRequested(for: currentAttempt))
        XCTAssertFalse(gate.registrationSucceeded(currentToken: "dev_new"))

        XCTAssertFalse(gate.canSubmit(for: cancelledAttempt))
        XCTAssertTrue(gate.canSubmit(for: currentAttempt))
    }

    func testSubmissionCanOnlyBeClaimedOnce() {
        var gate = PairingRegistrationGate()
        let attempt = gate.beginAttempt()
        XCTAssertTrue(gate.registrationRequested(for: attempt))
        XCTAssertFalse(gate.registrationSucceeded(currentToken: "dev_current"))

        XCTAssertTrue(gate.claimSubmission(for: attempt, token: "dev_current"))
        XCTAssertFalse(gate.claimSubmission(for: attempt, token: "dev_current"))
    }

    func testChangedTokenDuringSubmissionRequiresAnotherAttempt() {
        var gate = PairingRegistrationGate()
        let attempt = gate.beginAttempt()
        XCTAssertTrue(gate.registrationRequested(for: attempt))
        XCTAssertFalse(gate.registrationSucceeded(currentToken: "dev_first"))
        XCTAssertTrue(gate.claimSubmission(for: attempt, token: "dev_first"))

        XCTAssertTrue(gate.registrationSucceeded(currentToken: "dev_second"))
        gate.cancel(attempt)
        XCTAssertFalse(gate.canSubmit(for: attempt))
    }

    func testChangedLinkedTokenCannotBeMarkedLinkedByAReceivedPush() {
        XCTAssertTrue(PushLinkPolicy.requiresRelinking(
            isLinked: true,
            linkedToken: "old_token",
            freshToken: "dev_new_token"
        ))
        XCTAssertFalse(PushLinkPolicy.canInferLinkFromPush(
            requiresRelinking: true,
            linkedToken: "old_token",
            currentToken: "dev_new_token"
        ))
    }
}
