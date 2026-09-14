// Copyright (c) 2026 InteliWEAR LLC.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import Foundation

@available(iOS 16.0, *)
enum SidePulseLEDColor: String, CaseIterable {
    case red
    case green
    case blue
    case purple
    case aqua
    case ember

    var displayName: String {
        rawValue.capitalized
    }

    var hex: String {
        switch self {
        case .red: "#ff0000"
        case .green: "#00ff00"
        case .blue: "#0000ff"
        case .purple: "#FF00FF"
        case .aqua: "#00e5ff"
        case .ember: "#ff6a00"
        }
    }
}

@available(iOS 16.0, *)
enum SidePulsePulseColor: String, AppEnum, CaseIterable {
    case red
    case green
    case blue
    case purple
    case aqua
    case ember

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Pulse Color")

    static var caseDisplayRepresentations: [SidePulsePulseColor: DisplayRepresentation] = [
        .red: DisplayRepresentation(
            title: "Red",
            subtitle: "Pulse",
            image: DisplayRepresentation.Image(named: "ShortcutPulseDotRed", isTemplate: false)
        ),
        .green: DisplayRepresentation(
            title: "Green",
            subtitle: "Pulse",
            image: DisplayRepresentation.Image(named: "ShortcutPulseDotGreen", isTemplate: false)
        ),
        .blue: DisplayRepresentation(
            title: "Blue",
            subtitle: "Pulse",
            image: DisplayRepresentation.Image(named: "ShortcutPulseDotBlue", isTemplate: false)
        ),
        .purple: DisplayRepresentation(
            title: "Purple",
            subtitle: "Pulse",
            image: DisplayRepresentation.Image(named: "ShortcutPulseDotPurple", isTemplate: false)
        ),
        .aqua: DisplayRepresentation(
            title: "Aqua",
            subtitle: "Pulse",
            image: DisplayRepresentation.Image(named: "ShortcutPulseDotAqua", isTemplate: false)
        ),
        .ember: DisplayRepresentation(
            title: "Ember",
            subtitle: "Pulse",
            image: DisplayRepresentation.Image(named: "ShortcutPulseDotEmber", isTemplate: false)
        )
    ]

    var ledColor: SidePulseLEDColor {
        SidePulseLEDColor(rawValue: rawValue) ?? .red
    }
}

@available(iOS 16.0, *)
enum SidePulseBreatheColor: String, AppEnum, CaseIterable {
    case red
    case green
    case blue
    case purple
    case aqua
    case ember

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Breathe Color")

    static var caseDisplayRepresentations: [SidePulseBreatheColor: DisplayRepresentation] = [
        .red: DisplayRepresentation(
            title: "Red",
            subtitle: "Breathe",
            image: DisplayRepresentation.Image(named: "ShortcutBreatheDotRed", isTemplate: false)
        ),
        .green: DisplayRepresentation(
            title: "Green",
            subtitle: "Breathe",
            image: DisplayRepresentation.Image(named: "ShortcutBreatheDotGreen", isTemplate: false)
        ),
        .blue: DisplayRepresentation(
            title: "Blue",
            subtitle: "Breathe",
            image: DisplayRepresentation.Image(named: "ShortcutBreatheDotBlue", isTemplate: false)
        ),
        .purple: DisplayRepresentation(
            title: "Purple",
            subtitle: "Breathe",
            image: DisplayRepresentation.Image(named: "ShortcutBreatheDotPurple", isTemplate: false)
        ),
        .aqua: DisplayRepresentation(
            title: "Aqua",
            subtitle: "Breathe",
            image: DisplayRepresentation.Image(named: "ShortcutBreatheDotAqua", isTemplate: false)
        ),
        .ember: DisplayRepresentation(
            title: "Ember",
            subtitle: "Breathe",
            image: DisplayRepresentation.Image(named: "ShortcutBreatheDotEmber", isTemplate: false)
        )
    ]

    var ledColor: SidePulseLEDColor {
        SidePulseLEDColor(rawValue: rawValue) ?? .red
    }
}

enum SidePulseLEDProgram {
    static let defaultPulseCount = 2
    static let pulseRange = 1...10

    static func pulse(color: SidePulseLEDColor, count: Int) -> String {
        let pulseCount = bounded(count)
        let program = "off\n\(color.hex) 280ms pulse\noff 160ms none\n"
        return pulseCount == 1 ? program : program + "repeat \(pulseCount)\n"
    }

    static func breathe(color: SidePulseLEDColor) -> String {
        "off\n\(color.hex) 1.4s pulse\noff 400ms none\nrepeat\n"
    }

    static func bounded(_ count: Int) -> Int {
        min(max(count, pulseRange.lowerBound), pulseRange.upperBound)
    }
}

@available(iOS 17.0, *)
struct PulseColorOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [SidePulsePulseColor] {
        SidePulsePulseColor.allCases
    }
}

@available(iOS 17.0, *)
struct BreatheColorOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [SidePulseBreatheColor] {
        SidePulseBreatheColor.allCases
    }
}

@MainActor
private func recordShortcutWrite(title: String, body: String, ledText: String) {
    AppModel.shared.ledText = ledText
    AppModel.shared.recordReceivedPush(
        ReceivedPush(
            source: "Shortcut",
            title: title,
            body: body,
            ledText: ledText,
            payloadSummary: "Shortcut: \(title)",
            writeStatus: .wrote
        )
    )
}

