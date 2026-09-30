// Copyright (c) 2026 InteliWEAR LLC.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import UIKit
import UserNotifications

enum PairingRequestError: LocalizedError {
    case invalidLink
    case unsupportedVersion
    case invalidServer
    case invalidChannel

    var errorDescription: String? {
        switch self {
        case .invalidLink: "This SidePulse pairing link is invalid."
        case .unsupportedVersion: "This SidePulse pairing link uses an unsupported version."
        case .invalidServer: "The pairing link contains an invalid bridge server."
        case .invalidChannel: "The pairing link contains an invalid channel."
        }
    }
}

struct IOSPairingRequest: Identifiable, Equatable {
    let server: URL
    let channel: String
    let sender: String
    let requiresConfirmation: Bool

    var id: String { channel }

    static func parse(_ url: URL) throws -> IOSPairingRequest {
        guard url.scheme?.lowercased() == "sidepulse" else {
            throw PairingRequestError.invalidLink
        }
        if url.host?.lowercased() == "p" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  components.query == nil, components.fragment == nil else {
                throw PairingRequestError.invalidLink
            }
            let channel = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard isCompactChannel(channel),
                  let server = URL(string: "https://bridge.sidepulse.io") else {
                throw PairingRequestError.invalidChannel
            }
            return IOSPairingRequest(
                server: server,
                channel: channel,
                sender: "your computer",
                requiresConfirmation: false
            )
        }
        guard url.host?.lowercased() == "pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw PairingRequestError.invalidLink
        }
        let values = Dictionary(
            components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [],
            uniquingKeysWith: { _, latest in latest }
        )
        guard values["v"] == "1" else {
            throw PairingRequestError.unsupportedVersion
        }
        guard let channelText = values["channel"] else {
            throw PairingRequestError.invalidChannel
        }
        let channel: String
        if isCompactChannel(channelText) {
            channel = channelText
        } else if let legacyChannel = UUID(uuidString: channelText) {
            channel = legacyChannel.uuidString.lowercased()
        } else {
            throw PairingRequestError.invalidChannel
        }
        guard let serverText = values["server"], let server = URL(string: serverText),
              let serverComponents = URLComponents(url: server, resolvingAgainstBaseURL: false),
              let host = serverComponents.host, !host.isEmpty,
              serverComponents.user == nil, serverComponents.password == nil,
              serverComponents.query == nil, serverComponents.fragment == nil,
              serverComponents.path.isEmpty || serverComponents.path == "/" else {
            throw PairingRequestError.invalidServer
        }
        let scheme = serverComponents.scheme?.lowercased()
        var schemeAllowed = scheme == "https"
#if DEBUG
        if scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(host.lowercased()) {
            schemeAllowed = true
        }
#endif
        guard schemeAllowed else {
            throw PairingRequestError.invalidServer
        }
        var normalized = serverComponents
        normalized.path = ""
        guard let normalizedServer = normalized.url else {
            throw PairingRequestError.invalidServer
        }
        let sender = String((values["sender"] ?? "Your computer").prefix(80))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return IOSPairingRequest(
            server: normalizedServer,
            channel: channel,
            sender: sender.isEmpty ? "Your computer" : sender,
            requiresConfirmation: true
        )
    }

    private static func isCompactChannel(_ value: String) -> Bool {
        value.count == 11 && value.unicodeScalars.allSatisfy {
            (65...90).contains($0.value)
                || (97...122).contains($0.value)
                || (48...57).contains($0.value)
                || $0.value == 45
                || $0.value == 95
        }
    }
}

struct PairingNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct ServerLEDUpdateResult {
    let queuedCount: Int
    let handledCount: Int
}

enum ServerLEDUpdateError: LocalizedError {
    case missingPushToken
    case noFolderSelected
    case invalidBridgeURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingPushToken:
            return "SidePulse does not have a push token yet. Open the app and try again."
        case .noFolderSelected:
            return "Select the SidePulse Dot folder in the app before updating the LEDs."
        case .invalidBridgeURL:
            return "The saved SidePulse bridge URL is invalid."
        case .invalidResponse:
            return "The SidePulse server returned an invalid response."
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var pushToken: String {
        didSet { UserDefaults.standard.set(pushToken, forKey: Defaults.pushToken) }
    }
    @Published private(set) var registrationReadiness: APNsRegistrationReadiness = .cached

