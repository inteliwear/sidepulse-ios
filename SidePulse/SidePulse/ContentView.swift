// Copyright (c) 2026 InteliWEAR LLC.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import SwiftUI
import UIKit
import UserNotifications

@MainActor
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel
    @State private var isShowingFolderPicker = false
    @State private var isShowingSettings = false
    @State private var opensSettingsAfterFolderSelection = false
    @State private var activeSheet: ActiveSheet?
    @StateObject private var library = PatternLibraryStore.shared
    @State private var playbackNotice: String?

    init() {
        _model = StateObject(wrappedValue: AppModel.shared)
    }

    init(model: AppModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SidePulseBrandHeader { isShowingSettings = true }

                    VStack(spacing: 2) {
                        SidePulseShortcutsBadge()
                            .frame(maxWidth: .infinity, minHeight: 76)

                        Link(destination: URL(string: "https://sidepulse.io/setup/dot/recipes")!) {
                            Text("Shortcuts setup recipes")
                                .font(.subheadline)
                                .underline()
                                .frame(minHeight: 44)
                        }
                    }
                    .padding(.bottom, 8)

                    Button { activeSheet = .agentControl } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "sparkles")
                                .font(.title2).foregroundStyle(PatternStyle.accent)
                                .frame(width: 42, height: 42)
                                .background(PatternStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Let your agent control it").font(.headline).foregroundStyle(.primary)
                                Text("Create a link to give your agent.").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(PatternStyle.card, in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain)

                    VStack(alignment: .trailing, spacing: 12) {
                        PatternLibraryPanel(store: library, play: playLibraryPattern)

                        Button {
                            if let off = LEDPatternCatalog.pattern(named: "off") { write(off) }
                        } label: {
                            Label("Turn off LEDs", systemImage: "power")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Stops the current pattern and turns off both lights on SidePulse Dot")
                    }
                    .padding(.bottom, 8)

                    if model.shouldShowLinkInstructions {
                        LinkSetupPanel(model: model)
                    }

                    RecentPushesPanel(pushes: latestNotificationPushes)

                    LatestReceivedLEDPanel(push: currentLEDPush) { ledText in
                        writeLEDText(ledText)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(PatternStyle.background)
            .tint(PatternStyle.accent)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView(
                    model: model,
                    requestPushToken: requestPushToken,
                    showFolderPicker: { showFolderPicker() }
                )
                .toolbar(.visible, for: .navigationBar)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .folderSetup:
                FolderSetupSheet() {
                    showFolderPicker(navigateToSettingsAfterSelection: !model.hasFolderAccess)
                }
            case .agentControl:
                AgentControlSheet(model: model)
            }
        }
        .sheet(isPresented: $isShowingFolderPicker) {
            FolderPicker { url in
                isShowingFolderPicker = false
                do {
                    try DriveWriter.shared.saveFolder(url)
                    model.refreshFolderStatus()
                    model.lastMessage = "Selected \(url.lastPathComponent)"

                    if opensSettingsAfterFolderSelection {
                        opensSettingsAfterFolderSelection = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isShowingSettings = true
                        }
                    }
                } catch {
                    opensSettingsAfterFolderSelection = false
                    model.recordError(error)
                    activeSheet = .folderSetup
                }
            } onCancel: {
                isShowingFolderPicker = false
                opensSettingsAfterFolderSelection = false
                if !model.hasFolderAccess {
                    activeSheet = .folderSetup
                }
            }
        }
        .sheet(item: $model.pendingPairing) { pairing in
            PairingSheet(model: model, pairing: pairing)
        }
        .alert(item: $model.pairingNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(item: $library.importedPattern) { pattern in
            PatternEditorView(pattern: pattern, store: library, isImport: true)
        }
        .alert("Pattern Library", isPresented: Binding(
            get: { library.error != nil }, set: { if !$0 { library.error = nil } }
        )) {
            Button("OK") { library.error = nil }
        } message: { Text(library.error ?? "") }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL, PatternShareLink.recognizes(url) {
                activeSheet = nil
                library.receiveLink(url)
            }
        }
        .onOpenURL { url in
            if PatternShareLink.recognizes(url) {
                activeSheet = nil
                library.receiveLink(url)
                return
            }
            if url.isFileURL {
                activeSheet = nil
                library.receive(url)
                return
            }
            guard url.scheme?.lowercased() == "sidepulse",
                  ["p", "pair"].contains(url.host?.lowercased() ?? "") else {
                return
            }
            model.receivePairingURL(url)
        }
        .onAppear {
            model.refreshFolderStatus()
            model.recoverQueuedPushes()
        }
        .onChange(of: model.pendingPairing) { pairing in
            if pairing != nil {
                activeSheet = nil
            }
        }
        .overlay(alignment: .bottom) {
            if let playbackNotice {
                Label(playbackNotice, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .padding().background(.regularMaterial, in: Capsule()).padding()
                    .accessibilityLabel(playbackNotice)
            }
        }
        .task(id: playbackNotice) {
            guard playbackNotice != nil else { return }
            do { try await Task.sleep(for: .seconds(3)); playbackNotice = nil } catch { }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.recoverQueuedPushes()
                library.reload()
            }
        }
    }

    private var latestNotificationPushes: [ReceivedPush] {
        Array(model.receivedPushes.filter {
            $0.hasNotificationText && !($0.notificationTitleText ?? $0.title)
                .localizedCaseInsensitiveContains("Update")
        }.prefix(5))
    }

    private var currentLEDPush: ReceivedPush? {
        model.receivedPushes.first { $0.ledText != nil }
    }

    private func requestPushToken() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, error in
            Task { @MainActor in
                if let error {
                    model.recordError(error)
                    return
                }

                UIApplication.shared.registerForRemoteNotifications()
                model.lastMessage = "Registering with APNs"
            }
        }
    }

    private func showFolderPicker(navigateToSettingsAfterSelection: Bool = false) {
        opensSettingsAfterFolderSelection = navigateToSettingsAfterSelection
        activeSheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isShowingFolderPicker = true
        }
    }

    private func playLibraryPattern(_ pattern: LibraryPattern) {
        write(LEDPattern(name: pattern.id.uuidString, displayName: pattern.name,
                         detail: pattern.summary, ledText: pattern.ledText,
                         tintHex: pattern.steps.first?.left.hex ?? "#FFFFFF"))
    }

    private func write(_ pattern: LEDPattern) {
        let pushBase = ReceivedPush(
            source: "Pattern Library",
            title: pattern.displayName,
            body: pattern.detail,
            patternName: pattern.name,
            ledText: pattern.ledText,
            payloadSummary: "{\"pattern\":\"\(pattern.name)\"}",
            writeStatus: .received
        )

        guard model.hasFolderAccess else {
            var push = pushBase
            push.writeStatus = .noFolder
            model.recordReceivedPush(push)
            activeSheet = .folderSetup
            return
        }

        do {
            let targetURL = try DriveWriter.shared.write(pattern.ledText)
            var push = pushBase
            push.body = "Wrote \(targetURL.lastPathComponent)"
            push.writeStatus = .wrote
            model.recordReceivedPush(push)
            playbackNotice = pattern.name == "off" ? "Dot turned off" : "Playing \(pattern.displayName)"
        } catch {
            var push = pushBase
            push.writeStatus = .failed
            push.errorMessage = error.localizedDescription
            model.recordReceivedPush(push)
            library.error = error.localizedDescription
        }
    }

    private func writeLEDText(_ ledText: String) {
        model.ledText = ledText

        guard model.hasFolderAccess else {
            activeSheet = .folderSetup
            return
        }

        do {
            let targetURL = try DriveWriter.shared.write(ledText)
            model.recordWriteSuccess("Wrote \(targetURL.lastPathComponent)")
        } catch {
            model.recordError(error)
        }
    }
}

