import Foundation
import XCTest
@testable import SidePulseTokenFormatting

final class PatternLibraryTests: XCTestCase {
    func testTextEditingPreservesIdentityAndExactSourceAcrossStorageAndSharing() throws {
        let original = LibraryPattern.starters[0]
        let source = "// Été 💡\r\noff\r\nbrightness 40\r\n#FF00FF 500ms pulse\r\n"
        let edited = try original.replacingSource(source)
        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(edited.name, original.name)
        XCTAssertFalse(edited.canEditVisually)
        XCTAssertEqual(edited.ledText, source)
        XCTAssertEqual(try PatternShareFile.encode(edited), Data(source.utf8))
        XCTAssertEqual(try PatternShareLink.decode(PatternShareLink.encode(edited)).ledText, source)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("library.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = PatternLibraryRepository(url: url)
        try repository.save([edited])
        XCTAssertEqual(try repository.load().first, edited)
    }

    func testTextEditingCanReturnToVisualStepsWithoutChangingSource() throws {
        let original = try LibraryPattern().replacingSource("off\nbrightness 40\n#FF00FF 500ms pulse\n")
        let source = "// Keep my comment\noff\n#FF0000 #0000FF 900ms cosine\nrepeat 2\n"
        let edited = try original.replacingSource(source)
        XCTAssertEqual(edited.id, original.id)
        XCTAssertTrue(edited.canEditVisually)
        XCTAssertEqual(edited.steps.first?.durationMS, 900)
        XCTAssertEqual(edited.repetitions, 2)
        XCTAssertEqual(edited.ledText, source)
        var visualEdit = edited
        visualEdit.steps[0].durationMS = 500
        XCTAssertNil(visualEdit.preparingToSave(comparedTo: edited).source)
    }

    func testFreeTextIsNotMistakenForLegacyJSONAndKeepsLimits() throws {
        let original = LibraryPattern()
        XCTAssertEqual(try original.replacingSource("{unfinished command").ledText, "{unfinished command")
        XCTAssertNoThrow(try original.replacingSource(String(repeating: "a", count: 65536)))
        XCTAssertThrowsError(try original.replacingSource(String(repeating: "a", count: 65537)))
        var edited = try original.replacingSource("off")
        edited.name = "   "
        XCTAssertThrowsError(try edited.validated())
    }

    func testStarterProgramsFitDeviceLimitsAndIDsRemainStable() throws {
        let first = LibraryPattern.starters
        XCTAssertEqual(first.map(\.id), LibraryPattern.starters.map(\.id))
        XCTAssertEqual(Set(first.map(\.id)).count, first.count)
        for pattern in first {
            _ = try pattern.validated()
            XCTAssertLessThanOrEqual(pattern.ledText.utf8.count, 512)
            XCTAssertLessThanOrEqual(pattern.ledText.split(separator: "\n").count, 20)
        }
    }

    func testShareRoundTripPreservesContentButNeverOverwritesIdentity() throws {
        let original = LibraryPattern.classicStarters[0]
        let data = try PatternShareFile.encode(original)
        let imported = try PatternShareFile.decode(data, name: original.name)
        XCTAssertNotEqual(original.id, imported.id)
        XCTAssertEqual(original.name, imported.name)
        XCTAssertEqual(original.steps.map(\.left), imported.steps.map(\.left))
        XCTAssertEqual(original.steps.map(\.right), imported.steps.map(\.right))
        XCTAssertNotEqual(original.steps.map(\.id), imported.steps.map(\.id))
        XCTAssertEqual(String(data: data, encoding: .utf8), original.ledText)
        XCTAssertEqual(original.ledText, imported.ledText)
        XCTAssertNotEqual(imported.id, try PatternShareFile.decode(data).id)
    }

    func testImportsRejectOversizedUnknownAndInvalidDocuments() throws {
        XCTAssertThrowsError(try PatternShareFile.decode(Data(repeating: 0, count: 65537)))
        XCTAssertEqual(try PatternShareFile.decode(Data("hello".utf8)).ledText, "hello")
        XCTAssertThrowsError(try PatternShareFile.decode(Data([0xFF, 0xFE])))
        let unknown = PatternShareFile(format: "io.sidepulse.pattern", version: 99, pattern: LibraryPattern())
        XCTAssertThrowsError(try PatternShareFile.decode(JSONEncoder().encode(unknown)))
        var invalid = LibraryPattern()
        invalid.steps[0].durationMS = -100
        let file = PatternShareFile(format: "io.sidepulse.pattern", version: 1, pattern: invalid)
        XCTAssertThrowsError(try PatternShareFile.decode(JSONEncoder().encode(file)))
    }

    func testLEDImportPreservesAllEffectsAndRepeatModes() throws {
        for repetitions in [0, 1, 2, 20] {
            let pattern = LibraryPattern(steps: PatternEffect.allCases.map {
                PatternStep(left: PatternRGB("12ABEF"), right: PatternRGB("FE4321"), durationMS: 1250, effect: $0)
            }, repetitions: repetitions)
            let decoded = try PatternShareFile.decode(PatternShareFile.encode(pattern))
            XCTAssertEqual(decoded.ledText, pattern.ledText)
            XCTAssertEqual(decoded.steps.map(\.effect), pattern.steps.map(\.effect))
        }
    }

    func testLEDReadUsesFilenameAndAcceptsCommentsAndWindowsNewlines() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Orange & Blue.led")
        let program = "// Shared pattern\r\n; Comment\r\n# Comment\r\n\r\noff\r\n#ff6a00 #006aff 1400ms pulse\r\nrepeat\r\n"
        try Data(program.utf8).write(to: url)
        let imported = try PatternShareFile.read(url)
        XCTAssertEqual(imported.name, "Orange & Blue")
        XCTAssertEqual(imported.ledText, program)
        XCTAssertTrue(imported.canEditVisually)
    }

