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
                    HStack {
                        Spacer()
                        ShortcutsLink()
                            .shortcutsLinkStyle(.automaticOutline)
                    }

                    if !model.isBridgeLinked {
                        LinkSetupPanel(model: model)
                    }

                    RecentPushesPanel(pushes: latestNotificationPushes)

                    QuickPatternsPanel { pattern in
                        write(pattern)
                    }

                    LatestReceivedLEDPanel(push: currentLEDPush) { ledText in
                        writeLEDText(ledText)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("SidePulse")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView(
                    model: model,
                    requestPushToken: requestPushToken,
                    showFolderPicker: { showFolderPicker() }
                )
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .folderSetup:
                FolderSetupSheet(requiresSelection: !model.hasFolderAccess) {
                    showFolderPicker(navigateToSettingsAfterSelection: !model.hasFolderAccess)
                }
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
        .onAppear {
            model.refreshFolderStatus()
            model.recoverQueuedPushes()
            if !model.hasFolderAccess {
                activeSheet = .folderSetup
            }
        }
        .onChange(of: model.pendingPairing) { pairing in
            if pairing != nil {
                activeSheet = nil
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.recoverQueuedPushes()
            }
        }
    }

    private var latestNotificationPushes: [ReceivedPush] {
        Array(model.receivedPushes.filter(\.hasNotificationText).prefix(5))
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

    private func write(_ pattern: LEDPattern) {
        let pushBase = ReceivedPush(
            source: "Quick Pattern",
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
        } catch {
            var push = pushBase
            push.writeStatus = .failed
            push.errorMessage = error.localizedDescription
            model.recordReceivedPush(push)
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
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(.tint)
                VStack(spacing: 8) {
                    Text("Link to \(pairing.sender)?")
                        .font(.title2.weight(.semibold))
                    Text("This shares your SidePulse push token with \(pairing.sender) through \(pairing.server.host ?? "the selected bridge").")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                if let error = model.pairingError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
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

    var id: String {
        switch self {
        case .folderSetup:
            return "folderSetup"
        }
    }
}

private struct LinkSetupPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Link this iPhone", systemImage: "link.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.tint)

                Text("Send SidePulse writes from your Mac when no local device is connected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("1. On your Mac, open Terminal and run:")
                    .font(.subheadline)

                Text("sidepulse link")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)

                Text("2. Scan the QR code with your iPhone Camera.")
                    .font(.subheadline)
                Text("3. Return here and tap Link iPhone.")
                    .font(.subheadline)

                Button {
                    UIPasteboard.general.string = "sidepulse link"
                    model.lastMessage = "Copied sidepulse link command"
                } label: {
                    Label("Copy Command", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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

private struct QuickPatternsPanel: View {
    let writePattern: (LEDPattern) -> Void
    @State private var pulseCount = SidePulseLEDProgram.defaultPulseCount
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Patterns")
                .font(.headline)

            Button {
                if let offPattern = LEDPatternCatalog.pattern(named: "off") {
                    writePattern(offPattern)
                }
            } label: {
                Panel {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(.tertiarySystemFill))
                            Image(systemName: "power")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Off")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Turn off SidePulse Dot")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            ForEach(QuickPatternEffect.allCases) { effect in
                VStack(alignment: .leading, spacing: 8) {
                    Text(effect.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if effect == .pulse {
                        Panel {
                            Stepper(value: $pulseCount, in: SidePulseLEDProgram.pulseRange) {
                                HStack {
                                    Text("Number of pulses")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(pulseCount)")
                                        .font(.body.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(SidePulseLEDColor.allCases, id: \.self) { color in
                            let pattern = effect.pattern(color: color, count: pulseCount)
                            Button {
                                writePattern(pattern)
                            } label: {
                                PatternButtonLabel(pattern: pattern)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

private enum QuickPatternEffect: String, CaseIterable, Identifiable {
    case pulse
    case breathe

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pulse: "Pulse"
        case .breathe: "Breathe"
        }
    }

    func pattern(color: SidePulseLEDColor, count: Int) -> LEDPattern {
        let boundedCount = SidePulseLEDProgram.bounded(count)
        let ledText: String
        let detail: String

        switch self {
        case .pulse:
            ledText = SidePulseLEDProgram.pulse(color: color, count: boundedCount)
            detail = "\(boundedCount) \(boundedCount == 1 ? "pulse" : "pulses")"
        case .breathe:
            ledText = SidePulseLEDProgram.breathe(color: color)
            detail = "Repeats until changed"
        }

        return LEDPattern(
            name: self == .pulse
                ? "\(rawValue)_\(color.rawValue)_\(boundedCount)"
                : "\(rawValue)_\(color.rawValue)",
            displayName: "\(displayName) \(color.displayName)",
            detail: detail,
            ledText: ledText,
            tintHex: color.hex
        )
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

private struct PatternButtonLabel: View {
    let pattern: LEDPattern

    var body: some View {
        Panel {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: pattern.tintHex))
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 3) {
                    Text(pattern.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(pattern.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
    }
}

private struct FolderSetupSheet: View {
    let requiresSelection: Bool
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
                if !requiresSelection {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(requiresSelection)
    }
}

private struct SettingsView: View {
    @ObservedObject var model: AppModel
    let requestPushToken: () -> Void
    let showFolderPicker: () -> Void

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

                Text("2. Scan the QR code using your iPhone Camera.\n3. Confirm by tapping Link iPhone when SidePulse opens.")
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
                        UIPasteboard.general.string = model.pushToken
                        model.lastMessage = "Copied push token"
                    } label: {
                        Label("Copy Token", systemImage: "doc.on.doc")
                    }
                }
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

                Text("Choose any of six colors. Pulse supports 1–10 repetitions; Breathe repeats continuously until you select another pattern.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Advanced Server") {
                TextField("Proxy base URL", text: $model.serverBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                SecureField("Shared secret", text: $model.sharedSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if let endpoint = model.pushEndpointURL {
                    Text(endpoint)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }

                if let curlExample = model.curlExample {
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

                if let shortcutURL = model.shortcutWriteURL {
                    Button {
                        UIPasteboard.general.string = shortcutURL
                        model.lastMessage = "Copied Shortcut URL"
                    } label: {
                        Label("Copy Shortcut URL", systemImage: "link.badge.plus")
                    }
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
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
