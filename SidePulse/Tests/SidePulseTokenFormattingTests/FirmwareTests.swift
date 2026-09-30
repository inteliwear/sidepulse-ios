import CryptoKit
import XCTest
@testable import SidePulseTokenFormatting

final class FirmwareTests: XCTestCase {
    func testDotAndProStatusWithWhitespaceAndPadding() throws {
        let dot = try FirmwareDevice.parse(Data("app_version 1.1.0\r\nserial\tSP-123\r\n\0\0".utf8))
        XCTAssertEqual(dot.product, .dot)
        XCTAssertEqual(dot.version, FirmwareVersion("1.1.0"))
        XCTAssertEqual(dot.serial, "SP-123")
        let pro = try FirmwareDevice.parse(Data("release_version 1.0.5\nserial SP-456\n".utf8))
        XCTAssertEqual(pro.product, .pro)
        XCTAssertEqual(pro.versionText, "1.0.5")
    }

    func testOlderStatusDoesNotMistakeBuildNumberForRelease() throws {
        let dot = try FirmwareDevice.parse(Data("app_build 22\nfw_state active\n".utf8))
        let pro = try FirmwareDevice.parse(Data("firmware_version 99\nfirmware_slot 1\n".utf8))
        XCTAssertEqual(dot.product, .dot)
        XCTAssertEqual(pro.product, .pro)
        XCTAssertNil(dot.version)
        XCTAssertNil(pro.version)
    }

    func testInvalidAndAmbiguousStatusCannotSelectFirmware() {
        for text in ["", "firmware_version 99\n", "app_version 1.1.0\nrelease_version 1.1.0\n", "app_version=1.1.0"] {
            XCTAssertThrowsError(try FirmwareDevice.parse(Data(text.utf8)))
        }
        XCTAssertThrowsError(try FirmwareDevice.parse(Data(repeating: 0, count: 65_537)))
    }

    func testVersionsAreNumericAndRejectPrereleasesAndPaths() throws {
        XCTAssertLessThan(FirmwareVersion("1.9.0")!, FirmwareVersion("1.10.0")!)
        XCTAssertEqual(FirmwareVersion("v1.1"), FirmwareVersion("1.1.0"))
        for text in ["1.1.0-beta", "../1.1.0", "1.-1.0", "1.1.0.0", "1..0", " 1.1.0", String(repeating: "9", count: 100) + ".1.0"] {
            XCTAssertNil(FirmwareVersion(text))
        }
        let list = Data("""
        [{"name":"v1.9.0","type":"dir"},{"name":"v1.10.0","type":"dir"},
         {"name":"v2.0.0-beta","type":"dir"},{"name":"v3.0.0","type":"file"}]
        """.utf8)
        XCTAssertEqual(try FirmwareService.versions(in: list).map(\.description), ["1.10.0", "1.9.0"])
        XCTAssertThrowsError(try FirmwareService.versions(in: Data("{}".utf8)))
    }

    func testNoDowngradeOrSameVersionUpdate() throws {
        let data = try fixture(.dot)
        let release = makeRelease(.dot, data)
        for version in ["1.1.0", "1.2.0", "2.0.0"] {
            XCTAssertFalse(release.isNewer(than: FirmwareDevice(product: .dot, versionText: version, serial: "test")))
        }
        XCTAssertTrue(release.isNewer(than: FirmwareDevice(product: .dot, versionText: "1.0.5", serial: "test")))
        XCTAssertFalse(release.isNewer(than: FirmwareDevice(product: .pro, versionText: "1.0.5", serial: "test")))
    }

    func testCompressedNestedAndStoredFlatCustomerPackages() throws {
        for product in [FirmwareProduct.dot, .pro] {
            let data = try fixture(product)
            let package = try FirmwarePackage.verify(data, release: makeRelease(product, data))
            XCTAssertEqual(package.payload, Data("TEST ONLY: synthetic firmware payload. Never install.\n".utf8))
            XCTAssertEqual(package.release.product, product)
        }
    }