    @Published var selectedFolderPath: String = "No USB folder selected"
    @Published var hasFolderAccess: Bool = false

    @Published var ledText: String {
        didSet { UserDefaults.standard.set(ledText, forKey: Defaults.ledText) }
    }

    @Published var serverBaseURL: String {
        didSet { UserDefaults.standard.set(serverBaseURL, forKey: Defaults.serverBaseURL) }
    }

    @Published var sharedSecret: String {
        didSet { UserDefaults.standard.set(sharedSecret, forKey: Defaults.sharedSecret) }
    }

    @Published var bridgeBaseURL: String {
        didSet { UserDefaults.standard.set(bridgeBaseURL, forKey: Defaults.bridgeBaseURL) }
    }

    @Published var isBridgeLinked: Bool {
        didSet { UserDefaults.standard.set(isBridgeLinked, forKey: Defaults.isBridgeLinked) }
    }

    @Published private(set) var requiresRelinking: Bool {
        didSet { UserDefaults.standard.set(requiresRelinking, forKey: Defaults.requiresRelinking) }
    }

    @Published var hasReceivedRemotePush: Bool {
        didSet { UserDefaults.standard.set(hasReceivedRemotePush, forKey: Defaults.hasReceivedRemotePush) }
    }

    @Published var pendingPairing: IOSPairingRequest?
    @Published var pairingInProgress = false
    @Published var pairingError: String?
    @Published var pairingSuccessMessage: String?
    @Published var pairingNotice: PairingNotice?
    @Published var lastRecoveryStatus = "Not checked"

    private var recoveryInProgress = false
    private var lastRecoveryAttempt: Date?
    private var recoveryWaiters: [CheckedContinuation<Void, Never>] = []
    private var pushTokenTimeoutTask: Task<Void, Never>?
    private var pairingRegistration = PairingRegistrationGate()
    private var linkedPushToken: String
    private var pairingKeyID: UUID?
    @Published private var pushKeys: PushKeyRegistry {
        didSet {
            if let data = try? JSONEncoder().encode(pushKeys) {
                UserDefaults.standard.set(data, forKey: Defaults.pushKeys)
            }
        }
    }

    var activePushKeys: [PushKeyRecord] {
        pushKeys.records.sorted { ($0.lastActiveAt ?? $0.createdAt) > ($1.lastActiveAt ?? $1.createdAt) }
    }

    func createPushKey(name: String = "Manual sender") -> PushKeyRecord {
        pushKeys.issue(name: name)
    }

    func removePushKey(_ id: UUID) {
        guard let key = pushKeys.records.first(where: { $0.id == id }) else { return }
        pushKeys.remove(id: id)
        if pushKeys.records.isEmpty {
            isBridgeLinked = false
            requiresRelinking = true
        }
        if pairingKeyID == id { failPairing("The pairing key was removed. Start pairing again.") }
        lastMessage = "Removed key \(key.maskedKey)"
        EventLog.append(lastMessage)
        refreshEventLog()
        Task { await clearUnauthorizedNotifications() }
    }

    func acceptsPush(_ userInfo: [AnyHashable: Any]) -> Bool {
        pushKeys.accepts(PushPayloadResolver.resolve(userInfo: userInfo).sharedKey)
    }

    @Published var lastMessage: String = "Ready"
    @Published var eventLog: [String] = []
    @Published var receivedPushes: [ReceivedPush] {
        didSet { persistReceivedPushes() }
    }

    private enum Defaults {
        static let pushToken = "pushToken"
        static let linkedPushToken = "linkedPushToken"
        static let ledText = "ledText"
        static let serverBaseURL = "serverBaseURL"
        static let sharedSecret = "sharedSecret"
        static let bridgeBaseURL = "bridgeBaseURL"
        static let isBridgeLinked = "isBridgeLinked"
        static let requiresRelinking = "requiresRelinking"
        static let hasReceivedRemotePush = "hasReceivedRemotePush"
        static let receivedPushes = "receivedPushes"
        static let processedEventIDs = "processedEventIDs"
        static let pushKeys = "pushKeys"
    }

