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
        case .red: "#ff1f3d"
        case .green: "#00ff66"
        case .blue: "#0066ff"
        case .purple: "#a855f7"
        case .aqua: "#00e5ff"
        case .ember: "#ff6a00"
        }
    }
}

@available(iOS 16.0, *)
enum SidePulsePulseColor: String, AppEnum {
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
            image: DisplayRepresentation.Image(named: "ShortcutPulseRed", isTemplate: false)
        ),
        .green: DisplayRepresentation(
            title: "Green",
            subtitle: "Pulse",
            image: DisplayRepresentation.Image(named: "ShortcutPulseGreen", isTemplate: false)
        ),
        .blue: DisplayRepresentation(
            title: "Blue",
            subtitle: "Pulse",
            image: DisplayRepresentation.Image(named: "ShortcutPulseBlue", isTemplate: false)
        ),
        .purple: DisplayRepresentation(
            title: "Purple",
            subtitle: "Pulse",
            image: DisplayRepresentation.Image(named: "ShortcutPulsePurple", isTemplate: false)
        ),
        .aqua: DisplayRepresentation(
            title: "Aqua",
            subtitle: "Pulse",
            image: DisplayRepresentation.Image(named: "ShortcutPulseAqua", isTemplate: false)
        ),
        .ember: DisplayRepresentation(
            title: "Ember",
            subtitle: "Pulse",
            image: DisplayRepresentation.Image(named: "ShortcutPulseEmber", isTemplate: false)
        )
    ]

    var ledColor: SidePulseLEDColor {
        SidePulseLEDColor(rawValue: rawValue) ?? .red
    }
}

@available(iOS 16.0, *)
enum SidePulseBreatheColor: String, AppEnum {
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
            image: DisplayRepresentation.Image(named: "ShortcutBreatheRed", isTemplate: false)
        ),
        .green: DisplayRepresentation(
            title: "Green",
            subtitle: "Breathe",
            image: DisplayRepresentation.Image(named: "ShortcutBreatheGreen", isTemplate: false)
        ),
        .blue: DisplayRepresentation(
            title: "Blue",
            subtitle: "Breathe",
            image: DisplayRepresentation.Image(named: "ShortcutBreatheBlue", isTemplate: false)
        ),
        .purple: DisplayRepresentation(
            title: "Purple",
            subtitle: "Breathe",
            image: DisplayRepresentation.Image(named: "ShortcutBreathePurple", isTemplate: false)
        ),
        .aqua: DisplayRepresentation(
            title: "Aqua",
            subtitle: "Breathe",
            image: DisplayRepresentation.Image(named: "ShortcutBreatheAqua", isTemplate: false)
        ),
        .ember: DisplayRepresentation(
            title: "Ember",
            subtitle: "Breathe",
            image: DisplayRepresentation.Image(named: "ShortcutBreatheEmber", isTemplate: false)
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

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let count = SidePulseLEDProgram.bounded(pulseCount)
        let ledColor = color.ledColor
        let program = SidePulseLEDProgram.pulse(color: ledColor, count: count)
        _ = try DriveWriter.shared.write(program)
        await recordShortcutWrite(
            title: "Pulse \(ledColor.displayName)",
            body: "\(count) \(count == 1 ? "pulse" : "pulses")",
            ledText: program
        )
        return .result(dialog: "Pulsed \(ledColor.displayName) \(count) times.")
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

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ledColor = color.ledColor
        let program = SidePulseLEDProgram.breathe(color: ledColor)
        _ = try DriveWriter.shared.write(program)
        await recordShortcutWrite(
            title: "Breathe \(ledColor.displayName)",
            body: "Repeats until changed",
            ledText: program
        )
        return .result(dialog: "Breathing \(ledColor.displayName) until changed.")
    }
}

@available(iOS 16.0, *)
struct TurnOffLEDsIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn Off SidePulse LEDs"
    static var description = IntentDescription("Turns off the SidePulse Dot LEDs.")
    static var openAppWhenRun = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let program = "off\n"
        _ = try DriveWriter.shared.write(program)
        await recordShortcutWrite(
            title: "Off",
            body: "Turned off SidePulse Dot",
            ledText: program
        )
        return .result(dialog: "SidePulse Dot is off.")
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

    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try DriveWriter.shared.write(ledsText)
        await recordShortcutWrite(
            title: "Custom LEDS.LED",
            body: "Wrote \(ledsText.utf8.count) bytes",
            ledText: ledsText
        )
        return .result(dialog: "Wrote LEDS.LED to SidePulse Dot.")
    }
}

@available(iOS 16.0, *)
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
                "Pulse \(\.$color) with \(.applicationName)",
                "Pulse the LEDs with \(.applicationName)"
            ],
            shortTitle: "Pulse LEDs",
            systemImageName: "waveform.path"
        )

        AppShortcut(
            intent: BreatheLEDsIntent(),
            phrases: [
                "Breathe \(\.$color) with \(.applicationName)",
                "Breathe the LEDs with \(.applicationName)"
            ],
            shortTitle: "Breathe LEDs",
            systemImageName: "wind"
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
