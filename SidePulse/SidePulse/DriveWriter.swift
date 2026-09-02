import Foundation

enum DriveWriterError: LocalizedError {
    case noFolderSelected
    case bookmarkStale
    case accessDenied
    case textTooLarge(Int)
    case tooManyLines(Int)
    case missingText

    var errorDescription: String? {
        switch self {
        case .noFolderSelected:
            return "Pick the USB drive folder first."
        case .bookmarkStale:
            return "The saved Files permission is stale. Pick the USB folder again."
        case .accessDenied:
            return "iOS did not grant access to the selected USB folder."
        case .textTooLarge(let byteCount):
            return "LEDS.LED is \(byteCount) bytes. Keep it at or below 512 bytes."
        case .tooManyLines(let lineCount):
            return "LEDS.LED has \(lineCount) physical lines. Keep it at or below 20 lines."
        case .missingText:
            return "No LED text was provided."
        }
    }
}

final class DriveWriter {
    static let shared = DriveWriter()

    private let bookmarkKey = "usbFolderBookmark"
    private let defaultFileName = "LEDS.LED"
    private let maxLEDBytes = 512
    private let maxLEDLines = 20

    private init() {}

    var fileName: String {
        defaultFileName
    }

    var hasSavedFolder: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    var savedFolderDisplayName: String {
        guard let url = try? resolveFolderURL() else {
            return "No USB folder selected"
        }

        return url.path
    }

    func saveFolder(_ url: URL) throws {
        EventLog.append("Saving USB folder bookmark: \(url.lastPathComponent)")
        let startedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let bookmark = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        EventLog.append("Saved USB folder bookmark")
    }

    @discardableResult
    func write(_ text: String) throws -> URL {
        let program = normalizeLEDText(text)
        let trimmed = program.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DriveWriterError.missingText
        }

        let byteCount = program.data(using: .utf8)?.count ?? 0
        guard byteCount <= maxLEDBytes else {
            throw DriveWriterError.textTooLarge(byteCount)
        }

        let lineCount = physicalLineCount(program)
        guard lineCount <= maxLEDLines else {
            throw DriveWriterError.tooManyLines(lineCount)
        }

        let folderURL = try resolveFolderURL()
        let startedAccess = folderURL.startAccessingSecurityScopedResource()
        guard startedAccess else {
            throw DriveWriterError.accessDenied
        }

        defer {
            folderURL.stopAccessingSecurityScopedResource()
        }

        let targetURL = folderURL.appendingPathComponent(fileName, isDirectory: false)
        let data = Data(program.utf8)
        try data.write(to: targetURL)
        EventLog.append("Wrote \(data.count) bytes to \(targetURL.lastPathComponent)")
        return targetURL
    }

    private func resolveFolderURL() throws -> URL {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            throw DriveWriterError.noFolderSelected
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            throw DriveWriterError.bookmarkStale
        }

        return url
    }

    private func physicalLineCount(_ text: String) -> Int {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).count
        if normalized.hasSuffix("\n") {
            lines -= 1
        }
        return max(lines, 1)
    }

    private func normalizeLEDText(_ text: String) -> String {
        var output = ""
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            guard character == "\\",
                  let nextIndex = text.index(index, offsetBy: 1, limitedBy: text.endIndex),
                  nextIndex < text.endIndex else {
                output.append(character)
                index = text.index(after: index)
                continue
            }

            let nextCharacter = text[nextIndex]
            switch nextCharacter {
            case "n":
                output.append("\n")
                index = text.index(after: nextIndex)
            case "r":
                output.append("\r")
                index = text.index(after: nextIndex)
            case "t":
                output.append("\t")
                index = text.index(after: nextIndex)
            case "\\":
                output.append("\\")
                index = text.index(after: nextIndex)
            default:
                output.append(character)
                index = text.index(after: index)
            }
        }

        return output
    }
}
