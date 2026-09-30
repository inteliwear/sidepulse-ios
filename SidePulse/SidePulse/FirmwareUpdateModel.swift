// Copyright (c) 2026 InteliWEAR LLC.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. https://mozilla.org/MPL/2.0/.

import Foundation
import Combine

@MainActor
final class FirmwareUpdateModel: ObservableObject {
    static let shared = FirmwareUpdateModel()

    @Published var automaticChecks: Bool {
        didSet {
            defaults.set(automaticChecks, forKey: "firmwareAutomaticChecks")
            if automaticChecks { checkOnAppOpen(isConnected: isConnected) }
            else { automaticTask?.cancel() }
        }
    }
    @Published private(set) var device: FirmwareDevice?
    @Published private(set) var release: FirmwareRelease?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published private(set) var message = "Check firmware with your device connected."
    @Published private(set) var error: String?
    @Published private(set) var pending: PendingInstall?

    struct PendingInstall: Codable {
        let device: FirmwareDevice
        let version: FirmwareVersion
        let transferredAt: Date
        let bookmark: Data

        func confirms(_ device: FirmwareDevice, bookmark: Data, now: Date) -> Bool {
            now.timeIntervalSince(transferredAt) >= 10 && self.bookmark == bookmark
                && self.device.product == device.product && self.device.serial == device.serial
                && device.version == version
        }
    }

    private struct CachedRelease: Codable {
        let release: FirmwareRelease
        let checkedAt: Date
    }

    private let defaults: UserDefaults
    private let service: FirmwareService
    private let now: () -> Date
    private let readStatus: () async throws -> DriveWriter.FirmwareSnapshot
    private let writeFirmware: (FirmwarePackage, DriveWriter.FirmwareSnapshot) async throws -> Void
    private var snapshot: DriveWriter.FirmwareSnapshot?
    private var cachedReleases: [String: CachedRelease]
    private var automaticTask: Task<Void, Never>?
    private var lastCheckAttempt: Date?
    private var isConnected = false

    var updateAvailable: Bool {
        guard let device, let release else { return false }
        return release.isNewer(than: device)
    }

    var canInstall: Bool {
        updateAvailable && !isChecking && !isInstalling
            && (pending.map { Date().timeIntervalSince($0.transferredAt) >= 10 } ?? true)
    }

    init(defaults: UserDefaults = .standard, service: FirmwareService = FirmwareService(),
         now: @escaping () -> Date = Date.init,
         readStatus: @escaping () async throws -> DriveWriter.FirmwareSnapshot = {
             try await Task.detached { try DriveWriter.shared.readFirmwareStatus() }.value
         },
         writeFirmware: @escaping (FirmwarePackage, DriveWriter.FirmwareSnapshot) async throws -> Void = { package, expected in
             try await Task.detached { try DriveWriter.shared.writeFirmware(package, expected: expected) }.value
         }) {
        self.defaults = defaults
        self.service = service
        self.now = now
        self.readStatus = readStatus
        self.writeFirmware = writeFirmware
        automaticChecks = defaults.bool(forKey: "firmwareAutomaticChecks")
        cachedReleases = defaults.data(forKey: "firmwareReleaseCache")
            .flatMap { try? JSONDecoder().decode([String: CachedRelease].self, from: $0) } ?? [:]
        lastCheckAttempt = defaults.object(forKey: "firmwareLastCheckAttempt") as? Date
            ?? cachedReleases.values.map(\.checkedAt).max()
        pending = defaults.data(forKey: "firmwarePendingInstall")
            .flatMap { try? JSONDecoder().decode(PendingInstall.self, from: $0) }
        if let pending { message = Self.transferMessage(pending.version) }
    }

    /// Called on launch or foreground entry. Persist the daily limit across launches,
    /// including failed attempts; manual checks remain available at any time.
    @discardableResult
    func checkOnAppOpen(isConnected: Bool) -> Task<Void, Never>? {
        connectionChanged(isConnected: isConnected)
        guard isConnected, automaticCheckDue || pending != nil, automaticTask == nil,
              !isChecking, !isInstalling else { return nil }
        automaticTask = Task {
            await refresh(automatic: true)
            automaticTask = nil
        }
        return automaticTask
    }

    private var automaticCheckDue: Bool {
        automaticChecks && (lastCheckAttempt.map { now().timeIntervalSince($0) >= 86_400 } ?? true)
    }

    /// The existing connection indicator may poll, but it never reads firmware status.
    func connectionChanged(isConnected: Bool) {
        self.isConnected = isConnected
        if !isConnected {
            snapshot = nil
            device = nil
            release = nil
            lastChecked = nil
            error = nil
            message = pending.map { Self.transferMessage($0.version) }
                ?? "Connect your SidePulse device to check firmware."
            automaticTask?.cancel()
        }
    }

