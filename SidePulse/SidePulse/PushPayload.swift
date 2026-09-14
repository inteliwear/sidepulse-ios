// Copyright (c) 2026 InteliWEAR LLC.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct LEDPattern: Identifiable, Codable, Hashable {
    let name: String
    let displayName: String
    let detail: String
    let ledText: String
    let tintHex: String

    var id: String { name }

    var byteCount: Int {
        ledText.data(using: .utf8)?.count ?? 0
    }
}

enum LEDPatternCatalog {
    static let patterns: [LEDPattern] = [
        LEDPattern(
            name: "off",
            displayName: "Off",
            detail: "Clear the LEDs",
            ledText: "off\n",
            tintHex: "#6b7280"
        ),
        LEDPattern(
            name: "green_pulse_2",
            displayName: "Two Green Pulses",
            detail: "Two quick confirmation pulses",
            ledText: "off\n#00ff00 280ms pulse\noff 160ms none\nrepeat 2\n",
            tintHex: "#20c997"
        ),
        LEDPattern(
            name: "success",
            displayName: "Success",
            detail: "Soft green success glow",
            ledText: "#00ff00 450ms cosine\noff 160ms none\n",
            tintHex: "#22c55e"
        ),
        LEDPattern(
            name: "error",
            displayName: "Error",
            detail: "Red attention blink",
            ledText: "#ff0000 120ms none\noff 120ms none\nrepeat 3\n",
            tintHex: "#ef4444"
        ),
        LEDPattern(
            name: "working",
            displayName: "Working",
            detail: "Blue activity pulse",
            ledText: "off\n#0000ff 900ms pulse\n#00ccff 900ms pulse\nrepeat\n",
            tintHex: "#0ea5e9"
        ),
        LEDPattern(
            name: "waiting",
            displayName: "Waiting",
            detail: "Amber waiting breath",
            ledText: "off\n#ffaa00 1.2s pulse\noff 500ms none\nrepeat\n",
            tintHex: "#f59e0b"
        ),
        LEDPattern(
            name: "white_breathe",
            displayName: "White Breathe",
            detail: "Soft neutral breathing",
            ledText: "off\n#404040 1.4s pulse\noff 400ms none\nrepeat\n",
            tintHex: "#f8fafc"
        )
    ]

    static func pattern(named name: String?) -> LEDPattern? {
        guard let name else {
            return nil
        }

        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return patterns.first { $0.name.lowercased() == normalized }
    }
}

struct ReceivedPush: Identifiable, Codable, Hashable {
    enum WriteStatus: String, Codable, Hashable {
        case received
        case wrote
        case noFolder
        case failed
        case unsupportedPattern
    }

    var id: UUID = UUID()
    var receivedAt: Date = Date()
    var source: String
    var title: String
    var body: String
    var notificationTitle: String? = nil
    var notificationBody: String? = nil
    var imageURL: URL? = nil
    var patternName: String?
    var ledText: String?
    var payloadSummary: String
    var writeStatus: WriteStatus
    var errorMessage: String?
    var eventID: String? = nil

    var ledByteCount: Int {
        ledText?.data(using: .utf8)?.count ?? 0
    }

    var notificationTitleText: String? {
        notificationTitle?.trimmedNonEmpty
    }

    var notificationBodyText: String? {
        notificationBody?.trimmedNonEmpty
    }

    var hasNotificationText: Bool {
        notificationTitleText != nil || notificationBodyText != nil
    }
}

struct PushPayloadResolution {
    let sourceTitle: String
    let sourceBody: String
    let imageURL: URL?
    let patternName: String?
    let pattern: LEDPattern?
    let ledText: String?
    let payloadSummary: String
    let eventID: String?

    var resolvedLEDText: String? {
        ledText ?? pattern?.ledText
    }

    var isUnsupportedPattern: Bool {
        patternName != nil && pattern == nil && ledText == nil
    }

    var displayTitle: String {
        if !sourceTitle.isEmpty {
            return sourceTitle
        }
        if let pattern {
            return pattern.displayName
        }
        if isUnsupportedPattern {
            return "Unknown Pattern"
        }
        if ledText != nil {
            return "LEDS.LED Push"
        }
        return "Push Received"
    }

    var displayBody: String {
        if !sourceBody.isEmpty {
            return sourceBody
        }
        if let pattern {
            return pattern.detail
        }
        if let patternName {
            return patternName
        }
        if let ledText {
            let byteCount = ledText.data(using: .utf8)?.count ?? 0
            return "\(byteCount) bytes"
        }
        return payloadSummary
    }
}

