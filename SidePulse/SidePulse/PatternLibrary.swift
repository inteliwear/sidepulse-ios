// Copyright (c) 2026 InteliWEAR LLC. MPL-2.0.
import Foundation

struct PatternRGB: Codable, Hashable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    init(_ hex: String) {
        let value = UInt32(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
        red = UInt8((value >> 16) & 255)
        green = UInt8((value >> 8) & 255)
        blue = UInt8(value & 255)
    }

    static let black = PatternRGB("000000")
    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }

    func mixed(with target: Self, amount: Double) -> Self {
        let t = min(1, max(0, amount))
        var result = self
        result.red = UInt8((Double(red) + (Double(target.red) - Double(red)) * t).rounded())
        result.green = UInt8((Double(green) + (Double(target.green) - Double(green)) * t).rounded())
        result.blue = UInt8((Double(blue) + (Double(target.blue) - Double(blue)) * t).rounded())
        return result
    }
}

enum PatternEffect: String, Codable, CaseIterable, Identifiable {
    case hold, fade, pulse
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var command: String {
        switch self { case .hold: "none"; case .fade: "cosine"; case .pulse: "pulse" }
    }
}

struct PatternStep: Codable, Identifiable, Hashable {
    var id = UUID()
    var left = PatternRGB("FF6A00")
    var right = PatternRGB("006AFF")
    var durationMS = 1400
    var effect: PatternEffect = .pulse
}