    func testUnsupportedLEDCommandsAreNeverSilentlyChanged() throws {
        for program in [
            "off\n#GG0000 #000000 100ms none\n",
            "off\n#FF0000 #000000 -100ms pulse\n",
            "off\n#FF0000 #000000 100ms linear\n",
            "off\n#FF0000 #000000 100ms none\nrepeat 0\n",
            "off\n#FF0000 #000000 100ms none\nrepeat 2\noff\n",
            "off\nbrightness 128\n#FF0000 #000000 100ms none\n",
            "#FF0000 #000000 100ms pulse\n",
            String(repeating: "// comment\n", count: 21) + LibraryPattern().ledText,
            String(repeating: " ", count: 513)
        ] {
            let imported = try PatternShareFile.decode(Data(program.utf8))
            XCTAssertFalse(imported.canEditVisually, program)
            XCTAssertEqual(try PatternShareFile.encode(imported), Data(program.utf8))
        }
    }

    func testDotStartupFileSurvivesImportPersistenceRenameAndSharing() throws {
        // Exact contents of /Volumes/PulseDot/INIT.LED reported by the user.
        let data = Data("off\nbrightness 40\n#FF00FF 500ms pulse\n".utf8)
        let imported = try PatternShareFile.decode(data, name: "INIT")
        XCTAssertFalse(imported.canEditVisually)
        XCTAssertTrue(imported.steps.isEmpty)
        XCTAssertEqual(imported.summary, "Imported .led file")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = PatternLibraryRepository(url: folder.appendingPathComponent("library.json"))
        try repository.save([imported])
        var restored = try XCTUnwrap(repository.load().first)
        restored.name = "Startup pulse"
        restored = restored.preparingToSave(comparedTo: imported)
        XCTAssertEqual(try PatternShareFile.encode(restored), data)
        XCTAssertEqual(restored.ledText, String(decoding: data, as: UTF8.self))
        var duplicate = restored
        duplicate.id = UUID()
        try repository.save([restored, duplicate])
        XCTAssertEqual(try repository.load().map(\.ledText), [restored.ledText, restored.ledText])
    }

    func testVisualChangesReplaceSourceButRenameKeepsIt() throws {
        let text = "// keep this comment\noff\n#FF0000 #0000FF 500ms pulse\nrepeat\n"
        let imported = try PatternShareFile.decode(Data(text.utf8))
        var edited = imported
        edited.name = "Renamed"
        XCTAssertEqual(edited.preparingToSave(comparedTo: imported).ledText, text)
        edited.steps[0].durationMS = 900
        let saved = try edited.preparingToSave(comparedTo: imported).validated()
        XCTAssertNil(saved.source)
        XCTAssertTrue(saved.ledText.contains("900ms pulse"))
        edited.steps[0].durationMS = -1
        XCTAssertThrowsError(try edited.preparingToSave(comparedTo: imported).validated())
    }

