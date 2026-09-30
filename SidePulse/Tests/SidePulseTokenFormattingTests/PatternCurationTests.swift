import Foundation
import XCTest
@testable import SidePulseTokenFormatting

final class PatternCurationTests: XCTestCase {
    func testLegacyLibraryGainsCollectionWithoutChangingExistingPatterns() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = PatternLibraryRepository(url: directory.appendingPathComponent("patterns.json"))
        var edited = LibraryPattern.classicStarters[1]
        edited.name = "My custom signal"
        edited.steps[0].left = PatternRGB("123456")
        let existing = [edited] + LibraryPattern.classicStarters.filter { $0.id != edited.id }
        let original = try JSONEncoder().encode(existing)
        try original.write(to: repository.url)
        let upgraded = try repository.load()
        XCTAssertEqual(Array(upgraded.suffix(existing.count)), existing)
        XCTAssertEqual(Array(upgraded.prefix(12)).map(\.name), LibraryPattern.starters.map(\.name))
        XCTAssertEqual(try Data(contentsOf: repository.url), original) // Reads do not overwrite the old file.
        XCTAssertFalse(edited.isClassicStarter)
        XCTAssertTrue(LibraryPattern.classicStarters.allSatisfy(\.isClassicStarter))
    }

    func testCuratedDeletionsStayDeletedAndEmptyLibraryStaysEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = PatternLibraryRepository(url: directory.appendingPathComponent("patterns.json"))
        var patterns = try repository.load()
        let removed = patterns.removeFirst()
        try repository.save(patterns)
        XCTAssertFalse(try repository.load().contains { $0.id == removed.id })
        try repository.save([])
        XCTAssertTrue(try repository.load().isEmpty)
        try Data("[]".utf8).write(to: repository.url)
        XCTAssertTrue(try repository.load().isEmpty)
    }

    func testCuratedSourceAndDescriptionsSurviveSharingAndEditing() throws {
        XCTAssertEqual(LibraryPattern.starters.count, 12)
        XCTAssertEqual(Set(LibraryPattern.starters.map(\.id)).count, 12)
        for pattern in LibraryPattern.starters {
            XCTAssertLessThanOrEqual(pattern.ledText.utf8.count, 512)
            XCTAssertLessThanOrEqual(pattern.ledText.split(separator: "\n").count, 20)
            XCTAssertFalse(pattern.summary.contains("Imported"))
            XCTAssertEqual(try PatternShareLink.decode(PatternShareLink.encode(pattern)).ledText, pattern.ledText)
            XCTAssertNotEqual(try pattern.replacingSource("off").summary, pattern.summary)
        }
    }
}
