import AppIntents
import WidgetKit

// MARK: - Entity

/// A widget design, as the Home Screen's "Edit Widget" picker and Shortcuts see it.
nonisolated struct PhotoWidgetEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Photo Widget")
    static let defaultQuery = PhotoWidgetEntityQuery()

    let id: UUID
    let name: String
    let photoCount: Int
    let thumbnailURL: URL?

    init(_ config: PhotoWidgetConfig) {
        id = config.id
        name = config.name
        photoCount = config.photos.count
        thumbnailURL = config.coverPhoto.map { WidgetStorage.thumbnailURL($0.id) }
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: photoCount == 1 ? LocalizedStringResource("1 photo") : LocalizedStringResource("\(photoCount) photos"),
            image: thumbnailURL.map { DisplayRepresentation.Image(url: $0) }
        )
    }
}

nonisolated struct PhotoWidgetEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [PhotoWidgetEntity] {
        WidgetStorage.loadWidgets()
            .filter { identifiers.contains($0.id) }
            .map(PhotoWidgetEntity.init)
    }

    func suggestedEntities() async throws -> [PhotoWidgetEntity] {
        WidgetStorage.loadWidgets()
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .map(PhotoWidgetEntity.init)
    }

    func defaultResult() async -> PhotoWidgetEntity? {
        WidgetStorage.defaultWidget(in: WidgetStorage.loadWidgets()).map(PhotoWidgetEntity.init)
    }
}

// MARK: - Widget configuration

struct SelectPhotoWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Photos"
    static let description = IntentDescription("Pick which of your photo widgets to show.")

    @Parameter(title: "Widget")
    var widget: PhotoWidgetEntity?

    init() {}

    init(widget: PhotoWidgetEntity?) {
        self.widget = widget
    }
}

// MARK: - Actions

/// Runs when a widget set to "Next Photo" is tapped.
struct NextPhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Photo"
    static let isDiscoverable = false

    @Parameter(title: "Widget")
    var widgetID: String

    init() {}

    init(widgetID: UUID) {
        self.widgetID = widgetID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: widgetID) {
            WidgetStorage.advance(id)
        }
        return .result()
    }
}

/// Moves every widget on to its next photo. Powers the Control Center button and Siri.
nonisolated struct ShufflePhotoWidgetsIntent: AppIntent {
    static let title: LocalizedStringResource = "Shuffle Photo Widgets"
    static let description = IntentDescription("Shows the next photo on all of your photo widgets.")

    init() {}

    func perform() async throws -> some IntentResult {
        for widget in WidgetStorage.loadWidgets() where widget.photos.count > 1 {
            WidgetStorage.advance(widget.id)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.widgetKind)
        return .result()
    }
}
