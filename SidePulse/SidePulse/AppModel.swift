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

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var pushToken: String {
        didSet { UserDefaults.standard.set(pushToken, forKey: Defaults.pushToken) }
    }

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

    @Published var pendingPairing: IOSPairingRequest?
    @Published var pairingInProgress = false
    @Published var pairingError: String?
    @Published var pairingSuccessMessage: String?
    @Published var pairingNotice: PairingNotice?
    @Published var lastRecoveryStatus = "Not checked"

    private var recoveryInProgress = false
    private var lastRecoveryAttempt: Date?
    private var pairingSubmissionInFlight = false
    private var pushTokenTimeoutTask: Task<Void, Never>?

    @Published var lastMessage: String = "Ready"
    @Published var eventLog: [String] = []
    @Published var receivedPushes: [ReceivedPush] {
        didSet { persistReceivedPushes() }
    }

    private enum Defaults {
        static let pushToken = "pushToken"
        static let ledText = "ledText"
        static let serverBaseURL = "serverBaseURL"
        static let sharedSecret = "sharedSecret"
        static let bridgeBaseURL = "bridgeBaseURL"
        static let isBridgeLinked = "isBridgeLinked"
        static let receivedPushes = "receivedPushes"
        static let processedEventIDs = "processedEventIDs"
    }

    private init() {
        self.pushToken = UserDefaults.standard.string(forKey: Defaults.pushToken) ?? ""
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
        self.isBridgeLinked = UserDefaults.standard.bool(forKey: Defaults.isBridgeLinked)
        self.pendingPairing = nil
        self.receivedPushes = Self.loadReceivedPushes()
        self.eventLog = EventLog.entries()
        refreshFolderStatus()
    }

    func setPushToken(from deviceToken: Data) {
        pushTokenTimeoutTask?.cancel()
        pushTokenTimeoutTask = nil
        pushToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        EventLog.append("APNs token updated")
        lastMessage = "Push token updated"
        refreshEventLog()
        if pendingPairing != nil, pairingInProgress {
            submitPendingPairingIfReady()
        }
        recoverQueuedPushes()
    }

    @discardableResult
    func receivePairingURL(_ url: URL) -> Bool {
        do {
            let pairing = try IOSPairingRequest.parse(url)
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
        pairingInProgress = true
        pairingError = nil
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
            granted, error in
            Task { @MainActor in
                if let error {
                    self.failPairing(error.localizedDescription)
                    return
                }
                guard granted else {
                    self.failPairing("Notification permission is required to link this iPhone.")
                    return
                }
                UIApplication.shared.registerForRemoteNotifications()
                if self.pushToken.isEmpty {
                    self.lastMessage = "Waiting for an APNs push token"
                    let channel = self.pendingPairing?.channel
                    self.pushTokenTimeoutTask?.cancel()
                    self.pushTokenTimeoutTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 10_000_000_000)
                        guard !Task.isCancelled, let self,
                              self.pendingPairing?.channel == channel,
                              self.pairingInProgress,
                              self.pushToken.isEmpty else {
                            return
                        }
                        self.failPairing(
                            "Could not get a push token. Check notification permissions and try again."
                        )
                    }
                } else {
                    self.submitPendingPairingIfReady()
                }
            }
        }
    }

    func cancelPairing() {
        pushTokenTimeoutTask?.cancel()
        pushTokenTimeoutTask = nil
        pendingPairing = nil
        pairingInProgress = false
        pairingSubmissionInFlight = false
        pairingError = nil
        pairingSuccessMessage = nil
    }

    func failPairing(_ message: String) {
        pushTokenTimeoutTask?.cancel()
        pushTokenTimeoutTask = nil
        pairingInProgress = false
        pairingSubmissionInFlight = false
        pairingError = message
        lastMessage = message
    }

    func failRemoteNotificationRegistration(_ error: Error) {
        if pendingPairing != nil, pairingInProgress {
            failPairing("Could not register for push notifications: \(error.localizedDescription)")
        } else {
            recordError(error)
        }
    }

    private func submitPendingPairingIfReady() {
        guard let pairing = pendingPairing, !pushToken.isEmpty,
              !pairingSubmissionInFlight else { return }
        pairingInProgress = true
        pairingSubmissionInFlight = true
        pairingError = nil
        let token = pushToken
        let deviceName = UIDevice.current.name
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
                        "push_token": token,
                    ],
                ]
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                bridgeBaseURL = pairing.server.absoluteString.trimmingCharacters(
                    in: CharacterSet(charactersIn: "/")
                )
                isBridgeLinked = true
                pushTokenTimeoutTask?.cancel()
                pushTokenTimeoutTask = nil
                pairingInProgress = false
                pairingSubmissionInFlight = false
                lastMessage = "Linked to \(pairing.sender)"
                EventLog.append("Linked to \(pairing.sender) through \(pairing.server.host ?? "bridge")")
                refreshEventLog()
                pairingSuccessMessage = "SidePulse writes from \(pairing.sender) will now arrive on this iPhone."
            } catch {
                failPairing("Could not complete pairing: \(error.localizedDescription)")
            }
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

    @discardableResult
    func processResolvedPush(_ resolution: PushPayloadResolution, source: String) -> Bool {
        if resolution.eventID != nil, !isBridgeLinked {
            isBridgeLinked = true
        }
        if let eventID = resolution.eventID, processedEventIDs()[eventID] != nil {
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
                eventID: resolution.eventID
            )
        )
        if let eventID = resolution.eventID {
            markEventProcessed(eventID)
        }
        return status != .failed
    }

    func recoverQueuedPushes() {
        guard !pushToken.isEmpty, !recoveryInProgress else { return }
        let now = Date()
        if let lastRecoveryAttempt, now.timeIntervalSince(lastRecoveryAttempt) < 3 {
            return
        }
        guard let server = URL(string: bridgeBaseURL) else {
            lastRecoveryStatus = "Invalid bridge URL"
            return
        }
        let endpoint = server
            .appendingPathComponent("api")
            .appendingPathComponent("leds")
            .appendingPathComponent("apns_\(pushToken)")
            .appendingPathComponent("queued")
        recoveryInProgress = true
        lastRecoveryAttempt = now
        Task {
            defer { recoveryInProgress = false }
            do {
                var request = URLRequest(url: endpoint)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      let entries = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                    throw URLError(.badServerResponse)
                }
                var handled = 0
                for entry in entries {
                    let payload: [AnyHashable: Any]
                    if let object = entry as? [String: Any] {
                        payload = Dictionary(uniqueKeysWithValues: object.map { (AnyHashable($0.key), $0.value) })
                    } else if let text = entry as? String {
                        payload = [AnyHashable("leds"): text]
                    } else {
                        continue
                    }
                    if processPush(payload, source: "Recovered push") {
                        handled += 1
                    }
                }
                lastRecoveryStatus = entries.isEmpty ? "Up to date" : "Recovered \(handled)"
            } catch {
                lastRecoveryStatus = "Recovery failed"
                EventLog.append("Push recovery failed: \(error.localizedDescription)")
                refreshEventLog()
            }
        }
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

        let tokenLine = pushToken.isEmpty ? "" : "\n  -d '{\"device_token\":\"\(pushToken)\",\"pattern\":\"green_pulse_2\"}'"
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
