// Copyright (c) 2026 InteliWEAR LLC.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. https://mozilla.org/MPL/2.0/.

import Compression
import CryptoKit
import Foundation

enum FirmwareError: LocalizedError, Equatable {
    case invalidStatus, invalidRelease, invalidPackage, checksumMismatch, downloadTooLarge
    case server(Int), deviceChanged, downgrade

    var errorDescription: String? {
        switch self {
        case .invalidStatus: "STATUS.TXT does not identify a SidePulse Dot or Pro. Select the device’s top-level folder and try again."
        case .invalidRelease: "The firmware release information is invalid or no release is available for this model."
        case .invalidPackage: "The firmware ZIP is invalid or does not match this model and version."
        case .checksumMismatch: "Firmware verification failed. Nothing was written. Check again to download a fresh copy."
        case .downloadTooLarge: "The firmware download exceeds the size limit."
        case .server(let code): "The firmware server returned an error (\(code)). Try again later."
        case .deviceChanged: "The connected device or selected folder changed. Check firmware again before updating."
        case .downgrade: "This firmware is not newer than the installed version."
        }
    }
}

struct FirmwareVersion: Equatable, Comparable, Codable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ text: String) {
        var value = text
        if value.hasPrefix("v") { value.removeFirst() }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({
            !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) }
        }), let major = Int(parts[0]), let minor = Int(parts[1]),
              let patch = parts.count == 3 ? Int(parts[2]) : 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

enum FirmwareProduct: String, Codable {
    case dot, pro
    var name: String { self == .dot ? "SidePulse Dot" : "SidePulse Pro" }
}

struct FirmwareDevice: Equatable, Codable {
    let product: FirmwareProduct
    let versionText: String
    let serial: String
    var version: FirmwareVersion? { FirmwareVersion(versionText) }

    static func parse(_ data: Data) throws -> Self {
        guard data.count <= 65_536 else { throw FirmwareError.invalidStatus }
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\0", with: "")
        var fields: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            if parts.count == 2 { fields[String(parts[0])] = String(parts[1]).trimmingCharacters(in: .whitespaces) }
        }
        let dot = fields["app_version"] != nil || (fields["app_build"] != nil && fields["fw_state"] != nil)
        let pro = fields["release_version"] != nil || (fields["firmware_version"] != nil && fields["firmware_slot"] != nil)
        guard dot != pro else { throw FirmwareError.invalidStatus }
        return Self(product: dot ? .dot : .pro,
                    versionText: fields[dot ? "app_version" : "release_version"] ?? "unknown",
                    serial: fields["serial"] ?? "unassigned")
    }
}

struct FirmwareRelease: Equatable, Codable {
    let product: FirmwareProduct
    let version: FirmwareVersion
    let checksum: String
    var filename: String { "sidepulse-\(product.rawValue)-\(version)-ota.zip" }
    var baseURL: URL {
        URL(string: "https://raw.githubusercontent.com/inteliwear/sidepulse/main/firmware/v\(version)")!
    }
    var downloadURL: URL { baseURL.appendingPathComponent(filename) }

    func isNewer(than device: FirmwareDevice) -> Bool {
        product == device.product && (device.version.map { version > $0 } ?? true)
    }
}

struct FirmwarePackage {
    let release: FirmwareRelease
    let payload: Data

    static func verify(_ data: Data, release: FirmwareRelease) throws -> Self {
        guard data.count <= FirmwareService.maxPackageBytes else { throw FirmwareError.downloadTooLarge }
        try FirmwareChecksums.verify(data, expected: release.checksum)
        let files = try FirmwareZIP.read(data, filename: release.filename)
        guard let sums = files["SHA256SUMS.txt"] else { throw FirmwareError.invalidPackage }
        let checksums = try FirmwareChecksums.parse(sums)
        guard Set(checksums.keys) == Set(["FIRMWARE.BIN", "README.txt", "RELEASE_NOTES.txt"]) else {
            throw FirmwareError.invalidPackage
        }
        for (name, digest) in checksums {
            guard let contents = files[name] else { throw FirmwareError.invalidPackage }
            try FirmwareChecksums.verify(contents, expected: digest)
        }
        let title = "\(release.product.name) firmware update - version \(release.version)"
        guard let readme = files["README.txt"],
              String(decoding: readme, as: UTF8.self).components(separatedBy: .newlines).first == title,
              let payload = files["FIRMWARE.BIN"], !payload.isEmpty else { throw FirmwareError.invalidPackage }
        return Self(release: release, payload: payload)
    }
}

