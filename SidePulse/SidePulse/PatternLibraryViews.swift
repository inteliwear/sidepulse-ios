// Copyright (c) 2026 InteliWEAR LLC. MPL-2.0.
import AppIntents
import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable
import WebKit

extension UTType {
    static let sidePulseLED = UTType(exportedAs: "io.sidepulse.led", conformingTo: .plainText)
    static let sidePulsePattern = UTType(exportedAs: "io.sidepulse.pattern", conformingTo: .json)
}

extension LibraryPattern: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .sidePulseLED) { pattern in
            try PatternShareFile.encode(pattern)
        }
        .suggestedFileName { pattern in
            let safeName = pattern.name.components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters))
                .joined().trimmingCharacters(in: .whitespaces)
            return "\(safeName.isEmpty ? "SidePulse Pattern" : safeName).led"
        }
    }
}

@MainActor
final class PatternLibraryStore: ObservableObject {
    static let shared = PatternLibraryStore()
    @Published private(set) var patterns: [LibraryPattern] = []
    @Published var error: String?
    @Published var importedPattern: LibraryPattern?
    private var canSave = false
    private let repository = PatternLibraryRepository.standard

    init() { reload() }
    func reload() {
        do {
            patterns = try repository.load()
            canSave = true
        } catch {
            canSave = false
            self.error = "Couldn’t read your saved library. Your file has been kept unchanged. \(error.localizedDescription)"
        }
    }
    func save(_ pattern: LibraryPattern) throws {
        guard canSave else { throw PatternLibraryError.invalid("The saved library couldn’t be loaded. Please reopen the app before saving.") }
        let valid = try pattern.validated()
        var updated = patterns
        if let index = updated.firstIndex(where: { $0.id == valid.id }) { updated[index] = valid }
        else { updated.insert(valid, at: 0) }
        try repository.save(updated)
        patterns = updated
        SidePulseShortcuts.updateAppShortcutParameters()
    }
    func delete(_ pattern: LibraryPattern) {
        do {
            guard canSave else { throw PatternLibraryError.invalid("The library couldn’t be loaded.") }
            let updated = patterns.filter { $0.id != pattern.id }
            try repository.save(updated)
            patterns = updated
            SidePulseShortcuts.updateAppShortcutParameters()
        } catch { self.error = error.localizedDescription }
    }
    func receiveLink(_ url: URL) {
        do { importedPattern = try PatternShareLink.decode(url) }
        catch { self.error = error.localizedDescription }
    }
    func receive(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do { importedPattern = try PatternShareFile.read(url) }
        catch { self.error = error.localizedDescription }
    }
}