struct LibraryPattern: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = "New pattern"
    var steps = [PatternStep()]
    /// Zero loops forever; other values are the total number of plays.
    var repetitions = 0
    /// Original imported program, preserved verbatim for sharing and playback.
    var source: String?
    var canEditVisually: Bool { !steps.isEmpty }

    func preparingToSave(comparedTo original: Self?) -> Self {
        var result = self
        if let original, original.canEditVisually, steps != original.steps || repetitions != original.repetitions {
            result.source = nil
        }
        return result
    }

    /// Text editing keeps the saved identity and the exact source, even for commands
    /// outside the visual editor. Parsing only determines whether steps are available.
    func replacingSource(_ text: String) throws -> Self {
        var result = try PatternShareFile.decode(Data(text.utf8), name: "Draft", allowLegacy: false)
        result.id = id
        result.name = name
        return result
    }

    var duration: Double { 1.0 / 60 + Double(steps.reduce(0) { $0 + $1.durationMS }) / 1000 }
    var summary: String {
        if let featured = Self.featured.first(where: { $0.pattern.id == id && $0.pattern.ledText == ledText }) { return featured.detail }
        if !canEditVisually { return "Imported .led file" }
        let timing = String(format: "%.1fs", duration)
        let loop = repetitions == 0 ? "Loops" : repetitions == 1 ? "Once" : "\(repetitions) plays"
        return "\(steps.count) \(steps.count == 1 ? "step" : "steps") · \(timing) · \(loop)"
    }
    var ledText: String {
        if let source { return source }
        var lines = ["off"]
        lines += steps.map { "\($0.left.hex) \($0.right.hex) \($0.durationMS)ms \($0.effect.command)" }
        if repetitions == 0 { lines.append("repeat") }
        else if repetitions > 1 { lines.append("repeat \(repetitions)") }
        return lines.joined(separator: "\n") + "\n"
    }
    func validated() throws -> Self {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.name.isEmpty, result.name.count <= 60 else {
            throw PatternLibraryError.invalid("Give the pattern a name of 1–60 characters.")
        }
        if let source {
            guard source.utf8.count <= 65536 else {
                throw PatternLibraryError.invalid("This pattern file is too large. Keep imports within 64 KB.")
            }
            if steps.isEmpty { return result }
        }
        guard (1...12).contains(steps.count), Set(steps.map(\.id)).count == steps.count else {
            throw PatternLibraryError.invalid("A pattern needs 1–12 unique steps.")
        }
        guard (0...20).contains(repetitions), steps.allSatisfy({ (50...10000).contains($0.durationMS) }) else {
            throw PatternLibraryError.invalid("Each step must last 0.05–10 seconds, with up to 20 plays or a continuous loop.")
        }
        guard ledText.utf8.count <= 512 else {
            throw PatternLibraryError.invalid("This pattern is too long for the Dot. Remove a step to keep it within 512 bytes.")
        }
        return result
    }

    /// Mirrors hold/cosine/pulse semantics in the Dot DSL, including reset at each loop.
    func colors(at elapsed: Double) -> (PatternRGB, PatternRGB) {
        guard !steps.isEmpty, elapsed.isFinite else { return (.black, .black) }
        let completed = repetitions > 0 && elapsed >= duration * Double(repetitions)
        var time = completed ? duration : max(0, elapsed).truncatingRemainder(dividingBy: duration)
        time -= 1.0 / 60 // The initial "off" command takes one firmware frame.
        var left = PatternRGB.black
        var right = PatternRGB.black
        if time < 0 { return (left, right) }
        for step in steps {
            let seconds = Double(step.durationMS) / 1000
            if time < seconds && !completed {
                let progress = min(1, max(0, time / seconds))
                let amount: Double
                switch step.effect {
                case .hold: amount = 1
                case .fade: amount = (1 - cos(.pi * progress)) / 2
                case .pulse: amount = (1 - cos(2 * .pi * progress)) / 2
                }
                return (left.mixed(with: step.left, amount: amount), right.mixed(with: step.right, amount: amount))
            }
            if step.effect != .pulse { left = step.left; right = step.right }
            time -= seconds
        }
        return (left, right)
    }

    /// Preserve old IDs for existing Shortcuts; only untouched presets are grouped away.
    var isClassicStarter: Bool {
        Self.classicStarters.contains { $0.id == id && $0.name == name && $0.ledText == ledText }
    }

    static var starters: [Self] { featured.map(\.pattern) }

    // Agent programs adapted from inteliwear/sidepulse (MIT, Peter Kuhar).
    // See Design/PatternLibrary/Curation.md for exact sources and attribution.
    private static let featured: [(pattern: Self, detail: String)] = {
        let definitions: [(String, String, String)] = [
            ("Working", "Cyan pulses pass from LED to LED · Loops", "off 320ms cosine\n0:#00E5FF 760ms pulse 0ms; 1:#00E5FF 760ms pulse 260ms\nrepeat\n"),
            ("Needs You", "A warm amber call for attention · Loops", "off\n#FF3A00 1.6s pulse\nrepeat\n"),
            ("All Done", "Two green cheers, then lights out · Once", "off\n#00FF66 #00FF66 240ms pulse\n#000000 #000000 140ms none\n#00FF66 #00FF66 640ms pulse\n#000000 #000000 400ms none\n"),
            ("Aurora", "Violet and mint drift through blue · Loops", "#6500FF #00FFC2 1600ms cosine\n#007AFF #B000FF 2400ms cosine\n#00FFC2 #6500FF 2400ms cosine\n#6500FF #00FFC2 2400ms cosine\nrepeat\n"),
            ("Ember Tide", "Glowing embers roll across the Dot · Loops", "off 320ms cosine\n0:#F23819 760ms pulse 0ms; 1:#F23819 760ms pulse 260ms\nrepeat\n"),
            ("Purple Tide", "Staggered magenta waves · Loops", "off 320ms cosine\n0:#FF00FF 760ms pulse 0ms; 1:#FF00FF 760ms pulse 260ms\nrepeat\n"),
            ("Night Rider", "A quick red scanner with a trailing pulse · Loops", "off\n0:#FF1200 360ms pulse;1:#FF1200 360ms pulse 90ms\nrepeat\n"),
            ("Heartbeat", "A rose double beat with a quiet pause · Loops", "off\n#FF1744 #FF1744 180ms pulse\n#000000 #000000 120ms none\n#FF1744 #FF1744 320ms pulse\n#000000 #000000 1100ms none\nrepeat\n"),
            ("Sunset", "Tangerine melts into rose and violet · Loops", "#FF4600 #FF147A 1800ms cosine\n#FF147A #7000FF 3000ms cosine\n#FF4600 #FF147A 3000ms cosine\nrepeat\n"),
            ("Ocean", "Blue and turquoise trade places slowly · Loops", "#0066FF #00DDBB 1800ms cosine\n#00DDBB #0066FF 2800ms cosine\n#0066FF #00DDBB 2800ms cosine\nrepeat\n"),
            ("Candlelight", "An uneven, softly flickering amber glow · Loops", "#FF6208 #C42A00 700ms cosine\n#B52E00 #FF720C 180ms cosine\n#FF5000 #D43B00 480ms cosine\n#DB4200 #FF6508 260ms cosine\n#FF780F #B52E00 900ms cosine\nrepeat\n"),
            ("Spectrum", "A saturated rainbow flows between both lights · Loops", "#FF2400 #FFAE00 1000ms cosine\n#FFAE00 #20FF70 1200ms cosine\n#20FF70 #00BFFF 1200ms cosine\n#00BFFF #6500FF 1200ms cosine\n#6500FF #FF1685 1200ms cosine\n#FF1685 #FF2400 1200ms cosine\n#FF2400 #FFAE00 1200ms cosine\nrepeat\n")
        ]
        return definitions.enumerated().map { index, definition in
            // These bundled programs are validated by the firmware engine in tests.
            var pattern = try! PatternShareFile.decode(Data(definition.2.utf8), name: definition.0, allowLegacy: false)
            pattern.id = UUID(uuidString: String(format: "A0200000-0000-4000-8000-%012d", index + 1))!
            return (pattern, definition.1)
        }
    }()

    static var classicStarters: [Self] {
        var result: [Self] = []
        let colors = [("Red", "FF0000"), ("Green", "00FF00"), ("Blue", "0000FF"),
                      ("Purple", "FF00FF"), ("Aqua", "00E5FF"), ("Ember", "FF6A00")]
        for (index, color) in colors.enumerated() {
            for breathe in [false, true] {
                let number = index * 2 + (breathe ? 2 : 1)
                result.append(Self(
                    id: UUID(uuidString: String(format: "A0100000-0000-4000-8000-%012d", number))!,
                    name: "\(breathe ? "Breathe" : "Blink") \(color.0)",
                    steps: [PatternStep(left: PatternRGB(color.1), right: PatternRGB(color.1),
                                        durationMS: breathe ? 1400 : 280, effect: .pulse),
                            PatternStep(left: .black, right: .black, durationMS: breathe ? 400 : 160, effect: .hold)],
                    repetitions: breathe ? 0 : 2))
            }
        }
        result.insert(Self(id: UUID(uuidString: "A0100000-0000-4000-8000-000000000013")!,
                           name: "Orange & Blue", steps: [PatternStep()], repetitions: 0), at: 0)
        return result
    }
}