    private init() {
        let cachedPushToken = UserDefaults.standard.string(forKey: Defaults.pushToken) ?? ""
        let savedLinkedPushToken = UserDefaults.standard.string(forKey: Defaults.linkedPushToken) ?? ""
        let savedIsBridgeLinked = UserDefaults.standard.bool(forKey: Defaults.isBridgeLinked)
        let savedRequiresRelinking = UserDefaults.standard.bool(forKey: Defaults.requiresRelinking)
        let savedKeys = UserDefaults.standard.data(forKey: Defaults.pushKeys)
            .flatMap { try? JSONDecoder().decode(PushKeyRegistry.self, from: $0) } ?? PushKeyRegistry()
        let needsKeyPairing = savedIsBridgeLinked && savedKeys.records.isEmpty
        self.pushKeys = savedKeys
        self.pushToken = cachedPushToken
        self.linkedPushToken = savedIsBridgeLinked && savedLinkedPushToken.isEmpty
            ? cachedPushToken
            : savedLinkedPushToken
        self.ledText = UserDefaults.standard.string(forKey: Defaults.ledText) ?? """
        off
        #404040 1.4s pulse
        off 400ms none
        repeat
        """
        self.serverBaseURL = UserDefaults.standard.string(forKey: Defaults.serverBaseURL) ?? "http://127.0.0.1:8787"
        self.sharedSecret = UserDefaults.standard.string(forKey: Defaults.sharedSecret) ?? ""
        self.bridgeBaseURL = UserDefaults.standard.string(forKey: Defaults.bridgeBaseURL)
            ?? "https://bridge.sidepulse.io"
        self.isBridgeLinked = savedIsBridgeLinked && !savedRequiresRelinking && !needsKeyPairing
        self.requiresRelinking = savedRequiresRelinking || needsKeyPairing
        let savedPushes = Self.loadReceivedPushes()
        self.hasReceivedRemotePush = UserDefaults.standard.bool(forKey: Defaults.hasReceivedRemotePush)
            || savedPushes.contains { Self.isRemotePushSource($0.source) }
        self.pendingPairing = nil
        self.receivedPushes = savedPushes
        self.eventLog = EventLog.entries()
        refreshFolderStatus()
    }

    func setPushToken(from deviceToken: Data) {
        pushTokenTimeoutTask?.cancel()
        pushTokenTimeoutTask = nil
        let environment: APNsEnvironment
        do {
            environment = try APNsEnvironment.configured(
                Bundle.main.object(forInfoDictionaryKey: "SidePulseAPNSEnvironment") as? String
            )
        } catch {
            registrationReadiness = .failed
            if pairingRegistration.activeAttemptID != nil, pairingInProgress {
                failPairing(error.localizedDescription, registrationFailed: true)
            } else {
                pairingNotice = PairingNotice(title: "Build Configuration Error", message: error.localizedDescription)
            }
            return
        }
        let previousToken = pushToken
        let formattedToken = PushTokenFormatter.format(deviceToken, environment: environment)
        pushToken = formattedToken
        let tokenChangedDuringSubmission = pairingRegistration.registrationSucceeded(
            currentToken: formattedToken
        )
        registrationReadiness = pairingRegistration.readiness
        if PushLinkPolicy.requiresRelinking(
            isLinked: isBridgeLinked,
            linkedToken: linkedPushToken,
            freshToken: formattedToken
        ) {
            let shouldShowRelinkNotice = !requiresRelinking
            requiresRelinking = true
            isBridgeLinked = false
            pairingSuccessMessage = nil
            if shouldShowRelinkNotice {
                pairingNotice = PairingNotice(
                    title: "Link SidePulse Again",
                    message: "The push token changed. Start a new pairing from your desktop so it receives the current token."
                )
            }
        }
        EventLog.append("APNs token updated")
        lastMessage = previousToken == formattedToken ? "Push token refreshed" : "Push token updated"
        refreshEventLog()
        if tokenChangedDuringSubmission {
            failPairing("The push token changed while linking. Start pairing again so the desktop receives the current token.")
        } else if pairingRegistration.activeAttemptID != nil, pairingInProgress {
            submitPendingPairingIfReady()
        }
        recoverQueuedPushes()
    }