struct SidePulseBrandHeader: View {
    let showSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image("DotHero")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 4)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                Text("Side").foregroundStyle(.primary)
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                    let phase = reduceMotion ? 0.18 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12) / 12
                    // Match sidepulse.io’s accent spectrum and wide color bands, at half its speed.
                    // Two identical spectra make the twelve-second drift seamless.
                    let palette = ["FF944D", "F675AB", "B48AFF", "62A7FF", "64D2CF", "B6D76D", "FF944D"]
                        .map { PatternRGB($0).color }
                    let stops = (0...14).map { Gradient.Stop(color: palette[$0 % palette.count], location: Double($0) / 14) }
                    Text("Pulse")
                        .foregroundStyle(.clear)
                        .overlay {
                            GeometryReader { geometry in
                                LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
                                    .frame(width: geometry.size.width * 4)
                                    .offset(x: -geometry.size.width * 2 * phase)
                            }
                            .mask(Text("Pulse").foregroundStyle(.white))
                        }
                }
            }
            .font(.system(size: 37, weight: .bold, design: .rounded))
            .tracking(-1.2)
            .minimumScaleFactor(0.65)
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("SidePulse")
            .frame(maxWidth: .infinity)
            Button(action: showSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

struct PatternLibraryPanel: View {
    @ObservedObject var store: PatternLibraryStore
    let play: (LibraryPattern) -> Void
    @State private var newPattern: LibraryPattern?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("Pattern Library").font(.title3.weight(.bold))
                Spacer()
                Button { newPattern = LibraryPattern() } label: {
                    Label("New", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Color.accentColor.opacity(0.09), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Create a pattern")
            }
            VStack(spacing: 0) {
                ForEach(Array(store.patterns.prefix(4))) { pattern in
                    NavigationLink {
                        PatternDetailView(patternID: pattern.id, store: store, play: play)
                    } label: { PatternLibraryRow(pattern: pattern) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Plays this pattern on the connected SidePulse Dot and opens its preview")
                    Divider().padding(.leading, 80)
                }
                if store.patterns.isEmpty {
                    Text("Create a pattern or import one from a friend.")
                        .font(.subheadline).foregroundStyle(.secondary).padding(24)
                }
                NavigationLink {
                    PatternLibraryView(store: store, play: play)
                } label: {
                    HStack {
                        Text("Browse library").font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(store.patterns.count) patterns").font(.caption).foregroundStyle(Color.secondary)
                        Image(systemName: "arrow.right").font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 18).frame(minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }
            .background(PatternStyle.card, in: RoundedRectangle(cornerRadius: 20))
        }
        .sheet(item: $newPattern) { PatternEditorView(pattern: $0, store: store) }
    }
}

struct PatternLibraryView: View {
    @ObservedObject var store: PatternLibraryStore
    let play: (LibraryPattern) -> Void
    @State private var search = ""
    @State private var newPattern: LibraryPattern?
    @State private var importing = false
    @State private var deleting: LibraryPattern?
    @State private var showClassics = false

    private var matches: [LibraryPattern] {
        store.patterns.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        List {
            if matches.isEmpty {
                ContentUnavailableView(search.isEmpty ? "Your library starts here" : "No matching patterns",
                                       systemImage: "sparkles", description: Text("Create a pattern or import one shared with you."))
            }
            ForEach(matches.filter { !$0.isClassicStarter }) { pattern in
                libraryRow(pattern)
            }
            let classics = matches.filter(\.isClassicStarter)
            if !classics.isEmpty {
                if search.isEmpty {
                    DisclosureGroup("Classic colors", isExpanded: $showClassics) {
                        ForEach(classics) { libraryRow($0) }
                    }
                } else {
                    ForEach(classics) { libraryRow($0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PatternStyle.background)
        .tint(PatternStyle.accent)
        .navigationTitle("Pattern Library")
        .toolbar(.visible, for: .navigationBar)
        .searchable(text: $search, prompt: "Find a pattern")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Create pattern", systemImage: "plus") { newPattern = LibraryPattern() }
                    Button("Import pattern", systemImage: "square.and.arrow.down") { importing = true }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add pattern")
            }
        }
        .sheet(item: $newPattern) { PatternEditorView(pattern: $0, store: store) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.sidePulseLED, .sidePulsePattern, .json]) { result in
            switch result {
            case .success(let url): store.receive(url)
            case .failure(let error): store.error = error.localizedDescription
            }
        }
        .confirmationDialog("Delete \(deleting?.name ?? "pattern")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Delete pattern", role: .destructive) {
                if let deleting { store.delete(deleting) }
                deleting = nil
            }
        } message: { Text("Shortcuts using this pattern will need another selection.") }
    }
    private func libraryRow(_ pattern: LibraryPattern) -> some View {
        NavigationLink {
            PatternDetailView(patternID: pattern.id, store: store, play: play)
        } label: { PatternLibraryRow(pattern: pattern, chevron: false) }
        .accessibilityHint("Plays this pattern on the connected SidePulse Dot and opens its preview")
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12))
        .swipeActions {
            Button("Delete", role: .destructive) { deleting = pattern }
            Button("Edit") { newPattern = pattern }.tint(.blue)
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { newPattern = pattern }
            PatternSharingActions(pattern: pattern)
            Button("Duplicate", systemImage: "plus.square.on.square") {
                var copy = pattern
                copy.id = UUID()
                copy.name = String((copy.name + " copy").prefix(60))
                newPattern = copy
            }
        }
    }

}

struct PatternLibraryRow: View {
    let pattern: LibraryPattern
    var chevron = true
    var body: some View {
        HStack(spacing: 12) {
            PatternThumbnail(pattern: pattern).frame(width: 50, height: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(pattern.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(pattern.summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if chevron { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct PatternThumbnail: View {
    let pattern: LibraryPattern
    var body: some View {
        if let data = PatternThumbnailRenderer.data(for: pattern), let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit().accessibilityHidden(true)
        } else {
            Image(systemName: "doc.text").foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }
}

struct PatternSharingActions: View {
    let pattern: LibraryPattern
    var body: some View {
        if let url = try? PatternShareLink.encode(pattern) {
            ShareLink(item: url, preview: SharePreview(pattern.name, image: Image("DotHero"))) {
                Label("Share preview link", systemImage: "link").frame(maxWidth: .infinity)
            }
        }
        ShareLink(item: pattern, preview: SharePreview(pattern.name, image: Image("DotHero"))) {
            Label("Share .led file", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
        }
    }
}

struct PatternDetailView: View {
    let patternID: UUID
    @ObservedObject var store: PatternLibraryStore
    let play: (LibraryPattern) -> Void
    @State private var editing: LibraryPattern?
    @State private var textEditing: LibraryPattern?
    @State private var hasStartedPlayback = false
    private var pattern: LibraryPattern? { store.patterns.first { $0.id == patternID } }

    var body: some View {
        ScrollView {
            if let pattern {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PATTERN LIBRARY").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
                        Text(pattern.name).font(.largeTitle.weight(.bold)).tracking(-1)
                        Text("Preview it here. Make it yours.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    PatternPreview(pattern: pattern)
                    HStack(spacing: 14) {
                        Button { textEditing = pattern } label: {
                            Label("Edit .led text", systemImage: "chevron.left.forwardslash.chevron.right")
                                .frame(maxWidth: .infinity)
                        }
                        if pattern.canEditVisually {
                            Button { editing = pattern } label: {
                                Label("Edit steps", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                            }
                        }
                    }.buttonStyle(.bordered).controlSize(.large).font(.subheadline.weight(.semibold))
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Share a little light").font(.headline)
                            Spacer()
                            Image(systemName: "sparkles").foregroundStyle(PatternStyle.accent)
                        }
                        Text("Send a preview link or the original .led file. They can open it, remix it, and make it theirs.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        PatternSharingActions(pattern: pattern).buttonStyle(.bordered).controlSize(.large)
                    }
                    .padding(20).background(PatternStyle.card, in: RoundedRectangle(cornerRadius: 20))
                    DisclosureGroup("LED source") {
                        Text(pattern.ledText).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                    }.font(.subheadline).padding(20)
                        .background(PatternStyle.card, in: RoundedRectangle(cornerRadius: 20))
                }.padding(20)
            } else {
                ContentUnavailableView("Pattern removed", systemImage: "sparkles")
            }
        }
        .background(PatternStyle.background)
        .tint(PatternStyle.accent)
        .navigationTitle("SidePulse")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit .led text", systemImage: "chevron.left.forwardslash.chevron.right") { textEditing = pattern }
                    if pattern?.canEditVisually == true {
                        Button("Edit steps", systemImage: "slider.horizontal.3") { editing = pattern }
                    }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("Pattern actions").disabled(pattern == nil)
            }
        }
        .sheet(item: $editing) { PatternEditorView(pattern: $0, store: store) }
        .sheet(item: $textEditing) { PatternTextEditorView(pattern: $0, store: store) }
        .onAppear {
            guard !hasStartedPlayback, let pattern else { return }
            hasStartedPlayback = true
            play(pattern)
        }
    }
}

/// Read-only source presentation for inspection and copying.
struct PatternSourceView: View {
    let pattern: LibraryPattern
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("LED source", systemImage: "doc.text").font(.headline)
            Text("Your exact .led text. Open the text editor to change any command; the visual step editor supports a smaller set of patterns.")
                .font(.subheadline).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                Text(pattern.ledText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(PatternStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }
}

/// The same offline WASM engine and CAD renders used by the shared web preview.
struct PatternPreview: View {
    let pattern: LibraryPattern
    @State private var restart = 0
    @State private var autoRestart = true
    @State private var device = 2
    @State private var status = "Loading preview…"
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            PatternDeviceWebView(source: pattern.ledText, count: device, restart: restart,
                                 autoRestart: autoRestart, active: scenePhase == .active, status: $status)
                .frame(height: 260)
                .accessibilityLabel("Live \(device == 2 ? "SidePulse Dot" : "SidePulse Pro") preview")
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { restart += 1 } label: {
                        Label("Restart", systemImage: "arrow.counterclockwise")
                            .font(.subheadline.weight(.semibold)).padding(.horizontal, 15).frame(height: 44)
                            .foregroundStyle(PatternStyle.background)
                            .background(Color.primary, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                    Spacer()
                    Picker("Device", selection: $device) {
                        Text("SidePulse Dot").tag(2)
                        Text("SidePulse Pro").tag(8)
                    }.pickerStyle(.menu).font(.subheadline)
                }
                Toggle(isOn: $autoRestart) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Loop preview").font(.subheadline)
                        Text("When a pattern finishes. Loops play normally.").font(.caption).foregroundStyle(.secondary)
                    }
                }.tint(PatternStyle.accent)
                Text(status).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("previewStatus")
            }.padding(18)
        }
        .background(PatternStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(PatternStyle.line, lineWidth: 1))
    }
}

private struct PatternDeviceWebView: UIViewRepresentable {
    let source: String
    let count: Int
    let restart: Int
    let autoRestart: Bool
    let active: Bool
    @Binding var status: String
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "preview")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "PatternPreviewWeb") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else { DispatchQueue.main.async { status = "Preview resources are unavailable." } }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        view.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        context.coordinator.update(view)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "preview")
        view.stopLoading()
        view.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: PatternDeviceWebView
        var ready = false
        var lastConfiguration: NSDictionary?
        init(_ parent: PatternDeviceWebView) { self.parent = parent }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            update(webView)
        }
        func update(_ view: WKWebView) {
            guard ready else { return }
            let configuration: [String: Any] = ["source": parent.source, "count": parent.count,
                "restart": parent.restart, "autoRestart": parent.autoRestart, "active": parent.active]
            let dictionary = configuration as NSDictionary
            guard lastConfiguration != dictionary else { return }
            lastConfiguration = dictionary
            view.callAsyncJavaScript("await window.configurePreview(configuration)", arguments: ["configuration": configuration], in: nil, in: .page) { [weak self] result in
                if case .failure = result { self?.parent.status = "Preview couldn’t load. You can still edit and save this pattern." }
            }
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let text = message.body as? String else { return }
            parent.status = text
        }
    }
}