enum PatternLibraryError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}

struct PatternShareFile: Codable {
    let format: String
    let version: Int
    let pattern: LibraryPattern

    /// The shared file is the exact program sent to the device, without app metadata.
    static func encode(_ pattern: LibraryPattern) throws -> Data {
        Data(try pattern.validated().ledText.utf8)
    }

    static func decode(_ data: Data, name: String = "Imported pattern", allowLegacy: Bool = true) throws -> LibraryPattern {
        guard data.count <= 65536 else { throw PatternLibraryError.invalid("This pattern file is too large.") }
        guard let text = String(data: data, encoding: .utf8) else {
            throw PatternLibraryError.invalid("Choose a UTF-8 .led pattern file.")
        }
        // Keep previously shared documents readable, but never export this legacy format.
        if allowLegacy && text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            return try decodeLegacy(data)
        }
        var pattern = (try? decodeVisualProgram(data, name: name))
            ?? LibraryPattern(name: name, steps: [], repetitions: 1)
        pattern.source = text
        return try pattern.validated()
    }

    /// Best-effort editor support must never determine whether a file can be imported.
    private static func decodeVisualProgram(_ data: Data, name: String) throws -> LibraryPattern {
        let text = String(decoding: data, as: UTF8.self)
        guard data.count <= 512 else {
            throw PatternLibraryError.invalid("A .led pattern must fit the Dot’s 512-byte limit.")
        }
        let normalized = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var physicalLines = normalized.components(separatedBy: "\n")
        if physicalLines.last == "" { physicalLines.removeLast() }
        guard physicalLines.count <= 20 else {
            throw PatternLibraryError.invalid("A .led pattern may contain at most 20 lines.")
        }
        var lines = physicalLines.map { $0.trimmingCharacters(in: .whitespaces) }.filter {
            !$0.isEmpty && !$0.hasPrefix(";") && !$0.hasPrefix("//") && !$0.hasPrefix("# ")
        }
        let unsupported = PatternLibraryError.invalid("This .led file uses commands the visual editor doesn’t support yet. Import a .led file shared from the SidePulse Pattern Library.")
        // The editor resets both LEDs at the start of every play. Do not silently
        // alter programs that depend on the device’s previous state.
        guard lines.first?.lowercased() == "off" else { throw unsupported }
        lines.removeFirst()
        var repetitions = 1
        if let last = lines.last {
            let tokens = last.lowercased().split(whereSeparator: \.isWhitespace)
            if tokens.first == "repeat" {
                guard tokens.count == 1 || (tokens.count == 2 && Int(tokens[1]).map { (1...20).contains($0) } == true) else {
                    throw PatternLibraryError.invalid("Use repeat for a continuous loop, or repeat 1–20.")
                }
                repetitions = tokens.count == 1 ? 0 : Int(tokens[1])!
                lines.removeLast()
            }
        }
        let steps = try lines.map { line -> PatternStep in
            let tokens = line.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count == 4,
                  tokens[0].range(of: "^#[0-9a-f]{6}$", options: .regularExpression) != nil,
                  tokens[1].range(of: "^#[0-9a-f]{6}$", options: .regularExpression) != nil,
                  tokens[2].hasSuffix("ms"), let duration = Int(tokens[2].dropLast(2)),
                  let effect = PatternEffect.allCases.first(where: { $0.command == tokens[3] }) else {
                throw unsupported
            }
            return PatternStep(left: PatternRGB(tokens[0]), right: PatternRGB(tokens[1]), durationMS: duration, effect: effect)
        }
        // Fresh pattern and step IDs prevent an import from replacing existing work.
        return try LibraryPattern(name: name, steps: steps, repetitions: repetitions).validated()
    }

    private static func decodeLegacy(_ data: Data) throws -> LibraryPattern {
        let file: Self
        do { file = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw PatternLibraryError.invalid("This isn’t a valid SidePulse pattern file.") }
        guard file.format == "io.sidepulse.pattern", file.version == 1 else {
            throw PatternLibraryError.invalid("This pattern format isn’t supported. Update SidePulse and try again.")
        }
        var pattern = try file.pattern.validated()
        pattern.id = UUID()
        return pattern
    }

    static func read(_ url: URL) throws -> LibraryPattern {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 65536 else {
            throw PatternLibraryError.invalid("Choose a SidePulse pattern file smaller than 64 KB.")
        }
        let name = String(url.deletingPathExtension().lastPathComponent.prefix(60))
        return try decode(Data(contentsOf: url), name: name, allowLegacy: url.pathExtension.lowercased() != "led")
    }

}