enum FirmwareChecksums {
    static func parse(_ data: Data) throws -> [String: String] {
        guard let text = String(data: data, encoding: .utf8) else { throw FirmwareError.invalidRelease }
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let parts = line.components(separatedBy: "  ")
            guard parts.count == 2, parts[0].count == 64,
                  parts[0].utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                  !parts[1].isEmpty,
                  parts[1].utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) }),
                  result[parts[1]] == nil else { throw FirmwareError.invalidRelease }
            result[parts[1]] = parts[0].lowercased()
        }
        return result
    }

    static func verify(_ data: Data, expected: String) throws {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expected.lowercased() else { throw FirmwareError.checksumMismatch }
    }
}

struct FirmwareService {
    static let maxPackageBytes = 4 * 1024 * 1024
    typealias Download = (URL, Int) async throws -> Data
    let download: Download

    init(download: @escaping Download = FirmwareService.downloadData) { self.download = download }

    struct Entry: Decodable { let name: String; let type: String }

    static func versions(in data: Data) throws -> [FirmwareVersion] {
        let entries: [Entry]
        do { entries = try JSONDecoder().decode([Entry].self, from: data) }
        catch { throw FirmwareError.invalidRelease }
        let versions = entries.compactMap { entry -> FirmwareVersion? in
            guard entry.type == "dir", let version = FirmwareVersion(entry.name),
                  entry.name == "v\(version)" else { return nil }
            return version
        }.sorted(by: >)
        guard !versions.isEmpty else { throw FirmwareError.invalidRelease }
        return versions
    }

    func latestRelease(for product: FirmwareProduct) async throws -> FirmwareRelease {
        let url = URL(string: "https://api.github.com/repos/inteliwear/sidepulse/contents/firmware?ref=main")!
        for version in try Self.versions(in: await download(url, 1024 * 1024)) {
            try Task.checkCancellation()
            let filename = "sidepulse-\(product.rawValue)-\(version)-ota.zip"
            let base = URL(string: "https://raw.githubusercontent.com/inteliwear/sidepulse/main/firmware/v\(version)")!
            let checksums = try FirmwareChecksums.parse(await download(base.appendingPathComponent("SHA256SUMS.txt"), 65_536))
            try Task.checkCancellation()
            if let checksum = checksums[filename] {
                return FirmwareRelease(product: product, version: version, checksum: checksum)
            }
        }
        throw FirmwareError.invalidRelease
    }

    func package(for release: FirmwareRelease) async throws -> FirmwarePackage {
        let data = try await download(release.downloadURL, Self.maxPackageBytes)
        return try FirmwarePackage.verify(data, release: release)
    }

    static func downloadData(_ url: URL, limit: Int) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("SidePulse-iOS", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw FirmwareError.invalidRelease }
        guard http.statusCode == 200 else { throw FirmwareError.server(http.statusCode) }
        guard response.expectedContentLength <= Int64(limit) else { throw FirmwareError.downloadTooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw FirmwareError.downloadTooLarge }
            data.append(byte)
        }
        return data
    }
}