enum PatternStyle {
    static let background = adaptive("F5F5F8", "14141B")
    static let card = adaptive("FFFFFF", "20212B")
    static let line = adaptive("DEDFe7", "363844")
    static let accent = adaptive("1765D3", "75AAFF")
    static let onAccent = adaptive("FFFFFF", "10233C")
    private static func adaptive(_ light: String, _ dark: String) -> Color {
        Color(UIColor { traits in
            let rgb = PatternRGB(traits.userInterfaceStyle == .dark ? dark : light)
            return UIColor(red: CGFloat(rgb.red)/255, green: CGFloat(rgb.green)/255, blue: CGFloat(rgb.blue)/255, alpha: 1)
        })
    }
}

struct PatternTextEditorView: View {
    @State var pattern: LibraryPattern
    @ObservedObject var store: PatternLibraryStore
    var isImport = false
    var onSaved: () -> Void = {}
    @State private var source: String
    @State private var preview: LibraryPattern
    @State private var initialName: String
    @State private var initialSource: String
    @State private var error: String?
    @State private var confirmDiscard = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editingSource: Bool

    init(pattern: LibraryPattern, store: PatternLibraryStore, isImport: Bool = false, onSaved: @escaping () -> Void = {}) {
        self._pattern = State(initialValue: pattern)
        self.store = store
        self.isImport = isImport
        self.onSaved = onSaved
        self._source = State(initialValue: pattern.ledText)
        self._preview = State(initialValue: pattern)
        self._initialName = State(initialValue: pattern.name)
        self._initialSource = State(initialValue: pattern.ledText)
    }
    private var hasChanges: Bool { pattern.name != initialName || source != initialSource }
    private var validationMessage: String? {
        do { _ = try pattern.replacingSource(source).validated(); return nil }
        catch { return error.localizedDescription }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(isImport ? "SHARED WITH YOU" : "MAKE IT YOURS")
                            .font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
                        TextField("Pattern name", text: $pattern.name, axis: .vertical)
                            .font(.largeTitle.weight(.bold)).tracking(-1)
                            .accessibilityIdentifier("patternName")
                        Text("A little light. Your way.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Edit pattern").font(.headline)
                            Spacer()
                            Text(".led").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        TextEditor(text: $source)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 220)
                            .padding(12).background(PatternStyle.card, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(PatternStyle.line))
                            .focused($editingSource)
                            .accessibilityLabel("LED pattern source")
                            .accessibilityIdentifier("patternSource")
                        Text("Edit any .led command. Apply updates the preview; Save keeps your exact text.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Link("LEDS_FORMAT.md on GitHub ↗", destination: URL(string: "https://github.com/inteliwear/sidepulse/blob/main/LEDS_FORMAT.md")!)
                            .font(.footnote)
                        HStack(spacing: 16) {
                            Button("Apply") {
                                do { preview = try pattern.replacingSource(source); editingSource = false }
                                catch { self.error = error.localizedDescription }
                            }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 14))
                                .foregroundStyle(PatternStyle.onAccent).disabled(source.utf8.count > 65536)
                            Button("Reset original") { source = initialSource; pattern.name = initialName; preview = pattern }
                                .buttonStyle(.bordered)
                        }.controlSize(.large)
                        if source != preview.ledText {
                            Text("Text changes haven’t been applied to the preview yet.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let validationMessage { Text(validationMessage).font(.footnote).foregroundStyle(.red) }
                    }
                    PatternPreview(pattern: preview)
                }.padding(20)
            }
            .background(PatternStyle.background)
            .navigationTitle("Edit .led text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if hasChanges { confirmDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isImport ? "Save copy" : "Save") {
                        do {
                            try store.save(pattern.replacingSource(source))
                            dismiss()
                            onSaved()
                        } catch { self.error = error.localizedDescription }
                    }.fontWeight(.semibold).disabled(validationMessage != nil)
                        .accessibilityIdentifier("savePattern")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editingSource = false } }
            }
            .tint(PatternStyle.accent)
            .interactiveDismissDisabled(hasChanges)
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
            .alert("Couldn’t save pattern", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}