    func cancelAutomaticCheck() { automaticTask?.cancel() }

    func folderChanged(isConnected: Bool) {
        automaticTask?.cancel()
        snapshot = nil
        device = nil
        release = nil
        error = nil
        checkOnAppOpen(isConnected: isConnected)
    }

    func refresh(forceReleaseCheck: Bool = false, automatic: Bool = false) async {
        guard !isChecking, !isInstalling else { return }
        let mayFetch = !automatic || automaticCheckDue
        guard !automatic || mayFetch || pending != nil else { return }
        if mayFetch {
            lastCheckAttempt = now()
            defaults.set(lastCheckAttempt, forKey: "firmwareLastCheckAttempt")
        }
        isChecking = true
        defer { isChecking = false }
        var readSucceeded = false
        var confirmedVersion: FirmwareVersion?
        do {
            let current = try await readStatus()
            try Task.checkCancellation()
            readSucceeded = true
            if !automatic || device != current.device { error = nil }
            snapshot = current
            isConnected = true
            device = current.device
            if let pending, pending.confirms(current.device, bookmark: current.bookmark, now: now()) {
                self.pending = nil
                error = nil
                confirmedVersion = pending.version
                defaults.removeObject(forKey: "firmwarePendingInstall")
                message = "Firmware \(pending.version) installed. Confirmed in STATUS.TXT."
                EventLog.append(message)
            }
            // Opting out still allows local confirmation of a requested installation.
            let cache = cachedReleases[current.device.product.rawValue]
            let due = cache.map { now().timeIntervalSince($0.checkedAt) >= 86_400 } ?? true
            release = cache?.release
            lastChecked = cache?.checkedAt
            if mayFetch && (forceReleaseCheck || due) {
                let latest = try await service.latestRelease(for: current.device.product)
                try Task.checkCancellation()
                // Ignore a response if the folder was changed while fetching release data.
                let fresh = try await readStatus()
                try Task.checkCancellation()
                guard fresh == current else {
                    snapshot = nil
                    device = nil
                    release = nil
                    throw FirmwareError.deviceChanged
                }
                let checkedAt = now()
                cachedReleases[current.device.product.rawValue] = CachedRelease(release: latest, checkedAt: checkedAt)
                if let data = try? JSONEncoder().encode(cachedReleases) {
                    defaults.set(data, forKey: "firmwareReleaseCache")
                }
                release = latest
                lastChecked = checkedAt
                error = nil
            }
            if let pending, pending.bookmark == current.bookmark,
               pending.device.product == current.device.product, pending.device.serial == current.device.serial {
                message = Self.transferMessage(pending.version)
            } else if let confirmedVersion {
                message = "Firmware \(confirmedVersion) installed. Confirmed in STATUS.TXT."
            } else if updateAvailable, let release {
                message = "Firmware \(release.version) is available."
            } else if release != nil {
                message = "Your firmware is up to date."
            } else {
                message = "Installed firmware read from STATUS.TXT."
            }
        } catch is CancellationError {
            // Backgrounding or opting out cancels automatic network checks quietly.
        } catch {
            guard !Task.isCancelled else { return }
            if !readSucceeded {
                snapshot = nil
                device = nil
                release = nil
                lastChecked = nil
            }
            self.error = error.localizedDescription
            if !automatic { EventLog.append("Firmware check: \(error.localizedDescription)") }
        }
    }

    func install(expectedDevice: FirmwareDevice? = nil) async {
        if let expectedDevice, expectedDevice != device {
            error = FirmwareError.deviceChanged.localizedDescription
            return
        }
        guard canInstall, let release, let expected = snapshot else { return }
        isInstalling = true
        error = nil
        message = "Downloading and verifying firmware \(release.version)…"
        defer { isInstalling = false }
        var transferStarted = false
        do {
            let package = try await service.package(for: release)
            try Task.checkCancellation()
            message = "Sending firmware. Keep your device connected…"
            transferStarted = true
            try await writeFirmware(package, expected)
            pending = PendingInstall(device: expected.device, version: release.version,
                                     transferredAt: Date(), bookmark: expected.bookmark)
            if let data = try? JSONEncoder().encode(pending) { defaults.set(data, forKey: "firmwarePendingInstall") }
            message = Self.transferMessage(release.version)
        } catch {
            self.error = error.localizedDescription + (transferStarted
                ? " Keep the device connected for at least 10 seconds before retrying."
                : "")
            message = "Firmware update did not finish."
            EventLog.append("Firmware update: \(error.localizedDescription)")
        }
    }

    private static func transferMessage(_ version: FirmwareVersion) -> String {
        "Firmware \(version) transferred. Keep your device connected for at least 10 seconds while it finishes updating."
    }
}