/// A bounded reader for the four-file customer OTA ZIP format. No entries are
/// extracted to disk; ZIP64, encryption, links, and unexpected files are rejected.
private enum FirmwareZIP {
    static func read(_ data: Data, filename: String) throws -> [String: Data] {
        let bytes = [UInt8](data)
        func number(_ offset: Int, _ count: Int) throws -> Int {
            guard offset >= 0, offset <= bytes.count - count else { throw FirmwareError.invalidPackage }
            return (0..<count).reduce(0) { $0 | (Int(bytes[offset + $1]) << ($1 * 8)) }
        }
        func slice(_ offset: Int, _ count: Int) throws -> Data {
            guard offset >= 0, count >= 0, offset <= bytes.count - count else { throw FirmwareError.invalidPackage }
            return Data(bytes[offset..<(offset + count)])
        }
        guard bytes.count >= 22 else { throw FirmwareError.invalidPackage }
        var end: Int?
        for offset in stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1) {
            if try number(offset, 4) == 0x06054b50,
               try offset + 22 + number(offset + 20, 2) == bytes.count { end = offset; break }
        }
        guard let end, try number(end + 4, 2) == 0, try number(end + 6, 2) == 0,
              try number(end + 8, 2) == 4, try number(end + 10, 2) == 4 else { throw FirmwareError.invalidPackage }
        let directorySize = try number(end + 12, 4)
        var cursor = try number(end + 16, 4)
        guard cursor + directorySize == end else { throw FirmwareError.invalidPackage }
        let required: Set<String> = ["FIRMWARE.BIN", "README.txt", "RELEASE_NOTES.txt", "SHA256SUMS.txt"]
        let prefix = String(filename.dropLast(4)) + "/"
        var contents: [String: Data] = [:]
        var totalSize = 0
        var nested: Bool?
        for _ in 0..<4 {
            guard try number(cursor, 4) == 0x02014b50 else { throw FirmwareError.invalidPackage }
            let flags = try number(cursor + 8, 2)
            let method = try number(cursor + 10, 2)
            let compressedSize = try number(cursor + 20, 4)
            let size = try number(cursor + 24, 4)
            let nameSize = try number(cursor + 28, 2)
            let extraSize = try number(cursor + 30, 2)
            let commentSize = try number(cursor + 32, 2)
            let attributes = try number(cursor + 38, 4)
            let local = try number(cursor + 42, 4)
            guard flags & 0x41 == 0, [0, 8].contains(method),
                  (attributes >> 16) & 0xf000 != 0xa000,
                  try number(cursor + 34, 2) == 0,
                  compressedSize > 0, compressedSize <= FirmwareService.maxPackageBytes,
                  size > 0, size <= FirmwareService.maxPackageBytes else { throw FirmwareError.invalidPackage }
            totalSize += size
            guard totalSize <= FirmwareService.maxPackageBytes,
                  let name = String(data: try slice(cursor + 46, nameSize), encoding: .utf8) else { throw FirmwareError.invalidPackage }
            let isNested = name.hasPrefix(prefix)
            if let nested, nested != isNested { throw FirmwareError.invalidPackage }
            nested = isNested
            let shortName = isNested ? String(name.dropFirst(prefix.count)) : name
            guard required.contains(shortName), contents[shortName] == nil,
                  try number(local, 4) == 0x04034b50,
                  try number(local + 6, 2) == flags, try number(local + 8, 2) == method else { throw FirmwareError.invalidPackage }
            let localNameSize = try number(local + 26, 2)
            let localExtraSize = try number(local + 28, 2)
            guard try slice(local + 30, localNameSize) == slice(cursor + 46, nameSize) else { throw FirmwareError.invalidPackage }
            let start = local + 30 + localNameSize + localExtraSize
            guard start + compressedSize <= cursor else { throw FirmwareError.invalidPackage }
            let compressed = try slice(start, compressedSize)
            let output: Data
            if method == 0 {
                guard compressedSize == size else { throw FirmwareError.invalidPackage }
                output = compressed
            } else {
                // One extra byte lets us detect a stream larger than its declared size.
                var buffer = [UInt8](repeating: 0, count: size + 1)
                let decoded = compressed.withUnsafeBytes { source in
                    buffer.withUnsafeMutableBufferPointer { destination in
                        compression_decode_buffer(destination.baseAddress!, size + 1,
                                                  source.bindMemory(to: UInt8.self).baseAddress!, compressedSize,
                                                  nil, COMPRESSION_ZLIB)
                    }
                }
                guard decoded == size else { throw FirmwareError.invalidPackage }
                output = Data(buffer.prefix(size))
            }
            contents[shortName] = output
            cursor += 46 + nameSize + extraSize + commentSize
            guard cursor <= end else { throw FirmwareError.invalidPackage }
        }
        guard cursor == end, Set(contents.keys) == required else { throw FirmwareError.invalidPackage }
        return contents
    }
}