    func testOuterChecksumDetectsDownloadCorruption() throws {
        let data = try fixture(.dot)
        var corrupt = data
        corrupt[20] ^= 1
        XCTAssertThrowsError(try FirmwarePackage.verify(corrupt, release: makeRelease(.dot, data))) { error in
            XCTAssertEqual(error as? FirmwareError, .checksumMismatch)
        }
    }

    func testInnerChecksumDetectsChangedFirmwareEvenWithMatchingZIPHash() throws {
        var data = try fixture(.pro)
        let range = try XCTUnwrap(data.range(of: Data("TEST ONLY".utf8)))
        data[range.lowerBound] ^= 1
        XCTAssertThrowsError(try FirmwarePackage.verify(data, release: makeRelease(.pro, data))) { error in
            XCTAssertEqual(error as? FirmwareError, .checksumMismatch)
        }
    }

    func testRenamedModelAndVersionAreRejected() throws {
        let data = try fixture(.pro)
        XCTAssertThrowsError(try FirmwarePackage.verify(data, release: makeRelease(.dot, data)))
        let wrongVersion = FirmwareRelease(product: .pro, version: FirmwareVersion("2.0.0")!, checksum: digest(data))
        XCTAssertThrowsError(try FirmwarePackage.verify(data, release: wrongVersion))
    }

    func testTruncatedZIPAndOversizedExpandedImageAreRejected() throws {
        let data = try fixture(.pro)
        for count in [0, 10, data.count - 1] {
            let truncated = Data(data.prefix(count))
            XCTAssertThrowsError(try FirmwarePackage.verify(truncated, release: makeRelease(.pro, truncated)))
        }
        var oversized = data
        let central = try XCTUnwrap(data.range(of: Data([0x50, 0x4b, 0x01, 0x02]))).lowerBound
        // Central-directory expanded size = 4 MiB + 1.
        oversized.replaceSubrange((central + 24)..<(central + 28), with: [1, 0, 64, 0])
        XCTAssertThrowsError(try FirmwarePackage.verify(oversized, release: makeRelease(.pro, oversized)))
    }

    func testSymlinkEncryptedAndTraversalEntriesAreRejected() throws {
        let data = try fixture(.pro)
        let central = try XCTUnwrap(data.range(of: Data([0x50, 0x4b, 0x01, 0x02]))).lowerBound
        var symlink = data
        symlink.replaceSubrange((central + 38)..<(central + 42), with: [0, 0, 0xff, 0xa1])
        var encrypted = data
        encrypted[central + 8] |= 1
        var traversal = data
        let name = try XCTUnwrap(traversal.range(of: Data("FIRMWARE.BIN".utf8)))
        traversal.replaceSubrange(name, with: Data("../EVIL_.BIN".utf8))
        for invalid in [symlink, encrypted, traversal] {
            XCTAssertThrowsError(try FirmwarePackage.verify(invalid, release: makeRelease(.pro, invalid)))
        }
    }

    func testChecksumsRejectDuplicatesMissingAndMalformedDigests() {
        let valid = String(repeating: "a", count: 64) + "  FIRMWARE.BIN\n"
        XCTAssertThrowsError(try FirmwareChecksums.parse(Data((valid + valid).utf8)))
        XCTAssertThrowsError(try FirmwareChecksums.parse(Data("bad  FIRMWARE.BIN\n".utf8)))
        XCTAssertThrowsError(try FirmwareChecksums.parse(Data((String(repeating: "g", count: 64) + "  FIRMWARE.BIN\n").utf8)))
        XCTAssertThrowsError(try FirmwareChecksums.parse(Data((String(repeating: "a", count: 64) + "  ../FIRMWARE.BIN\n").utf8)))
    }

