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
        guard let data = try? Data(contentsOf: libraryURL),
              let file = try? JSONDecoder().decode(LibraryFile.self, from: data) else { return [] }
        return file.widgets
    }

    static func saveWidgets(_ widgets: [PhotoWidgetConfig]) {
        guard let data = try? JSONEncoder().encode(LibraryFile(widgets: widgets)) else { return }
        try? data.write(to: libraryURL, options: .atomic)
    }

    /// The widget a Home Screen widget falls back to when the user hasn't picked one.
    static func mostRecentWidget(in widgets: [PhotoWidgetConfig]) -> PhotoWidgetConfig? {
        widgets.max { $0.modifiedAt < $1.modifiedAt }
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