struct PatternLibraryRepository {
    let url: URL
    static var standard: Self {
        Self(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PatternLibrary.json"))
    }
    func load() throws -> [LibraryPattern] {
        guard FileManager.default.fileExists(atPath: url.path) else { return LibraryPattern.starters }
        let data = try Data(contentsOf: url)
        let patterns: [LibraryPattern]
        if let legacy = try? JSONDecoder().decode([LibraryPattern].self, from: data) {
            // Empty means intentionally cleared. Otherwise add the new collection once;
            // preserve every saved identity, edit, and old Shortcut target.
            let existingIDs = Set(legacy.map(\.id))
            patterns = legacy.isEmpty ? [] : LibraryPattern.starters.filter { !existingIDs.contains($0.id) } + legacy
        } else {
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.version == 1 else { throw PatternLibraryError.invalid("Update SidePulse to open this library.") }
            patterns = document.patterns
        }
        guard Set(patterns.map(\.id)).count == patterns.count else {
            throw PatternLibraryError.invalid("The library contains duplicate identifiers.")
        }
        return try patterns.map { try $0.validated() }
    }
    private struct Document: Codable {
        var version = 1
        let patterns: [LibraryPattern]
    }
    func save(_ patterns: [LibraryPattern]) throws {
        let validated = try patterns.map { try $0.validated() }
        guard Set(validated.map(\.id)).count == validated.count else {
            throw PatternLibraryError.invalid("The library contains duplicate identifiers.")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Document(patterns: validated)).write(to: url, options: .atomic)
    }
}

/// Versioned, self-contained links. The fragment is not sent to the web server.
enum PatternShareLink {
    static let maximumPayloadLength = 8192
    private struct Payload: Codable {
        let v: Int
        let name: String
        let led: String
    }

    static func recognizes(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "sidepulse" { return url.host == "pattern" }
        return url.scheme == "https" && url.host == "sidepulse.io" && ["/pattern", "/pattern/"].contains(url.path)
    }

    static func encode(_ pattern: LibraryPattern) throws -> URL {
        let pattern = try pattern.validated()
        let data = try JSONEncoder().encode(Payload(v: 1, name: pattern.name, led: pattern.ledText))
        let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        guard payload.count <= maximumPayloadLength else {
            throw PatternLibraryError.invalid("This pattern is too large for a link. Share the .led file instead.")
        }
        return URL(string: "https://sidepulse.io/pattern#\(payload)")!
    }

    static func decode(_ url: URL) throws -> LibraryPattern {
        guard recognizes(url), url.user == nil, url.password == nil, url.port == nil, url.query == nil,
              let fragment = url.fragment, !fragment.isEmpty, fragment.count <= maximumPayloadLength,
              fragment.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw PatternLibraryError.invalid("This pattern link is incomplete or invalid.")
        }
        var base64 = fragment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), let payload = try? JSONDecoder().decode(Payload.self, from: data), payload.v == 1 else {
            throw PatternLibraryError.invalid("This pattern link isn’t supported. Try sharing the .led file instead.")
        }
        return try PatternShareFile.decode(Data(payload.led.utf8), name: payload.name, allowLegacy: false)
    }
}
