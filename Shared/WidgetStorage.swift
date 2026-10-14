import Foundation

/// File layout inside the App Group container, shared by the app and the widget extension.
///
///     Library/widgets.json         every widget the user has made
///     Library/renders.json         what each rendered image was rendered from (app only)
///     Photos/<photo>.jpg           imported originals, downsampled for editing
///     Thumbs/<photo>.jpg           small previews
///     Thumbs/<photo>-glow.jpg      tiny blurred version used for "Glow" mats
///     Renders/<widget>/<photo>-<size>.jpg   final, cropped + filtered widget images
nonisolated enum WidgetStorage {
    static let appGroupID = "group.Adrian.Photo-Widget"
    static let widgetKind = "PhotoWidget"

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        // Without the entitlement (e.g. unsigned builds) keep working, just without the widget seeing it.
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var libraryURL: URL { directory("Library").appendingPathComponent("widgets.json") }
    static var renderManifestURL: URL { directory("Library").appendingPathComponent("renders.json") }
    static var legacyImageURL: URL { containerURL.appendingPathComponent("widget_photo.jpg") }

    static func photoURL(_ id: UUID) -> URL {
        directory("Photos").appendingPathComponent("\(id.uuidString).jpg")
    }

    static func thumbnailURL(_ id: UUID) -> URL {
        directory("Thumbs").appendingPathComponent("\(id.uuidString).jpg")
    }

    static func glowURL(_ id: UUID) -> URL {
        directory("Thumbs").appendingPathComponent("\(id.uuidString)-glow.jpg")
    }

    static func renderDirectory(widget: UUID) -> URL {
        directory("Renders/\(widget.uuidString)")
    }

    static func renderURL(widget: UUID, photo: UUID, size: WidgetSize) -> URL {
        renderDirectory(widget: widget).appendingPathComponent("\(photo.uuidString)-\(size.rawValue).jpg")
    }

    private static func directory(_ path: String) -> URL {
        let url = containerURL.appendingPathComponent(path, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    // MARK: - Library

    private struct LibraryFile: Codable {
        var version = 1
        var widgets: [PhotoWidgetConfig]
    }

    static func loadWidgets() -> [PhotoWidgetConfig] {
        loadLibrary() ?? []
    }

    /// `nil` when a library exists but can't be read. The file is set aside first, so saving a
    /// fresh library afterwards can never destroy the user's widgets.
    static func loadLibrary() -> [PhotoWidgetConfig]? {
        guard let data = try? Data(contentsOf: libraryURL) else { return [] }
        if let file = try? JSONDecoder().decode(LibraryFile.self, from: data) { return file.widgets }
        let backup = libraryURL.deletingLastPathComponent()
            .appendingPathComponent("widgets-unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: libraryURL, to: backup)
        return nil
    }

    static func saveWidgets(_ widgets: [PhotoWidgetConfig]) {
        guard let data = try? JSONEncoder().encode(LibraryFile(widgets: widgets)) else { return }
        try? data.write(to: libraryURL, options: .atomic)
    }

    /// What a Home Screen widget shows when the user hasn't picked one, or picked one that was
    /// since deleted: the first widget they made that has photos. It only changes if that widget
    /// is deleted, so editing or creating other widgets never swaps out what's on the Home Screen.
    static func defaultWidget(in widgets: [PhotoWidgetConfig]) -> PhotoWidgetConfig? {
        widgets.filter { !$0.photos.isEmpty }.min { $0.createdAt < $1.createdAt }
            ?? widgets.min { $0.createdAt < $1.createdAt }
    }

    /// The widget a Home Screen widget configured with `chosen` displays.
    static func resolve(_ chosen: UUID?, in widgets: [PhotoWidgetConfig]) -> PhotoWidgetConfig? {
        if let chosen, let widget = widgets.first(where: { $0.id == chosen }) { return widget }
        return defaultWidget(in: widgets)
    }

    // MARK: - Tap to advance

    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroupID) ?? .standard }

    static func tapOffset(for widget: UUID) -> Int {
        defaults.integer(forKey: "offset.\(widget.uuidString)")
    }

    static func advance(_ widget: UUID, by steps: Int = 1) {
        defaults.set(tapOffset(for: widget) + steps, forKey: "offset.\(widget.uuidString)")
    }

    static func resetOffset(for widget: UUID) {
        defaults.removeObject(forKey: "offset.\(widget.uuidString)")
    }
}