    func testOldLibrariesWithoutSourceStillLoad() throws {
        let original = LibraryPattern.classicStarters[0]
        let data = try JSONEncoder().encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "source")
        let decoded = try JSONDecoder().decode(LibraryPattern.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.source)
        XCTAssertEqual(decoded, original)
    }

    func testPreviewLinksPreserveNamesAndArbitrarySource() throws {
        let original = try PatternShareFile.decode(Data("off\nbrightness 40\n#FF00FF 500ms pulse\n".utf8), name: "Été 💡 & <sunset>")
        let url = try PatternShareLink.encode(original)
        XCTAssertEqual(url.host, "sidepulse.io")
        XCTAssertEqual(url.path, "/pattern")
        XCTAssertNil(url.query)
        let imported = try PatternShareLink.decode(url)
        XCTAssertEqual(imported.name, original.name)
        XCTAssertEqual(imported.ledText, original.ledText)
        XCTAssertNotEqual(imported.id, original.id)
        let deepLink = try XCTUnwrap(URL(string: "sidepulse://pattern#" + (url.fragment ?? "")))
        XCTAssertEqual(try PatternShareLink.decode(deepLink).ledText, original.ledText)
    }

    func testPreviewLinksRejectInvalidRoutesPayloadsAndUnsupportedVersions() throws {
        let valid = try PatternShareLink.encode(LibraryPattern())
        for text in [
            valid.absoluteString.replacingOccurrences(of: "https://sidepulse.io", with: "https://other.example"),
            valid.absoluteString.replacingOccurrences(of: "/pattern#", with: "/pair#"),
            valid.absoluteString.replacingOccurrences(of: "https://", with: "http://"),
            "https://sidepulse.io/pattern#bad!", "sidepulse://pattern", "https://sidepulse.io/pattern#" + String(repeating: "A", count: 8193)
        ] {
            XCTAssertThrowsError(try PatternShareLink.decode(XCTUnwrap(URL(string: text))))
        }
        let unknown = Data("{\"v\":2,\"name\":\"Future\",\"led\":\"off\"}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        XCTAssertThrowsError(try PatternShareLink.decode(XCTUnwrap(URL(string: "https://sidepulse.io/pattern#" + unknown))))
        let large = try PatternShareFile.decode(Data(String(repeating: "; long comment\n", count: 1000).utf8))
        XCTAssertThrowsError(try PatternShareLink.encode(large))
        XCTAssertNoThrow(try PatternShareFile.encode(large))
    }

    func testLegacySharedDocumentsStillImport() throws {
        let original = LibraryPattern()
        let file = PatternShareFile(format: "io.sidepulse.pattern", version: 1, pattern: original)
        let imported = try PatternShareFile.decode(JSONEncoder().encode(file))
        XCTAssertEqual(imported.ledText, original.ledText)
        XCTAssertEqual(imported.name, original.name)
        XCTAssertNotEqual(imported.id, original.id)
    }

    func testAtomicPersistenceHandlesEditsDeletesAndEmptyLibrary() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = PatternLibraryRepository(url: folder.appendingPathComponent("library.json"))
        XCTAssertFalse(try repository.load().isEmpty)
        var pattern = LibraryPattern()
        try repository.save([pattern])
        pattern.name = "Edited"
        try repository.save([pattern])
        XCTAssertEqual(try repository.load(), [pattern])
        try repository.save([])
        XCTAssertEqual(try repository.load(), []) // Never reseed an intentionally empty library.
        try Data("corrupt".utf8).write(to: repository.url)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: repository.url), Data("corrupt".utf8))
    }

    func testPreviewPulseReturnsToStartingColorAndFinitePlaybackStops() throws {
        let red = PatternRGB("FF0000")
        let pattern = LibraryPattern(steps: [PatternStep(left: red, right: red, durationMS: 1000, effect: .pulse)], repetitions: 1)
        XCTAssertEqual(pattern.colors(at: 0).0, .black)
        XCTAssertEqual(pattern.colors(at: 0.5 + 1.0 / 60).0, red)
        XCTAssertEqual(pattern.colors(at: 2).0, .black)
        let hold = LibraryPattern(steps: [PatternStep(left: red, right: red, durationMS: 1000, effect: .hold)], repetitions: 1)
        XCTAssertEqual(hold.colors(at: 5).0, red)
    }

    func testPreviewUsesPreviousStepForFadeAndRestartsLoopFromOff() {
        let red = PatternRGB("FF0000"), blue = PatternRGB("0000FF")
        let pattern = LibraryPattern(steps: [
            PatternStep(left: red, right: red, durationMS: 1000, effect: .hold),
            PatternStep(left: blue, right: blue, durationMS: 1000, effect: .fade)
        ], repetitions: 0)
        let midpoint = pattern.colors(at: 1.5 + 1.0 / 60).0
        XCTAssertEqual(midpoint.red, 128)
        XCTAssertEqual(midpoint.blue, 127, accuracy: 1)
        XCTAssertEqual(pattern.colors(at: pattern.duration + 0.001).0, .black)
    }

    func testInvalidEditsCannotBeSavedOrExported() {
        var pattern = LibraryPattern()
        pattern.name = "   "
        XCTAssertThrowsError(try pattern.validated())
        pattern.name = "Valid"
        pattern.steps = []
        XCTAssertThrowsError(try PatternShareFile.encode(pattern))
        pattern.steps = [PatternStep()]
        pattern.repetitions = -1
        XCTAssertThrowsError(try pattern.validated())
        pattern.repetitions = 0
        pattern.steps += pattern.steps
        XCTAssertThrowsError(try pattern.validated())
    }
}
