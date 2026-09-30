// Copyright (c) 2026 InteliWEAR LLC.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Darwin

enum DriveWriterError: LocalizedError {
    case noFolderSelected
    case bookmarkStale
    case accessDenied
    case textTooLarge(Int)
    case tooManyLines(Int)
    case missingText
    case firmwareBusy

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
        case .firmwareBusy:
            return "Firmware is being applied. Keep the device connected and wait at least 10 seconds before playing patterns."
        }
    }
}

final class DriveWriter {
    static let shared = DriveWriter()

    private let bookmarkKey = "usbFolderBookmark"
    private let defaultFileName = "LEDS.LED"
    private let maxLEDBytes = 512
    private let maxLEDLines = 20
    private let ioLock = NSLock()
    private var firmwareQuietUntil = UserDefaults.standard.object(forKey: "firmwareQuietUntil") as? Date ?? .distantPast

    private init() {}

    var fileName: String {
        defaultFileName
    }

    var hasSavedFolder: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    var isFolderAvailable: Bool {
        guard let url = try? resolveFolderURL() else {
            return false
        }
        guard url.startAccessingSecurityScopedResource() else { return false }
        defer { url.stopAccessingSecurityScopedResource() }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    func saveFolder(_ url: URL) throws {
        ioLock.lock()
        defer { ioLock.unlock() }
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
        ioLock.lock()
        defer { ioLock.unlock() }
        guard Date() >= firmwareQuietUntil else { throw DriveWriterError.firmwareBusy }
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

    struct FirmwareSnapshot: Equatable {
        let device: FirmwareDevice
        let bookmark: Data
    }

    func readFirmwareStatus() throws -> FirmwareSnapshot {
        ioLock.lock()
        defer { ioLock.unlock() }
        let folder = try resolveFolderURL()
        guard folder.startAccessingSecurityScopedResource() else { throw DriveWriterError.accessDenied }
        defer { folder.stopAccessingSecurityScopedResource() }
        return try firmwareSnapshot(in: folder)
    }

    private func firmwareSnapshot(in folder: URL) throws -> FirmwareSnapshot {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { throw DriveWriterError.noFolderSelected }
        let handle = try FileHandle(forReadingFrom: folder.appendingPathComponent("STATUS.TXT"))
        defer { try? handle.close() }
        // Reopen every time and ask Darwin to avoid caching device-generated status.
        _ = fcntl(handle.fileDescriptor, F_NOCACHE, 1)
        let data = try handle.read(upToCount: 65_537) ?? Data()
        return try FirmwareSnapshot(device: FirmwareDevice.parse(data), bookmark: bookmark)
    }

    func writeFirmware(_ package: FirmwarePackage, expected: FirmwareSnapshot) throws {
        ioLock.lock()
        defer { ioLock.unlock() }
        guard Date() >= firmwareQuietUntil else { throw DriveWriterError.firmwareBusy }
        let folder = try resolveFolderURL()
        guard folder.startAccessingSecurityScopedResource() else { throw DriveWriterError.accessDenied }
        defer { folder.stopAccessingSecurityScopedResource() }
        // Recheck the device and permission after the download, immediately before writing.
        guard try firmwareSnapshot(in: folder) == expected else { throw FirmwareError.deviceChanged }
        guard package.release.isNewer(than: expected.device) else { throw FirmwareError.downgrade }
        let target = folder.appendingPathComponent("FIRMWARE.BIN")
        let descriptor = open(target.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            try? handle.close()
            // A partial transfer may also start the updater. Protect its restart window.
            firmwareQuietUntil = Date().addingTimeInterval(10)
            UserDefaults.standard.set(firmwareQuietUntil, forKey: "firmwareQuietUntil")
        }
        // Write in place: an atomic temporary-file rename is unsuitable for this USB filesystem.
        try handle.write(contentsOf: package.payload)
        try handle.synchronize()
        try handle.close()
        EventLog.append("Transferred firmware \(package.release.version) for \(package.release.product.name); awaiting STATUS.TXT confirmation")
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