    func testLatestReleaseFallsBackWhenNewerReleaseIsForOtherModel() async throws {
        let data = try fixture(.dot)
        var requests: [String] = []
        let service = FirmwareService { url, _ in
            requests.append(url.absoluteString)
            if url.host == "api.github.com" {
                return Data("[{\"name\":\"v1.2.0\",\"type\":\"dir\"},{\"name\":\"v1.1.0\",\"type\":\"dir\"}]".utf8)
            }
            if url.path.contains("v1.2.0") { return Data((String(repeating: "a", count: 64) + "  sidepulse-pro-1.2.0-ota.zip\n").utf8) }
            return Data("\(self.digest(data))  sidepulse-dot-1.1.0-ota.zip\n".utf8)
        }
        let release = try await service.latestRelease(for: .dot)
        XCTAssertEqual(release.version.description, "1.1.0")
        XCTAssertEqual(requests.count, 3)
    }

    func testPendingInstallationNeedsMatchingDeviceFolderVersionAndTenSeconds() {
        let original = FirmwareDevice(product: .dot, versionText: "1.0.5", serial: "SP-123")
        let upgraded = FirmwareDevice(product: .dot, versionText: "1.1.0", serial: "SP-123")
        let bookmark = Data([1, 2])
        let date = Date()
        let pending = FirmwareUpdateModel.PendingInstall(device: original, version: FirmwareVersion("1.1.0")!, transferredAt: date, bookmark: bookmark)
        XCTAssertFalse(pending.confirms(upgraded, bookmark: bookmark, now: date.addingTimeInterval(9)))
        XCTAssertFalse(pending.confirms(original, bookmark: bookmark, now: date.addingTimeInterval(11)))
        XCTAssertFalse(pending.confirms(upgraded, bookmark: Data([3]), now: date.addingTimeInterval(11)))
        XCTAssertFalse(pending.confirms(FirmwareDevice(product: .dot, versionText: "1.1.0", serial: "other"), bookmark: bookmark, now: date.addingTimeInterval(11)))
        XCTAssertTrue(pending.confirms(upgraded, bookmark: bookmark, now: date.addingTimeInterval(11)))
    }

    fileprivate func fixture(_ product: FirmwareProduct) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: product.rawValue, withExtension: "zip", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    fileprivate func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    fileprivate func makeRelease(_ product: FirmwareProduct, _ data: Data) -> FirmwareRelease {
        FirmwareRelease(product: product, version: FirmwareVersion("1.1.0")!, checksum: digest(data))
    }
}

