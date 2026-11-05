import XCTest
import FileProvider
@testable import SidePulseTokenFormatting

final class ShortcutDriveAvailabilityTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let target = URL(fileURLWithPath: "/Volumes/PulseDot/LEDS.LED")
    private var disconnected: NSError {
        NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.providerNotFound.rawValue)
    }

    override func setUp() {
        super.setUp()
        suiteName = "ShortcutDriveAvailabilityTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testProviderWarningIsFriendlyAndOnlyShownOnceAcrossLaunches() throws {
        let gate = ShortcutDriveAvailability(defaults: defaults)
        XCTAssertThrowsError(try gate.perform { throw disconnected }) { error in
            guard case DriveWriterError.deviceUnavailable = error else {
                return XCTFail("Expected an actionable connection warning, got \(error)")
            }
        }
        let relaunched = ShortcutDriveAvailability(defaults: UserDefaults(suiteName: suiteName)!)
        XCTAssertNil(try relaunched.perform { throw disconnected })
        XCTAssertNil(try gate.perform { throw DriveWriterError.accessDenied })
    }

    func testSkippedWritesStillRetryAndSuccessfulWriteResetsWarning() throws {
        let gate = ShortcutDriveAvailability(defaults: defaults)
        XCTAssertThrowsError(try gate.perform { throw disconnected })
        var attempts = 0
        XCTAssertNil(try gate.perform {
            attempts += 1
            throw disconnected
        })
        XCTAssertEqual(try gate.perform {
            attempts += 1
            return target
        }, target)
        XCTAssertEqual(attempts, 2)
        XCTAssertThrowsError(try gate.perform { throw disconnected })
    }

    func testSuccessfulWriteOutsideShortcutsResetsWarning() {
        let gate = ShortcutDriveAvailability(defaults: defaults)
        XCTAssertThrowsError(try gate.perform { throw disconnected })
        gate.didWrite()
        XCTAssertThrowsError(try gate.perform { throw disconnected })
    }

    func testMissingDriveAndWrappedProviderErrorsShareOneWarning() throws {
        let gate = ShortcutDriveAvailability(defaults: defaults)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError,
                              userInfo: [NSUnderlyingErrorKey: disconnected])
        XCTAssertThrowsError(try gate.perform { throw wrapped })
        XCTAssertNil(try gate.perform { throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENODEV)) })
        XCTAssertNil(try gate.perform { throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError) })
        XCTAssertNil(try gate.perform {
            throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.noSuchItem.rawValue)
        })
    }

    func testSetupErrorRetainsItsInstructionsAndIsNotRepeated() throws {
        let gate = ShortcutDriveAvailability(defaults: defaults)
        XCTAssertThrowsError(try gate.perform { throw DriveWriterError.noFolderSelected }) { error in
            guard case DriveWriterError.noFolderSelected = error else { return XCTFail("Lost setup instructions") }
        }
        XCTAssertNil(try gate.perform { throw DriveWriterError.noFolderSelected })
    }

    func testInvalidProgramsAndUnrelatedIOErrorsAreNeverHidden() throws {
        let gate = ShortcutDriveAvailability(defaults: defaults)
        XCTAssertThrowsError(try gate.perform { throw disconnected })
        let errors: [Error] = [DriveWriterError.missingText, DriveWriterError.textTooLarge(513),
                               DriveWriterError.tooManyLines(21), DriveWriterError.firmwareBusy,
                               NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError),
                               NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))]
        for error in errors {
            XCTAssertThrowsError(try gate.perform { throw error }) { reported in
                XCTAssertEqual((reported as NSError).domain, (error as NSError).domain)
                XCTAssertEqual((reported as NSError).code, (error as NSError).code)
            }
        }
        // Unrelated errors do not clear the outstanding connection warning.
        XCTAssertNil(try gate.perform { throw disconnected })
    }
}