@available(iOS 16.0, *)
struct PulseLEDsIntent: AppIntent {
    static var title: LocalizedStringResource = "Pulse SidePulse LEDs"
    static var description = IntentDescription("Pulses the SidePulse Dot in a chosen color.")
    static var openAppWhenRun = false

    @Parameter(title: "Color", default: .red)
    var color: SidePulsePulseColor

    @Parameter(title: "Number of Pulses", default: 2, inclusiveRange: (1, 10))
    var pulseCount: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Pulse \(\.$color) \(\.$pulseCount) times")
    }

    init() {
        color = .red
        pulseCount = SidePulseLEDProgram.defaultPulseCount
    }

    func perform() async throws -> some IntentResult {
        let count = SidePulseLEDProgram.bounded(pulseCount)
        let ledColor = color.ledColor
        let program = SidePulseLEDProgram.pulse(color: ledColor, count: count)
        _ = try DriveWriter.shared.write(program)
        await recordShortcutWrite(
            title: "Pulse \(ledColor.displayName)",
            body: "\(count) \(count == 1 ? "pulse" : "pulses")",
            ledText: program
        )
        return .result()
    }
}

@available(iOS 16.0, *)
struct BreatheLEDsIntent: AppIntent {
    static var title: LocalizedStringResource = "Breathe SidePulse LEDs"
    static var description = IntentDescription("Breathes the SidePulse Dot in a chosen color.")
    static var openAppWhenRun = false

    @Parameter(title: "Color", default: .aqua)
    var color: SidePulseBreatheColor

    static var parameterSummary: some ParameterSummary {
        Summary("Breathe \(\.$color) until changed")
    }

    init() {
        color = .aqua
    }

    func perform() async throws -> some IntentResult {
        let ledColor = color.ledColor
        let program = SidePulseLEDProgram.breathe(color: ledColor)
        _ = try DriveWriter.shared.write(program)
        await recordShortcutWrite(
            title: "Breathe \(ledColor.displayName)",
            body: "Repeats until changed",
            ledText: program
        )
        return .result()
    }
}

@available(iOS 16.0, *)
struct TurnOffLEDsIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn Off SidePulse LEDs"
    static var description = IntentDescription("Turns off the SidePulse Dot LEDs.")
    static var openAppWhenRun = false

    init() {}

    func perform() async throws -> some IntentResult {
        let program = "off\n"
        _ = try DriveWriter.shared.write(program)
        await recordShortcutWrite(
            title: "Off",
            body: "Turned off SidePulse Dot",
            ledText: program
        )
        return .result()
    }
}

@available(iOS 16.0, *)
struct WriteLEDsIntent: AppIntent {
    static var title: LocalizedStringResource = "Write SidePulse LEDS.LED"
    static var description = IntentDescription("Writes the supplied LED program to LEDS.LED on the selected USB drive.")
    static var openAppWhenRun = false

    @Parameter(title: "LEDS.LED Text")
    var ledsText: String

    static var parameterSummary: some ParameterSummary {
        Summary("Write \(\.$ledsText) to SidePulse Dot")
    }

    init() {}

    init(ledsText: String) {
        self.ledsText = ledsText
    }

    func perform() async throws -> some IntentResult {
        _ = try DriveWriter.shared.write(ledsText)
        await recordShortcutWrite(
            title: "Custom LEDS.LED",
            body: "Wrote \(ledsText.utf8.count) bytes",
            ledText: ledsText
        )
        return .result()
    }
}

@available(iOS 17.0, *)
struct SidePulseShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .grayBlue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TurnOffLEDsIntent(),
            phrases: [
                "Turn off \(.applicationName)",
                "Switch off \(.applicationName) LEDs"
            ],
            shortTitle: "Turn Off LEDs",
            systemImageName: "power"
        )

        AppShortcut(
            intent: PulseLEDsIntent(),
            phrases: [
                "Pulse \(\.$color) with \(.applicationName)"
            ],
            shortTitle: "Pulse LEDs",
            systemImageName: "waveform.path",
            parameterPresentation: ParameterPresentation(
                for: \.$color,
                summary: Summary("Pulse \(\.$color)")
            ) {
                OptionsCollection(
                    PulseColorOptionsProvider(),
                    title: "Pulse LEDs",
                    systemImageName: "circle.grid.2x1.fill"
                )
            }
        )

        AppShortcut(
            intent: BreatheLEDsIntent(),
            phrases: [
                "Breathe \(\.$color) with \(.applicationName)"
            ],
            shortTitle: "Breathe LEDs",
            systemImageName: "wind",
            parameterPresentation: ParameterPresentation(
                for: \.$color,
                summary: Summary("Breathe \(\.$color)")
            ) {
                OptionsCollection(
                    BreatheColorOptionsProvider(),
                    title: "Breathe LEDs",
                    systemImageName: "circle.grid.2x1.fill"
                )
            }
        )

        AppShortcut(
            intent: WriteLEDsIntent(),
            phrases: [
                "Write \(.applicationName) LEDs",
                "Send \(.applicationName) LEDs"
            ],
            shortTitle: "Write LEDs",
            systemImageName: "externaldrive"
        )
    }
}