struct PatternEditorView: View {
    let pattern: LibraryPattern
    @ObservedObject var store: PatternLibraryStore
    var isImport = false
    var body: some View {
        if pattern.canEditVisually {
            VisualPatternEditorView(pattern: pattern, store: store, isImport: isImport)
        } else {
            PatternTextEditorView(pattern: pattern, store: store, isImport: isImport)
        }
    }
}

struct VisualPatternEditorView: View {
    @State var pattern: LibraryPattern
    @ObservedObject var store: PatternLibraryStore
    var isImport = false
    @Environment(\.dismiss) private var dismiss
    @State private var textEditing = false
    @State private var error: String?
    @State private var confirmDiscard = false
    @State private var initialPattern: LibraryPattern?
    private var saveCandidate: LibraryPattern { pattern.preparingToSave(comparedTo: initialPattern) }
    private var validationMessage: String? {
        do { _ = try saveCandidate.validated(); return nil } catch { return error.localizedDescription }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isImport {
                    Section {
                        Label("Shared with you", systemImage: "square.and.arrow.down")
                        Text("Save your own copy. It won’t play on your Dot until you choose to play it.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField("Pattern name", text: $pattern.name)
                        .accessibilityIdentifier("patternName")
                }
                Section {
                    Button { textEditing = true } label: {
                        Label("Edit .led text", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } footer: { Text("Use the full .led language, including commands beyond the visual editor.") }
                if pattern.canEditVisually {
                    Section {
                        PatternPreview(pattern: saveCandidate).listRowInsets(EdgeInsets())
                    }
                    if pattern.source != nil {
                        Section {
                            Text("Changing the steps will replace the original file’s formatting and comments. Renaming keeps the file unchanged.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section("Playback") {
                        Toggle("Loop continuously", isOn: Binding(get: { pattern.repetitions == 0 }, set: { pattern.repetitions = $0 ? 0 : 1 }))
                        if pattern.repetitions > 0 {
                            Stepper("Plays: \(pattern.repetitions)", value: $pattern.repetitions, in: 1...20)
                        }
                    }
                    Section {
                        ForEach($pattern.steps) { $step in
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text("Step \((pattern.steps.firstIndex(where: { $0.id == step.id }) ?? 0) + 1)").font(.headline)
                                    Spacer()
                                    Button(role: .destructive) { pattern.steps.removeAll { $0.id == step.id } } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .disabled(pattern.steps.count == 1)
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Remove step")
                                }
                                ColorPicker("LED 1", selection: colorBinding($step.left), supportsOpacity: false)
                                ColorPicker("LED 2", selection: colorBinding($step.right), supportsOpacity: false)
                                Picker("Effect", selection: $step.effect) {
                                    ForEach(PatternEffect.allCases) { Text($0.title).tag($0) }
                                }
                                .pickerStyle(.segmented)
                                HStack {
                                    Text("Duration").font(.subheadline)
                                    Spacer()
                                    Text(String(format: "%.2f s", Double(step.durationMS) / 1000))
                                        .monospacedDigit().foregroundStyle(.secondary)
                                }
                                Slider(value: Binding(get: { Double(step.durationMS) }, set: { step.durationMS = Int($0) }),
                                       in: 50...10000, step: 50)
                                    .accessibilityLabel("Step duration in milliseconds")
                            }.padding(.vertical, 8)
                        }
                        .onMove { pattern.steps.move(fromOffsets: $0, toOffset: $1) }
                        Button { pattern.steps.append(PatternStep()) } label: {
                            Label("Add step", systemImage: "plus.circle.fill")
                        }.disabled(pattern.steps.count >= 12)
                    } header: {
                        Text("Sequence · \(pattern.steps.count) \(pattern.steps.count == 1 ? "step" : "steps")")
                    } footer: {
                        Text("Hold sets the colors immediately. Fade blends from the previous colors. Pulse rises to the chosen colors and returns to the previous colors.")
                    }
                } else {
                    Section { PatternSourceView(pattern: pattern).listRowInsets(EdgeInsets()) }
                }
                if let validationMessage {
                    Section { Text(validationMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle(isImport ? "Import Pattern" : store.patterns.contains(where: { $0.id == pattern.id }) ? "Edit Pattern" : "New Pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if initialPattern != pattern { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isImport ? "Save copy" : "Save") {
                        do { try store.save(saveCandidate); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                    .fontWeight(.semibold).disabled(validationMessage != nil)
                    .accessibilityIdentifier("savePattern")
                }
                ToolbarItem(placement: .bottomBar) { if pattern.canEditVisually { EditButton() } }
            }
            .alert("Couldn’t save pattern", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
            .sheet(isPresented: $textEditing) {
                PatternTextEditorView(pattern: saveCandidate, store: store, isImport: isImport) { dismiss() }
            }
            .tint(PatternStyle.accent)
            .interactiveDismissDisabled(initialPattern != pattern)
            .onAppear { if initialPattern == nil { initialPattern = pattern } }
        }
    }
    private func colorBinding(_ rgb: Binding<PatternRGB>) -> Binding<Color> {
        Binding(get: { rgb.wrappedValue.color }, set: { color in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            rgb.wrappedValue = PatternRGB(String(format: "%02X%02X%02X", Int((min(1, max(0, r)) * 255).rounded()), Int((min(1, max(0, g)) * 255).rounded()), Int((min(1, max(0, b)) * 255).rounded())))
        })
    }
}

extension PatternRGB {
    var color: Color { Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255) }
}
