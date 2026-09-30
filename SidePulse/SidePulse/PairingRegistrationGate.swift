import Foundation

enum APNsRegistrationReadiness: Equatable {
    case cached
    case authorizing
    case registering
    case ready
    case failed
}

struct PairingRegistrationGate {
    private(set) var readiness: APNsRegistrationReadiness = .cached
    private(set) var activeAttemptID: UUID?
    private var submissionClaimed = false
    private var submittedToken: String?

    @discardableResult
    mutating func beginAttempt() -> UUID {
        let id = UUID()
        activeAttemptID = id
        readiness = .authorizing
        submissionClaimed = false
        submittedToken = nil
        return id
    }

    mutating func registrationRequested(for id: UUID) -> Bool {
        guard activeAttemptID == id, readiness == .authorizing else { return false }
        readiness = .registering
        return true
    }

    mutating func registrationSucceeded(currentToken: String) -> Bool {
        if activeAttemptID != nil, readiness == .authorizing {
            return false
        }
        readiness = .ready
        return submissionClaimed && submittedToken != currentToken
    }

    mutating func failRegistration(for id: UUID) -> Bool {
        guard activeAttemptID == id else { return false }
        readiness = .failed
        activeAttemptID = nil
        submissionClaimed = false
        submittedToken = nil
        return true
    }

    func canSubmit(for id: UUID) -> Bool {
        activeAttemptID == id && readiness == .ready && !submissionClaimed
    }

    mutating func claimSubmission(for id: UUID, token: String) -> Bool {
        guard canSubmit(for: id), !token.isEmpty else { return false }
        submissionClaimed = true
        submittedToken = token
        return true
    }

    mutating func cancel(_ id: UUID) {
        guard activeAttemptID == id else { return }
        activeAttemptID = nil
        submissionClaimed = false
        submittedToken = nil
        if readiness == .authorizing || readiness == .registering { readiness = .cached }
    }

    mutating func finish(_ id: UUID) {
        guard activeAttemptID == id else { return }
        activeAttemptID = nil
        submissionClaimed = false
        submittedToken = nil
    }
}

enum PushLinkPolicy {
    static func requiresRelinking(isLinked: Bool, linkedToken: String, freshToken: String) -> Bool {
        (isLinked || !linkedToken.isEmpty) && linkedToken != freshToken
    }

    static func canInferLinkFromPush(
        requiresRelinking: Bool,
        linkedToken: String,
        currentToken: String
    ) -> Bool {
        !requiresRelinking && (linkedToken.isEmpty || linkedToken == currentToken)
    }
}