@MainActor
final class FirmwareUpdateModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let original = DriveWriter.FirmwareSnapshot(
        device: FirmwareDevice(product: .dot, versionText: "1.0.5", serial: "SP-123"), bookmark: Data([1]))

    override func setUp() async throws {
        suite = "firmware-tests-\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }

    func testOptOutPerformsNoAutomaticReadsOrDownloads() async {
        var reads = 0
        let model = FirmwareUpdateModel(defaults: defaults, service: FirmwareService { _, _ in
            XCTFail("Opt-out must not download")
            throw FirmwareError.invalidRelease
        }, readStatus: {
            reads += 1
            return self.original
        })
        XCTAssertFalse(model.automaticChecks)
        XCTAssertNil(model.checkOnAppOpen(isConnected: true))
        XCTAssertEqual(reads, 0)
    }

    func testRepeatedAppOpensDoNotReadStatusOrFetchReleasesMoreThanDaily() async throws {
        defaults.set(true, forKey: "firmwareAutomaticChecks")
        let helper = FirmwareTests()
        let zip = try helper.fixture(.dot)
        var downloads = 0
        var reads = 0
        let service = FirmwareService { url, _ in
            downloads += 1
            if url.host == "api.github.com" { return Data("[{\"name\":\"v1.1.0\",\"type\":\"dir\"}]".utf8) }
            return Data("\(helper.digest(zip))  sidepulse-dot-1.1.0-ota.zip\n".utf8)
        }
        let model = FirmwareUpdateModel(defaults: defaults, service: service, readStatus: {
            reads += 1
            return self.original
        })
        await model.checkOnAppOpen(isConnected: true)?.value
        XCTAssertEqual(downloads, 2)
        XCTAssertTrue(model.updateAvailable)
        await model.checkOnAppOpen(isConnected: true)?.value
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(downloads, 2)
        await model.refresh(forceReleaseCheck: true)
        XCTAssertEqual(downloads, 4)
        XCTAssertNil(model.checkOnAppOpen(isConnected: false))
        XCTAssertNil(model.device)
        XCTAssertFalse(model.updateAvailable)
        model.automaticChecks = false
        XCTAssertFalse(defaults.bool(forKey: "firmwareAutomaticChecks"))
    }

    func testDailyLimitSurvivesRelaunchAndExpiresAfter24Hours() async throws {
        defaults.set(true, forKey: "firmwareAutomaticChecks")
        let helper = FirmwareTests()
        let zip = try helper.fixture(.dot)
        var time = Date(timeIntervalSince1970: 1_800_000_000)
        var reads = 0
        var downloads = 0
        let service = FirmwareService { url, _ in
            downloads += 1
            if url.host == "api.github.com" { return Data("[{\"name\":\"v1.1.0\",\"type\":\"dir\"}]".utf8) }
            return Data("\(helper.digest(zip))  sidepulse-dot-1.1.0-ota.zip\n".utf8)
        }
        func makeModel() -> FirmwareUpdateModel {
            FirmwareUpdateModel(defaults: defaults, service: service, now: { time }, readStatus: {
                reads += 1
                return self.original
            })
        }
        await makeModel().checkOnAppOpen(isConnected: true)?.value
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(downloads, 2)
        time = time.addingTimeInterval(86_399)
        let relaunched = makeModel()
        XCTAssertNil(relaunched.checkOnAppOpen(isConnected: true))
        relaunched.connectionChanged(isConnected: true)
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(downloads, 2)
        time = time.addingTimeInterval(1)
        await relaunched.checkOnAppOpen(isConnected: true)?.value
        XCTAssertEqual(reads, 4)
        XCTAssertEqual(downloads, 4)
        XCTAssertTrue(relaunched.updateAvailable)
    }

    func testManualCheckWorksWithoutOptInAndInstallationIsNotAssumedSuccessful() async throws {
        let helper = FirmwareTests()
        let zip = try helper.fixture(.dot)
        var writes = 0
        let service = FirmwareService { url, _ in
            if url.pathExtension == "zip" { return zip }
            if url.host == "api.github.com" { return Data("[{\"name\":\"v1.1.0\",\"type\":\"dir\"}]".utf8) }
            return Data("\(helper.digest(zip))  sidepulse-dot-1.1.0-ota.zip\n".utf8)
        }
        let model = FirmwareUpdateModel(defaults: defaults, service: service,
            readStatus: { self.original }, writeFirmware: { package, expected in
                writes += 1
                XCTAssertEqual(expected, self.original)
                XCTAssertFalse(package.payload.isEmpty)
            })
        await model.refresh(forceReleaseCheck: true)
        XCTAssertTrue(model.canInstall)
        XCTAssertEqual(writes, 0)
        await model.install(expectedDevice: FirmwareDevice(product: .dot, versionText: "1.0.5", serial: "another-device"))
        XCTAssertEqual(writes, 0)
        XCTAssertNil(model.pending)
        XCTAssertNotNil(model.error)
        await model.install()
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(model.device?.versionText, "1.0.5")
        XCTAssertNotNil(model.pending)
        XCTAssertFalse(model.canInstall)
        XCTAssertNotNil(defaults.data(forKey: "firmwarePendingInstall"))
        XCTAssertTrue(model.message.contains("transferred"))
        XCTAssertFalse(model.message.lowercased().contains("reconnect"))
    }

    func testNetworkFailureStillCountsTowardDailyLimitAndManualChecksRemainAvailable() async {
        defaults.set(true, forKey: "firmwareAutomaticChecks")
        var downloads = 0
        var readable = true
        var time = Date()
        let model = FirmwareUpdateModel(defaults: defaults, service: FirmwareService { _, _ in
            downloads += 1
            throw URLError(.notConnectedToInternet)
        }, now: { time }, readStatus: {
            if !readable { throw FirmwareError.invalidStatus }
            return self.original
        })
        await model.checkOnAppOpen(isConnected: true)?.value
        XCTAssertNotNil(model.error)
        await model.checkOnAppOpen(isConnected: true)?.value
        XCTAssertEqual(downloads, 1)
        XCTAssertNotNil(model.error)
        let relaunched = FirmwareUpdateModel(defaults: defaults, service: FirmwareService { _, _ in
            downloads += 1
            throw URLError(.notConnectedToInternet)
        }, now: { time }, readStatus: { self.original })
        XCTAssertNil(relaunched.checkOnAppOpen(isConnected: true))
        time = time.addingTimeInterval(86_400)
        await relaunched.checkOnAppOpen(isConnected: true)?.value
        XCTAssertEqual(downloads, 2)
        readable = false
        await model.refresh(forceReleaseCheck: true)
        XCTAssertNil(model.device)
        XCTAssertFalse(model.canInstall)
    }

    func testEnablingChecksWithoutAConnectedDeviceDoesNotReadOrFetch() {
        let model = FirmwareUpdateModel(defaults: defaults, service: FirmwareService { _, _ in
            XCTFail("No device is connected")
            throw FirmwareError.invalidRelease
        }, readStatus: {
            XCTFail("No device is connected")
            return self.original
        })
        model.automaticChecks = true
        XCTAssertTrue(defaults.bool(forKey: "firmwareAutomaticChecks"))
        XCTAssertNil(model.checkOnAppOpen(isConnected: false))
        XCTAssertNil(model.error)
    }

    func testOptingOutCancelsAnInFlightAutomaticCheck() async {
        defaults.set(true, forKey: "firmwareAutomaticChecks")
        let requested = expectation(description: "Listing requested")
        var downloads = 0
        var resume: CheckedContinuation<Data, Never>?
        let model = FirmwareUpdateModel(defaults: defaults, service: FirmwareService { _, _ in
            downloads += 1
            return await withCheckedContinuation { continuation in
                resume = continuation
                requested.fulfill()
            }
        }, readStatus: { self.original })
        let task = model.checkOnAppOpen(isConnected: true)
        await fulfillment(of: [requested], timeout: 2)
        model.automaticChecks = false
        resume?.resume(returning: Data("[{\"name\":\"v1.1.0\",\"type\":\"dir\"}]".utf8))
        await task?.value
        XCTAssertEqual(downloads, 1)
        XCTAssertNil(model.release)
        XCTAssertNil(model.error)
    }

    func testPendingInstallCanConfirmLocallyWithAutomaticChecksDisabled() async throws {
        let upgraded = DriveWriter.FirmwareSnapshot(device: FirmwareDevice(product: .dot, versionText: "1.1.0", serial: "SP-123"), bookmark: original.bookmark)
        let pending = FirmwareUpdateModel.PendingInstall(device: original.device, version: FirmwareVersion("1.1.0")!, transferredAt: Date().addingTimeInterval(-20), bookmark: original.bookmark)
        defaults.set(try JSONEncoder().encode(pending), forKey: "firmwarePendingInstall")
        let model = FirmwareUpdateModel(defaults: defaults, service: FirmwareService { _, _ in
            XCTFail("Local installation confirmation must not require opting in to release checks")
            throw FirmwareError.invalidRelease
        }, readStatus: { upgraded })
        await model.checkOnAppOpen(isConnected: true)?.value
        XCTAssertNil(model.pending)
        XCTAssertNil(defaults.data(forKey: "firmwarePendingInstall"))
        XCTAssertTrue(model.message.contains("Confirmed in STATUS.TXT"))
    }
}