private struct PairingSheet: View {
    @ObservedObject var model: AppModel
    let pairing: IOSPairingRequest

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: model.pairingSuccessMessage == nil ? "link.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(model.pairingSuccessMessage == nil ? Color.accentColor : Color.green)
                VStack(spacing: 8) {
                    Text(model.pairingSuccessMessage == nil ? "Link to \(pairing.sender)?" : "iPhone Linked")
                        .font(.title2.weight(.semibold))
                    Text(
                        model.pairingSuccessMessage
                            ?? "This shares your SidePulse push token with \(pairing.sender) through \(pairing.server.host ?? "the selected bridge")."
                    )
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                if let error = model.pairingError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                if model.pairingSuccessMessage != nil {
                    Button {
                        model.cancelPairing()
                    } label: {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        model.confirmPairing()
                    } label: {
                        HStack {
                            if model.pairingInProgress {
                                ProgressView()
                            }
                            Text(model.pairingInProgress ? "Linking…" : "Link iPhone")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.pairingInProgress)
                    Button("Cancel", role: .cancel) {
                        model.cancelPairing()
                    }
                    .disabled(model.pairingInProgress)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("SidePulse Link")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(model.pairingInProgress)
    }
}

private enum ActiveSheet: Identifiable {
    case folderSetup
    case agentControl

    var id: String {
        switch self {
        case .folderSetup:
            return "folderSetup"
        case .agentControl:
            return "agentControl"
        }
    }
}


/// Each opening issues one independently revocable key; copying never issues another.
private struct AgentControlSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var key: PushKeyRecord?
    @State private var waiting = false
    @State private var error: String?
    @State private var permissionDenied = false
    @State private var copied = false
    @State private var attempt = UUID()

    private var link: URL? {
        guard let key, model.activePushKeys.contains(where: { $0.id == key.id }) else { return nil }
        return key.agentControlURL(for: model.pushToken)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image("DotHero").resizable().scaledToFit().frame(width: 88, height: 88)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 6).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Let your agent control it").font(.largeTitle.bold()).tracking(-0.8)
                        Text("Just give this to your agent and it’ll know what to do.")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    if let link {
                        let instructions = "I have a SidePulse device. Use the instructions at this link to let me know if something needs my attention:\n\n\(link.absoluteString)"
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Message for your agent", systemImage: "text.bubble").font(.headline)
                            Text(instructions)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled).privacySensitive()
                                .accessibilityIdentifier("agentControlLink")
                            Text("The link includes a token for this iPhone.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(PatternStyle.card, in: RoundedRectangle(cornerRadius: 20))
                        Button {
                            UIPasteboard.general.string = instructions
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy instructions for your agent", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                                .foregroundStyle(PatternStyle.onAccent)
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                            .buttonBorderShape(.roundedRectangle(radius: 16))
                            .accessibilityIdentifier("copyAgentControlLink")
                        DisclosureGroup("Show token") {
                            Text(link.fragment ?? "")
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled).privacySensitive().padding(.top, 12)
                            Button("Copy token") {
                                UIPasteboard.general.string = link.fragment
                            }.padding(.top, 8)
                        }.font(.subheadline)
                        Text("You can stop access anytime by removing this AI agent key in Settings → Active Push Keys.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if let error {
                        Text(error).foregroundStyle(.secondary)
                        if permissionDenied {
                            Button("Open notification settings") {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }.buttonStyle(.bordered)
                        }
                        Button("Try again") { attempt = UUID() }.buttonStyle(.borderedProminent)
                    } else {
                        ProgressView("Creating your agent link…").frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(24)
            }
            .background(PatternStyle.background).tint(PatternStyle.accent)
            .navigationTitle("Agent control").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: attempt) { await prepareLink() }
            .onChange(of: model.registrationReadiness) { _, _ in issueKeyIfReady() }
            .onChange(of: model.pushToken) { _, _ in copied = false; issueKeyIfReady() }
        }
    }

    private func issueKeyIfReady() {
        guard waiting, key == nil, model.registrationReadiness == .ready,
              model.pushToken.range(of: "^(dev_)?[0-9a-fA-F]{64}$", options: .regularExpression) != nil else { return }
        key = model.createPushKey(name: "AI agent")
        waiting = false
    }

    private func prepareLink() async {
        error = nil
        permissionDenied = false
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard !Task.isCancelled else { return }
            guard granted else {
                permissionDenied = true
                error = "Allow notifications so your agent can send updates to SidePulse."
                return
            }
            waiting = true
            issueKeyIfReady()
            if waiting {
                UIApplication.shared.registerForRemoteNotifications()
                try await Task.sleep(for: .seconds(20))
                guard waiting else { return }
                waiting = false
                error = "Couldn’t get a push token. Check your connection and try again."
            }
        } catch is CancellationError {
            waiting = false
        } catch {
            waiting = false
            self.error = error.localizedDescription
        }
    }
}