    @discardableResult
    func receivePairingURL(_ url: URL) -> Bool {
        do {
            let pairing = try IOSPairingRequest.parse(url)
            supersedePairingAttempt()
            EventLog.append("Pairing link received")
            pendingPairing = pairing
            pairingError = nil
            pairingSuccessMessage = nil
            pairingInProgress = false
            if !pairing.requiresConfirmation {
                confirmPairing()
            }
            return true
        } catch {
            recordError(error)
            pairingNotice = PairingNotice(
                title: "Couldn’t Link iPhone",
                message: error.localizedDescription
            )
            return false
        }
    }

    func confirmPairing() {
        guard pendingPairing != nil else { return }
        do {
            _ = try APNsEnvironment.configured(
                Bundle.main.object(forInfoDictionaryKey: "SidePulseAPNSEnvironment") as? String
            )
        } catch {
            registrationReadiness = .failed
            failPairing(error.localizedDescription)
            return
        }
        supersedePairingAttempt()
        let attemptID = pairingRegistration.beginAttempt()
        registrationReadiness = pairingRegistration.readiness
        pairingInProgress = true
        pairingError = nil
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
            granted, error in
            Task { @MainActor in
                guard self.pairingRegistration.activeAttemptID == attemptID, self.pairingInProgress else { return }
                if let error {
                    self.failPairing(error.localizedDescription)
                    return
                }
                guard granted else {
                    self.failPairing("Notification permission is required to link this iPhone.")
                    return
                }
                guard self.pairingRegistration.registrationRequested(for: attemptID) else { return }
                self.registrationReadiness = self.pairingRegistration.readiness
                self.lastMessage = "Waiting for a fresh APNs registration"
                UIApplication.shared.registerForRemoteNotifications()
                self.pushTokenTimeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                    guard !Task.isCancelled, let self,
                          self.pairingRegistration.activeAttemptID == attemptID,
                          self.pairingInProgress,
                          self.registrationReadiness != .ready else { return }
                    self.failPairing(
                        "APNs registration did not finish. Check your network connection and notification settings, then try pairing again.",
                        registrationFailed: true
                    )
                }
            }
        }
    }

    func cancelPairing() {
        supersedePairingAttempt()
        pendingPairing = nil
        pairingInProgress = false
        pairingError = nil
        pairingSuccessMessage = nil
    }

    func failPairing(_ message: String, registrationFailed: Bool = false) {
        discardPendingPairingKey()
        pushTokenTimeoutTask?.cancel()
        pushTokenTimeoutTask = nil
        pairingInProgress = false
        if let attemptID = pairingRegistration.activeAttemptID {
            if registrationFailed {
                _ = pairingRegistration.failRegistration(for: attemptID)
            } else {
                pairingRegistration.cancel(attemptID)
            }
            registrationReadiness = pairingRegistration.readiness
        }
        pairingError = message
        lastMessage = message
    }

    func failRemoteNotificationRegistration(_ error: Error) {
        if pendingPairing != nil,
           pairingInProgress,
           pairingRegistration.readiness != .authorizing {
            registrationReadiness = .failed
            failPairing(
                "Could not register for push notifications: \(error.localizedDescription)",
                registrationFailed: true
            )
        } else {
            recordError(error)
        }
    }

    private func submitPendingPairingIfReady() {
        let token = pushToken
        guard let pairing = pendingPairing,
              let attemptID = pairingRegistration.activeAttemptID,
              pairingRegistration.claimSubmission(for: attemptID, token: token) else { return }
        pairingInProgress = true
        pairingError = nil
        let deviceName = UIDevice.current.name
        let key = createPushKey(name: pairing.sender)
        pairingKeyID = key.id
        let sharedToken = key.token(for: token)
        Task {
            do {
                let endpoint = pairing.server
                    .appendingPathComponent("api")
                    .appendingPathComponent("leds")
                    .appendingPathComponent(pairing.channel)
                let body: [String: Any] = [
                    "v": 1,
                    "type": "ios_registration",
                    "device": [
                        "name": deviceName,
                        "platform": "ios",
                        "bundle_id": "io.sidepulse.ios",
                        "push_token": sharedToken,
                    ],
                ]
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (_, response) = try await URLSession.shared.data(for: request)
                guard self.pairingRegistration.activeAttemptID == attemptID, self.pairingInProgress else { return }
                guard self.pushToken == token else {
                    failPairing("The push token changed while linking. Start pairing again so the desktop receives the current token.")
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                bridgeBaseURL = pairing.server.absoluteString.trimmingCharacters(
                    in: CharacterSet(charactersIn: "/")
                )
                isBridgeLinked = true
                linkedPushToken = token
                UserDefaults.standard.set(token, forKey: Defaults.linkedPushToken)
                requiresRelinking = false
                pairingKeyID = nil
                pairingRegistration.finish(attemptID)
                pushTokenTimeoutTask?.cancel()
                pushTokenTimeoutTask = nil
                pairingInProgress = false
                lastMessage = "Linked to \(pairing.sender)"
                EventLog.append("Linked to \(pairing.sender) through \(pairing.server.host ?? "bridge")")
                refreshEventLog()
                pairingSuccessMessage = "SidePulse writes from \(pairing.sender) will now arrive on this iPhone."
            } catch {
                guard self.pairingRegistration.activeAttemptID == attemptID else { return }
                failPairing("Could not complete pairing: \(error.localizedDescription)")
            }
        }
    }

    private func discardPendingPairingKey() {
        if let id = pairingKeyID { pushKeys.remove(id: id) }
        pairingKeyID = nil
    }

    private func supersedePairingAttempt() {
        discardPendingPairingKey()
        pushTokenTimeoutTask?.cancel()
        pushTokenTimeoutTask = nil
        if let attemptID = pairingRegistration.activeAttemptID {
            pairingRegistration.cancel(attemptID)
            registrationReadiness = pairingRegistration.readiness
        }
    }

    func refreshFolderStatus() {
        hasFolderAccess = DriveWriter.shared.hasSavedFolder
        selectedFolderPath = DriveWriter.shared.savedFolderDisplayName
    }

    func recordWriteSuccess(_ message: String) {
        EventLog.append(message)
        lastMessage = message
        refreshFolderStatus()
        refreshEventLog()
    }

    func recordError(_ error: Error) {
        let message = error.localizedDescription
        EventLog.append("Error: \(message)")
        lastMessage = message
        refreshFolderStatus()
        refreshEventLog()
    }

    func recordReceivedPush(_ push: ReceivedPush) {
        var next = [push]
        next.append(contentsOf: receivedPushes)
        if next.count > 50 {
            next.removeLast(next.count - 50)
        }
        receivedPushes = next

        let status = push.writeStatus.displayName
        EventLog.append("\(push.source): \(push.title) (\(status))")
        lastMessage = "\(push.title) - \(status)"
        refreshFolderStatus()
        refreshEventLog()
    }

    @discardableResult
    func processPush(_ userInfo: [AnyHashable: Any], source: String) -> Bool {
        let resolution = PushPayloadResolver.resolve(userInfo: userInfo)
        return processResolvedPush(resolution, source: source)
    }

    var shouldShowLinkInstructions: Bool {
        !isBridgeLinked && (!hasReceivedRemotePush || requiresRelinking)
    }

    @discardableResult
    func processResolvedPush(_ resolution: PushPayloadResolution, source: String, isRemote: Bool = true) -> Bool {
        let senderID = pushKeys.records.first { $0.value == resolution.sharedKey }?.id
        if isRemote {
            switch pushKeys.receive(key: resolution.sharedKey, messageID: resolution.receiptID) {
            case .rejected:
                EventLog.append("Ignored remote push: missing, unknown, or removed key")
                refreshEventLog()
                return false
            case .duplicate:
                let previous = receivedPushes.first { $0.matchesReceipt(resolution, senderID: senderID) }
                if previous?.writeStatus != .failed && previous?.writeStatus != .noFolder {
                    EventLog.append("Ignored duplicate SidePulse push")
                    refreshEventLog()
                    return true
                }
                // A delivery receipt is not proof that USB writing succeeded.
                // Recovery may retry after the user reconnects or selects the Dot.
            case .accepted:
                if !hasReceivedRemotePush {
                    hasReceivedRemotePush = true
                    EventLog.append("Remote push delivery confirmed")
                }
            }
        }
        if resolution.eventID != nil,
           !isBridgeLinked,
           PushLinkPolicy.canInferLinkFromPush(
               requiresRelinking: requiresRelinking,
               linkedToken: linkedPushToken,
               currentToken: pushToken
           ) {
            isBridgeLinked = true
        }
        if let eventID = resolution.eventID, processedEventIDs()[eventIdentity(eventID, sharedKey: resolution.sharedKey)] != nil {
            EventLog.append("Ignored duplicate SidePulse event")
            refreshEventLog()
            return true
        }

        var status: ReceivedPush.WriteStatus = .received
        var errorMessage: String?
        if resolution.isUnsupportedPattern {
            status = .unsupportedPattern
        } else if let ledText = resolution.resolvedLEDText {
            if DriveWriter.shared.hasSavedFolder {
                do {
                    _ = try DriveWriter.shared.write(ledText)
                    status = .wrote
                } catch {
                    status = .failed
                    errorMessage = error.localizedDescription
                }
            } else {
                status = .noFolder
            }
        }

        recordReceivedPush(
            ReceivedPush(
                source: source,
                title: resolution.displayTitle,
                body: resolution.displayBody,
                notificationTitle: resolution.sourceTitle,
                notificationBody: resolution.sourceBody,
                imageURL: resolution.imageURL,
                patternName: resolution.patternName,
                ledText: resolution.resolvedLEDText,
                payloadSummary: resolution.payloadSummary,
                writeStatus: status,
                errorMessage: errorMessage,
                eventID: resolution.eventID,
                sharedKeySuffix: resolution.sharedKey.map { String($0.suffix(4)) },
                pushID: resolution.pushID,
                senderKeyID: senderID
            )
        )
        if let eventID = resolution.eventID, status != .failed, status != .noFolder {
            markEventProcessed(eventIdentity(eventID, sharedKey: resolution.sharedKey))
        }
        return status != .failed
    }

    func processPushAndCleanUp(_ userInfo: [AnyHashable: Any], source: String) async -> Bool {
        let previousID = receivedPushes.first?.id
        let didHandle = processPush(userInfo, source: source)
        let resolution = PushPayloadResolver.resolve(userInfo: userInfo)
        let senderID = pushKeys.records.first { $0.value == resolution.sharedKey }?.id
        // Use this receipt's latest attempt; another sender or an older write of
        // identical LED text must never hide a notification for a failed update.
        let matchingReceipt = receivedPushes.first { $0.matchesReceipt(resolution, senderID: senderID) }
        let newReceipt = receivedPushes.first.flatMap { $0.id != previousID ? $0 : nil }
        let wasWritten = (newReceipt ?? matchingReceipt)?.writeStatus == .wrote
        let unauthorized = resolution.shouldClearNotification(isAuthorized: pushKeys.accepts(resolution.sharedKey))
        if unauthorized || (didHandle && wasWritten && resolution.isLEDUpdate) {
            let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
            let identifiers = notifications.compactMap { notification -> String? in
                let delivered = PushPayloadResolver.resolve(userInfo: notification.request.content.userInfo)
                return resolution.matchesNotification(delivered) ? notification.request.identifier : nil
            }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        }
        return didHandle
    }

    private func clearUnauthorizedNotifications() async {
        let center = UNUserNotificationCenter.current()
        let notifications = await center.deliveredNotifications()
        let identifiers = notifications.compactMap { notification -> String? in
            let resolution = PushPayloadResolver.resolve(userInfo: notification.request.content.userInfo)
            return resolution.shouldClearNotification(isAuthorized: pushKeys.accepts(resolution.sharedKey))
                ? notification.request.identifier : nil
        }
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        EventLog.append("Dismissed \(identifiers.count) unauthorized notification(s)")
        refreshEventLog()
    }

    func recoverQueuedPushes() {
        Task { await clearUnauthorizedNotifications() }
        guard !pushKeys.records.isEmpty else {
            lastRecoveryStatus = "No active senders"
            return
        }
        guard !pushToken.isEmpty, !recoveryInProgress else { return }
        let now = Date()
        if let lastRecoveryAttempt, now.timeIntervalSince(lastRecoveryAttempt) < 3 {
            return
        }
        guard let server = URL(string: bridgeBaseURL) else {
            lastRecoveryStatus = "Invalid bridge URL"
            return
        }
        let endpoint = PushRecoveryEndpoint.queued(server: server, token: pushToken)
        recoveryInProgress = true
        lastRecoveryAttempt = now
        Task {
            defer { finishRecovery() }
            do {
                let result = try await fetchQueuedLEDUpdates(from: endpoint, source: "Recovered push")
                lastRecoveryStatus = result.queuedCount == 0
                    ? "Up to date"
                    : "Recovered \(result.handledCount)"
            } catch {
                lastRecoveryStatus = "Recovery failed"
                EventLog.append("Push recovery failed: \(error.localizedDescription)")
                refreshEventLog()
            }
        }
    }

    func updateLEDsFromServer() async throws -> ServerLEDUpdateResult {
        await clearUnauthorizedNotifications()
        guard !pushKeys.records.isEmpty else {
            lastRecoveryStatus = "No active senders"
            EventLog.append("Server update skipped: no active sender keys")
            refreshEventLog()
            return ServerLEDUpdateResult(queuedCount: 0, handledCount: 0)
        }
        guard !pushToken.isEmpty else {
            throw ServerLEDUpdateError.missingPushToken
        }
        guard DriveWriter.shared.hasSavedFolder else {
            throw ServerLEDUpdateError.noFolderSelected
        }
        // Run another check after the active request, since a new push may have
        // arrived after that request's server snapshot.
        while recoveryInProgress {
            await withCheckedContinuation { continuation in
                recoveryWaiters.append(continuation)
            }
        }
        guard let server = URL(string: bridgeBaseURL) else {
            throw ServerLEDUpdateError.invalidBridgeURL
        }

        let endpoint = PushRecoveryEndpoint.queued(server: server, token: pushToken)

        recoveryInProgress = true
        lastRecoveryAttempt = Date()
        defer { finishRecovery() }

        do {
            let result = try await fetchQueuedLEDUpdates(
                from: endpoint,
                source: "Shortcut server update"
            )
            lastRecoveryStatus = result.queuedCount == 0
                ? "Up to date"
                : "Updated \(result.handledCount)"
            EventLog.append(
                result.queuedCount == 0
                    ? "Shortcut server update: already up to date"
                    : "Shortcut server update: handled \(result.handledCount) queued update(s)"
            )
            refreshEventLog()
            return result
        } catch {
            lastRecoveryStatus = "Update failed"
            EventLog.append("Shortcut server update failed: \(error.localizedDescription)")
            refreshEventLog()
            throw error
        }
    }

    private func finishRecovery() {
        recoveryInProgress = false
        let waiters = recoveryWaiters
        recoveryWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func fetchQueuedLEDUpdates(
        from endpoint: URL,
        source: String
    ) async throws -> ServerLEDUpdateResult {
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let entries = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw ServerLEDUpdateError.invalidResponse
        }

        var handled = 0
        for entry in entries {
            let payload: [AnyHashable: Any]
            if let object = entry as? [String: Any] {
                payload = Dictionary(
                    uniqueKeysWithValues: object.map { (AnyHashable($0.key), $0.value) }
                )
            } else if let text = entry as? String {
                payload = [AnyHashable("leds"): text]
            } else {
                continue
            }
            let containsLEDUpdate = PushPayloadResolver.resolve(userInfo: payload).resolvedLEDText != nil
            if await processPushAndCleanUp(payload, source: source), containsLEDUpdate {
                handled += 1
            }
        }
        return ServerLEDUpdateResult(queuedCount: entries.count, handledCount: handled)
    }

    func clearReceivedPushes() {
        receivedPushes = []
        lastMessage = "Cleared received pushes"
    }

    func refreshEventLog() {
        eventLog = EventLog.entries()
    }

    func clearEventLog() {
        EventLog.clear()
        refreshEventLog()
    }

    private static func isRemotePushSource(_ source: String) -> Bool {
        source.localizedCaseInsensitiveContains("push")
            || source.localizedCaseInsensitiveContains("notification")
    }

    var preauthenticatedPostURL: String? {
        let trimmedBase = serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedBase.isEmpty, !pushToken.isEmpty else {
            return nil
        }

        var components = URLComponents(string: trimmedBase + "/v1/push")
        var items = [
            URLQueryItem(name: "device_token", value: pushToken)
        ]

        if !sharedSecret.isEmpty {
            items.append(URLQueryItem(name: "key", value: sharedSecret))
        }

        components?.queryItems = items
        return components?.url?.absoluteString
    }

    var pushEndpointURL: String? {
        let trimmedBase = serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedBase.isEmpty else {
            return nil
        }
        return trimmedBase + "/v1/push"
    }

    var curlExample: String? {
        guard let pushEndpointURL else {
            return nil
        }

        let tokenLine = pushToken.isEmpty ? "" : "\n  -d '{\"device_token\":\"<copied-token>\",\"pattern\":\"green_pulse_2\"}'"
        let authHeader = sharedSecret.isEmpty ? "" : " \\\n  -H \"Authorization: Bearer \(sharedSecret)\""
        if tokenLine.isEmpty {
            return """
            curl -X POST \(pushEndpointURL)\(authHeader) \\
              -H "content-type: application/json" \\
              -d '{"pattern":"green_pulse_2"}'
            """
        }

        return """
        curl -X POST \(pushEndpointURL)\(authHeader) \\
          -H "content-type: application/json" \(tokenLine)
        """
    }

    var shortcutWriteURL: String? {
        guard !ledText.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "sidepulse"
        components.host = "write"
        components.queryItems = [
            URLQueryItem(name: "text", value: ledText)
        ]
        return components.url?.absoluteString
    }

    func shortcutPatternURL(for pattern: LEDPattern) -> String? {
        var components = URLComponents()
        components.scheme = "sidepulse"
        components.host = "write"
        components.queryItems = [
            URLQueryItem(name: "pattern", value: pattern.name)
        ]
        return components.url?.absoluteString
    }

    private func persistReceivedPushes() {
        if let data = try? JSONEncoder().encode(receivedPushes) {
            UserDefaults.standard.set(data, forKey: Defaults.receivedPushes)
        }
    }

    private func eventIdentity(_ eventID: String, sharedKey: String?) -> String {
        let identity = pushKeys.records.first { $0.value == sharedKey }?.id.uuidString ?? "local"
        return identity + ":" + eventID
    }

    private func processedEventIDs() -> [String: TimeInterval] {
        let stored = UserDefaults.standard.dictionary(forKey: Defaults.processedEventIDs)
            as? [String: TimeInterval] ?? [:]
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60).timeIntervalSince1970
        return stored.filter { $0.value >= cutoff }
    }

    private func markEventProcessed(_ eventID: String) {
        var stored = processedEventIDs()
        stored[eventID] = Date().timeIntervalSince1970
        if stored.count > 100 {
            for key in stored.sorted(by: { $0.value < $1.value }).prefix(stored.count - 100).map(\.key) {
                stored.removeValue(forKey: key)
            }
        }
        UserDefaults.standard.set(stored, forKey: Defaults.processedEventIDs)
    }

    private static func loadReceivedPushes() -> [ReceivedPush] {
        guard let data = UserDefaults.standard.data(forKey: Defaults.receivedPushes),
              let pushes = try? JSONDecoder().decode([ReceivedPush].self, from: data) else {
            return []
        }
        return Array(pushes.prefix(50))
    }
}

extension ReceivedPush.WriteStatus {
    var displayName: String {
        switch self {
        case .received:
            return "Received"
        case .wrote:
            return "Wrote LEDS.LED"
        case .noFolder:
            return "Folder needed"
        case .failed:
            return "Failed"
        case .unsupportedPattern:
            return "Unknown pattern"
        }
    }
}
