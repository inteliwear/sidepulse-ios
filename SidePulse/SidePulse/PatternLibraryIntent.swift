// Copyright (c) 2026 InteliWEAR LLC. MPL-2.0.
import AppIntents
import Foundation

struct SavedPatternEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Saved Pattern")
    static var defaultQuery = SavedPatternQuery()
    var id: UUID
    var name: String
    var detail: String
    var thumbnailData: Data?

    init(_ pattern: LibraryPattern) {
        id = pattern.id
        name = pattern.name
        detail = pattern.summary
        thumbnailData = PatternThumbnailRenderer.data(for: pattern)
    }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)",
                              image: thumbnailData.map { .init(data: $0, isTemplate: false) }
                                ?? .init(systemName: "doc.text"))
    }
}

struct SavedPatternQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [SavedPatternEntity] {
        let patterns = try PatternLibraryRepository.standard.load()
        return identifiers.compactMap { id in patterns.first { $0.id == id }.map(SavedPatternEntity.init) }
    }
    func suggestedEntities() async throws -> [SavedPatternEntity] {
        try PatternLibraryRepository.standard.load().map(SavedPatternEntity.init)
    }
    func entities(matching string: String) async throws -> [SavedPatternEntity] {
        try PatternLibraryRepository.standard.load()
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(SavedPatternEntity.init)
    }
}

/// Expose the current library on the app's Shortcuts page, not only in the
/// action's entity picker. Saves, imports, and deletions refresh this collection.
struct SavedPatternOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [SavedPatternEntity] {
        try await SavedPatternQuery().suggestedEntities()
    }
}

struct PlaySavedPatternIntent: AppIntent {
    static var title: LocalizedStringResource = "Play SidePulse Pattern"
    static var description = IntentDescription("Plays a saved pattern from your SidePulse Pattern Library.")
    static var openAppWhenRun = false

    @Parameter(title: "Pattern", requestValueDialog: "Which pattern from your SidePulse library?")
    var pattern: SavedPatternEntity
    static var parameterSummary: some ParameterSummary { Summary("Play \(\.$pattern) on SidePulse Dot") }

    func perform() async throws -> some IntentResult {
        guard let saved = try PatternLibraryRepository.standard.load().first(where: { $0.id == pattern.id }) else {
            throw PatternLibraryError.invalid("This pattern was deleted. Choose another pattern in this shortcut.")
        }
        _ = try saved.validated()
        _ = try DriveWriter.shared.write(saved.ledText)
        await MainActor.run {
            AppModel.shared.ledText = saved.ledText
            AppModel.shared.recordReceivedPush(ReceivedPush(
                source: "Shortcut", title: saved.name, body: saved.summary, ledText: saved.ledText,
                payloadSummary: "Saved pattern: \(saved.name)", writeStatus: .wrote))
        }
        return .result()
    }
}