private struct LinkSetupPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "link.circle.fill")
                        .foregroundStyle(.tint)
                    Text("Link this iPhone")
                        .foregroundStyle(.primary)
                }
                .font(.subheadline.weight(.semibold))

                Text("Send SidePulse writes from your Mac when no local device is connected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)

                instructionStep(1, "On your Mac, open Terminal and run:")

                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("sidepulse link")
                        .font(.system(.footnote, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.leading, 28)

                instructionStep(2, "Scan the QR code with your iPhone Camera to link.")

                Text("For direct HTTP push without CLI linking, use Direct Push Server in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)

                Button {
                    UIPasteboard.general.string = "sidepulse link"
                    model.lastMessage = "Copied sidepulse link command"
                } label: {
                    Label("Copy Command", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func instructionStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.14), in: Circle())
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
        }
    }
}

private struct RecentPushesPanel: View {
    let pushes: [ReceivedPush]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Latest Pushes")
                    .font(.headline)
                Spacer()
                Text("\(pushes.count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
            }

            if pushes.isEmpty {
                EmptyInboxView()
            } else {
                VStack(spacing: 8) {
                    ForEach(pushes) { push in
                        ReceivedPushRow(push: push)
                    }
                }
            }
        }
    }
}

private struct EmptyInboxView: View {
    var body: some View {
        Panel {
            HStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text("No text notifications yet")
                        .font(.subheadline.weight(.semibold))
                    Text("Notifications with a title or message will appear here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ReceivedPushRow: View {
    let push: ReceivedPush

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    if let title = push.notificationTitleText {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 8)
                    Text(push.receivedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let suffix = push.sharedKeySuffix {
                    Text("Key …\(suffix)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let body = push.notificationBodyText {
                    Text(body)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let imageURL = push.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        ZStack {
                            Color(.secondarySystemGroupedBackground)

                            switch phase {
                            case .empty:
                                ProgressView()
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}

private struct LatestReceivedLEDPanel: View {
    let push: ReceivedPush?
    let writeLED: (String) -> Void
    @State private var ledText: String

    init(push: ReceivedPush?, writeLED: @escaping (String) -> Void) {
        self.push = push
        self.writeLED = writeLED
        _ledText = State(initialValue: push?.ledText ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Current LEDS.LED")
                    .font(.headline)

                Spacer()

                if let push {
                    Text(push.receivedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Panel {
                if push == nil {
                    Label("No LEDS.LED received yet", systemImage: "lightbulb.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                } else {
                    VStack(spacing: 12) {
                        TextEditor(text: $ledText)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(minHeight: 150)
                            .scrollContentBackground(.hidden)
                            .accessibilityLabel("Latest received LEDS.LED text")

                        Button {
                            writeLED(ledText)
                        } label: {
                            Label("Write to SidePulse Dot", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(ledText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .onChange(of: push?.id) { _ in
            ledText = push?.ledText ?? ""
        }
    }
}

private struct FolderSetupSheet: View {
    let openPicker: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Select Your SidePulse Dot")
                        .font(.title2.weight(.semibold))

                    Text("SidePulse needs access to the PulseDot folder before it can write LED patterns.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Label("Locations  →  PulseDot", systemImage: "folder.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    dismiss()
                    openPicker()
                } label: {
                    Label("Choose PulseDot Folder", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .navigationTitle("Set Up SidePulse Dot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: AppModel
    let requestPushToken: () -> Void
    let showFolderPicker: () -> Void
    @State private var keyToRemove: PushKeyRecord?
    @State private var isConfirmingKeyRemoval = false

    var body: some View {
        Form {
            Section("Link to Your Mac") {
                Label(
                    model.isBridgeLinked ? "Linked" : "Not linked",
                    systemImage: model.isBridgeLinked ? "checkmark.circle.fill" : "link.circle"
                )
                .foregroundStyle(model.isBridgeLinked ? .green : .secondary)

                Text("1. Open Terminal on your Mac and run:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("sidepulse link")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)

                Button {
                    UIPasteboard.general.string = "sidepulse link"
                    model.lastMessage = "Copied sidepulse link command"
                } label: {
                    Label("Copy Command", systemImage: "doc.on.doc")
                }

                Text("2. Scan the QR code with your iPhone Camera to link.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("If scanning is unavailable, copy the push token below and paste it into the waiting Terminal command.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Push Token") {
                Button {
                    requestPushToken()
                } label: {
                    Label("Get Push Token", systemImage: "key.horizontal")
                }

                if model.pushToken.isEmpty {
                    Text("No token yet")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Push token available", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                    Button {
                        let key = model.createPushKey()
                        UIPasteboard.general.string = key.token(for: model.pushToken)
                        model.lastMessage = "Copied token for key \(key.maskedKey)"
                    } label: {
                        Label("Copy New Token", systemImage: "doc.on.doc")
                    }
                }
            }

            Section {
                if model.activePushKeys.isEmpty {
                    Text("No active keys")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.activePushKeys) { key in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(key.maskedKey, systemImage: "key.horizontal")
                                .font(.system(.headline, design: .monospaced))
                            Spacer()
                            Text(key.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Last active") {
                            if let date = key.lastActiveAt {
                                Text(date, style: .relative)
                            } else {
                                Text("Never")
                            }
                        }
                        LabeledContent("Total received", value: key.totalReceived.formatted())
                        HStack {
                            Button {
                                UIPasteboard.general.string = key.token(for: model.pushToken)
                                model.lastMessage = "Copied token for key \(key.maskedKey)"
                            } label: {
                                Label("Copy Token", systemImage: "doc.on.doc")
                                    .frame(minHeight: 44)
                            }
                            .disabled(model.pushToken.isEmpty)
                            Spacer()
                            Button(role: .destructive) {
                                keyToRemove = key
                                isConfirmingKeyRemoval = true
                            } label: {
                                Label("Remove", systemImage: "trash")
                                    .frame(minHeight: 44)
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 6)
                }
            } header: {
                Text("Active Push Keys")
            } footer: {
                Text("Unused tokens expire after 24 hours. Tokens used at least once stay until you remove them. Each sender has its own key; removing it stops that sender’s updates.")
            }

            Section("Bridge") {
                LabeledContent("Server", value: model.bridgeBaseURL)
                LabeledContent("Recovery", value: model.lastRecoveryStatus)
                Button {
                    model.recoverQueuedPushes()
                } label: {
                    Label("Check for Missed Pushes", systemImage: "arrow.clockwise")
                }
            }

            Section("SidePulse Dot") {
                LabeledContent("Folder", value: model.selectedFolderPath)

                Button {
                    showFolderPicker()
                } label: {
                    Label(model.hasFolderAccess ? "Change LED Folder" : "Set Up LED Folder", systemImage: "folder.badge.plus")
                }
            }

            Section("Shortcuts") {
                ShortcutsLink()

                Text("Create, edit, preview, and share patterns in Pattern Library. Choose two LED colors and timing for each step, then play once, repeat, or loop continuously. Saved patterns are also available in the Play Pattern shortcut action.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Direct Push Server") {
                Text("Use the original raw server for push-only delivery without linking the SidePulse CLI.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("1. Copy a new token above.\n2. Configure the raw server with that token, including its key suffix.\n3. Send JSON to the endpoint below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField("Push server base URL", text: $model.serverBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                SecureField("Shared secret", text: $model.sharedSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if let endpoint = model.pushEndpointURL {
                    Text("Push endpoint")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(endpoint)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }

                if let curlExample = model.curlExample {
                    Text("Example request")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(curlExample)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    Button {
                        UIPasteboard.general.string = curlExample
                        model.lastMessage = "Copied curl example"
                    } label: {
                        Label("Copy Curl", systemImage: "terminal")
                    }
                }
            }

            Section("Raw LED Editor") {
                TextEditor(text: $model.ledText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)

                Button {
                    writeLocalTest()
                } label: {
                    Label("Write to USB", systemImage: "square.and.arrow.down")
                }
            }

            Section("Diagnostics") {
                Button {
                    model.refreshEventLog()
                } label: {
                    Label("Refresh Log", systemImage: "arrow.clockwise")
                }

                Button(role: .destructive) {
                    model.clearEventLog()
                } label: {
                    Label("Clear Log", systemImage: "trash")
                }

                if model.eventLog.isEmpty {
                    Text("No events")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.eventLog.reversed(), id: \.self) { line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Inbox") {
                Button(role: .destructive) {
                    model.clearReceivedPushes()
                } label: {
                    Label("Clear Received Pushes", systemImage: "tray.and.arrow.down")
                }
            }
        }
        .alert("Remove key?", isPresented: $isConfirmingKeyRemoval, presenting: keyToRemove) { key in
            Button("Remove", role: .destructive) {
                model.removePushKey(key.id)
                keyToRemove = nil
            }
            Button("Cancel", role: .cancel) { keyToRemove = nil }
        } message: { key in
            Text("Pushes from key \(key.maskedKey) will be ignored. This sender will need a new token to reconnect.")
        }
        .navigationTitle("Settings")
    }

    private func writeLocalTest() {
        do {
            let targetURL = try DriveWriter.shared.write(model.ledText)
            model.recordWriteSuccess("Wrote \(targetURL.lastPathComponent)")
        } catch {
            model.recordError(error)
        }
    }
}

private struct Panel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension ReceivedPush.WriteStatus {
    var symbolName: String {
        switch self {
        case .received:
            return "tray.fill"
        case .wrote:
            return "checkmark.circle.fill"
        case .noFolder:
            return "folder.badge.questionmark"
        case .failed:
            return "xmark.octagon.fill"
        case .unsupportedPattern:
            return "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .received:
            return .blue
        case .wrote:
            return .green
        case .noFolder:
            return .orange
        case .failed:
            return .red
        case .unsupportedPattern:
            return .purple
        }
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64

        switch cleaned.count {
        case 6:
            red = (value >> 16) & 0xff
            green = (value >> 8) & 0xff
            blue = value & 0xff
        default:
            red = 0x3b
            green = 0x82
            blue = 0xf6
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: 1
        )
    }
}

/// Preserve Apple's app-specific navigation beneath the custom badge label.
private struct SidePulseShortcutsBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ShortcutsLink()
            .shortcutsLinkStyle(colorScheme == .dark ? .darkOutline : .lightOutline)
            .frame(width: 276, height: 68)
            .overlay {
                HStack(spacing: 14) {
                    Image("ShortcutsBadgeIcon")
                        .resizable()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("SidePulse in Shortcuts")
                        .font(.system(size: 18, weight: .semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(colorScheme == .dark ? Color.black : .white, in: RoundedRectangle(cornerRadius: 17))
                .overlay {
                    RoundedRectangle(cornerRadius: 17)
                        .strokeBorder(Color.primary.opacity(0.28), lineWidth: 1)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .accessibilityLabel("SidePulse in Shortcuts")
    }
}