enum PushPayloadResolver {
    private static let ledKeys = ["leds", "LEDS.LED", "LEDS.led", "text"]

    static func resolve(userInfo: [AnyHashable: Any]) -> PushPayloadResolution {
        let payload = normalizedDictionary(userInfo)
        let candidates = candidateDictionaries(from: payload)
        let ledText = firstString(in: candidates, keys: ledKeys)
        let requestedPattern = firstString(in: candidates, keys: ["pattern"])
        let pattern = ledText == nil ? LEDPatternCatalog.pattern(named: requestedPattern) : nil
        let alert = alertText(from: payload)
        let imageURL = firstRemoteURL(
            in: candidates,
            keys: ["image_url", "image-url", "imageURL", "media_url", "media-url"]
        )
        let eventID = firstString(in: candidates, keys: ["sidepulse_event_id"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return PushPayloadResolution(
            sourceTitle: alert.title,
            sourceBody: alert.body,
            imageURL: imageURL,
            patternName: requestedPattern,
            pattern: pattern,
            ledText: ledText,
            payloadSummary: summary(from: payload),
            eventID: eventID?.isEmpty == false ? eventID : nil
        )
    }

    static func resolve(url: URL) -> PushPayloadResolution? {
        guard url.scheme == "sidepulse" else {
            return nil
        }

        let command = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard command == "write" else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var payload: [String: Any] = [:]
        components?.queryItems?.forEach { item in
            payload[item.name] = item.value ?? ""
        }

        guard !payload.isEmpty else {
            return nil
        }

        var userInfo: [AnyHashable: Any] = [:]
        payload.forEach { key, value in
            userInfo[AnyHashable(key)] = value
        }
        return resolve(userInfo: userInfo)
    }

    private static func candidateDictionaries(from payload: [String: Any]) -> [[String: Any]] {
        var dictionaries = [payload]
        for key in ["payload", "data"] {
            if let nested = payload[key] as? [String: Any] {
                dictionaries.append(nested)
            }
        }
        return dictionaries
    }

    private static func firstString(in dictionaries: [[String: Any]], keys: [String]) -> String? {
        for dictionary in dictionaries {
            for key in keys {
                if let value = dictionary[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? value : value
                }
            }
        }
        return nil
    }

    private static func firstRemoteURL(in dictionaries: [[String: Any]], keys: [String]) -> URL? {
        guard let rawValue = firstString(in: dictionaries, keys: keys)?.trimmedNonEmpty,
              let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }

        return url
    }

    private static func alertText(from payload: [String: Any]) -> (title: String, body: String) {
        let directTitle = payload["title"] as? String ?? ""
        let directBody = payload["body"] as? String ?? ""

        guard let aps = payload["aps"] as? [String: Any] else {
            return (directTitle, directBody)
        }

        if let alert = aps["alert"] as? String {
            return (directTitle, directBody.isEmpty ? alert : directBody)
        }

        if let alert = aps["alert"] as? [String: Any] {
            return (
                directTitle.isEmpty ? (alert["title"] as? String ?? "") : directTitle,
                directBody.isEmpty ? (alert["body"] as? String ?? "") : directBody
            )
        }

        return (directTitle, directBody)
    }

    private static func summary(from payload: [String: Any]) -> String {
        let visiblePayload = payload.filter { key, _ in
            key != "aps"
        }

        guard !visiblePayload.isEmpty else {
            return "APNs notification"
        }

        if JSONSerialization.isValidJSONObject(visiblePayload),
           let data = try? JSONSerialization.data(withJSONObject: visiblePayload, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return truncated(json)
        }

        return truncated(visiblePayload.keys.sorted().joined(separator: ", "))
    }

    private static func truncated(_ value: String) -> String {
        guard value.count > 280 else {
            return value
        }

        let endIndex = value.index(value.startIndex, offsetBy: 280)
        return String(value[..<endIndex]) + "..."
    }

    private static func normalizedDictionary(_ input: [AnyHashable: Any]) -> [String: Any] {
        var output: [String: Any] = [:]
        for (key, value) in input {
            output[String(describing: key)] = normalizedValue(value)
        }
        return output
    }

    private static func normalizedValue(_ value: Any) -> Any {
        if let dictionary = value as? [AnyHashable: Any] {
            return normalizedDictionary(dictionary)
        }

        if let dictionary = value as? NSDictionary {
            var output: [String: Any] = [:]
            dictionary.forEach { key, value in
                output[String(describing: key)] = normalizedValue(value)
            }
            return output
        }

        if let array = value as? [Any] {
            return array.map { normalizedValue($0) }
        }

        return value
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
