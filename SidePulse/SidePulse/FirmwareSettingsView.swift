// Copyright (c) 2026 InteliWEAR LLC.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. https://mozilla.org/MPL/2.0/.

import SwiftUI

struct FirmwareSettingsSection: View {
    @ObservedObject var firmware: FirmwareUpdateModel
    let isConnected: Bool

    var body: some View {
        Section {
            Toggle("Automatically Check Firmware", isOn: $firmware.automaticChecks)

            if let device = firmware.device {
                LabeledContent("Model", value: device.product.name)
                LabeledContent("Installed", value: device.versionText)
            }
            if let release = firmware.release {
                LabeledContent("Latest Available", value: release.version.description)
            }
            if let checked = firmware.lastChecked {
                LabeledContent("Last Release Check") {
                    Text(checked, style: .relative)
                }
            }

            Text(firmware.message)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let error = firmware.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Firmware error: \(error)")
            }

            if firmware.isChecking || firmware.isInstalling {
                ProgressView(firmware.isInstalling ? "Updating Firmware…" : "Checking Firmware…")
            }

            Button {
                Task { await firmware.refresh(forceReleaseCheck: true) }
            } label: {
                Label("Check Firmware", systemImage: "arrow.clockwise")
            }
            .disabled(!isConnected || firmware.isChecking || firmware.isInstalling)

            if firmware.updateAvailable, let release = firmware.release {
                Button {
                    let device = firmware.device
                    Task { await firmware.install(expectedDevice: device) }
                } label: {
                    Label("Update to \(release.version.description)", systemImage: "arrow.down.circle")
                }
                .disabled(!isConnected || !firmware.canInstall)
            }

            Link("Firmware Release Notes", destination: URL(string: "https://github.com/inteliwear/sidepulse/blob/main/firmware/README.md")!)
        } header: {
            Text("Firmware")
        } footer: {
            Text("When enabled, firmware is checked when you open SidePulse, at most once every 24 hours. You can check manually anytime. Tap Update to install new firmware. Keep your device connected while it updates.")
        }
    }
}
