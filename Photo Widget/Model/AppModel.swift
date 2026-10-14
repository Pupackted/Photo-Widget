import Observation
import PhotosUI
import SwiftUI
import WidgetKit

/// The app's single source of truth: the user's widgets, plus the background work that keeps
/// the Home Screen in sync with them (importing photos and rendering widget images).
@Observable
final class AppModel {
    private(set) var widgets: [PhotoWidgetConfig] = []
    /// Photos still being imported, per widget.
    private(set) var importing: [UUID: Int] = [:]
    /// Render progress, per widget, while the Home Screen copy is being updated.
    private(set) var syncing: [UUID: SyncProgress] = [:]
    /// Bumps whenever a widget's rendered images change, so previews reload them.
    private(set) var renderGeneration: [UUID: Int] = [:]
    /// Widgets that are currently placed on the Home Screen.
    private(set) var placedWidgetIDs: Set<UUID> = []
    /// A widget or action requested from outside, e.g. by tapping a widget.
    var pendingRoute: Route?
    /// Photos that couldn't be imported, waiting to be explained to the user.
    var importIssue: ImportIssue?
    /// The photo removed last, kept for a few seconds so it can be put back.
    private(set) var recentlyRemoved: RemovedPhoto?

    enum Route: Equatable {
        case widget(UUID)
        case newWidget
    }

    struct SyncProgress: Equatable {
        var done: Int
        var total: Int
    }

    struct ImportIssue: Identifiable, Equatable {
        let id = UUID()
        let failed: Int
        let total: Int
    }

    struct RemovedPhoto: Equatable {
        let widgetID: UUID
        let photo: WidgetPhoto
        let index: Int
    }

    @ObservationIgnored private var manifest: [String: String] = [:]
    @ObservationIgnored private var renderTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    /// False when the saved library couldn't be read: its photos are then left untouched on disk.
    @ObservationIgnored private let libraryReadable: Bool

    init() {
        let library = WidgetStorage.loadLibrary()
        widgets = library ?? []
        libraryReadable = library != nil
        if let data = try? Data(contentsOf: WidgetStorage.renderManifestURL),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            manifest = saved
        }
        Task { await migrateLegacyPhoto() }
        // Clears out photos left behind if the app was closed in the middle of an import.
        collectUnusedPhotos()
        for widget in widgets { scheduleRender(widget.id, delay: .zero) }
    }

    // MARK: - Reading

    func widget(_ id: UUID) -> PhotoWidgetConfig? {
        widgets.first { $0.id == id }
    }

    var sortedWidgets: [PhotoWidgetConfig] {
        widgets.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Editing

    func update(_ id: UUID, _ change: (inout PhotoWidgetConfig) -> Void) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        var widget = widgets[index]
        change(&widget)
        guard widget != widgets[index] else { return }
        widget.modifiedAt = .now
        widgets[index] = widget
        scheduleSave()
        scheduleRender(id)
    }

    @discardableResult
    func createWidget(named name: String = String(localized: "New Widget")) -> UUID {
        let widget = PhotoWidgetConfig(name: name)
        widgets.append(widget)
        scheduleSave()
        return widget.id
    }

    @discardableResult
    func duplicate(_ id: UUID) -> UUID? {
        guard var copy = widget(id) else { return nil }
        copy.id = UUID()
        copy.name = String(localized: "\(copy.name) Copy")
        copy.createdAt = .now
        copy.modifiedAt = .now
        widgets.append(copy)
        scheduleSave()
        scheduleRender(copy.id, delay: .zero)
        return copy.id
    }

    func delete(_ id: UUID) {
        finishPendingRemoval()
        renderTasks[id]?.cancel()
        widgets.removeAll { $0.id == id }
        manifest = manifest.filter { !$0.key.hasPrefix(id.uuidString) }
        try? FileManager.default.removeItem(at: WidgetStorage.renderDirectory(widget: id))
        WidgetStorage.resetOffset(for: id)
        collectUnusedPhotos()
        scheduleSave()
        reloadWidgets()
    }

    /// Removes a photo, keeping its files for a few seconds in case the user taps Undo.
    func removePhoto(_ photoID: UUID, from id: UUID) {
        guard let index = widget(id)?.photos.firstIndex(where: { $0.id == photoID }),
              let photo = widget(id)?.photos[index] else { return }
        finishPendingRemoval()
        recentlyRemoved = RemovedPhoto(widgetID: id, photo: photo, index: index)
        update(id) { $0.photos.remove(at: index) }
        undoTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            finishPendingRemoval()
        }
    }

    func undoRemove() {
        guard let removed = recentlyRemoved else { return }
        undoTask?.cancel()
        recentlyRemoved = nil
        update(removed.widgetID) { widget in
            widget.photos.insert(removed.photo, at: min(removed.index, widget.photos.count))
        }
    }

    private func finishPendingRemoval() {
        undoTask?.cancel()
        undoTask = nil
        guard recentlyRemoved != nil else { return }
        recentlyRemoved = nil
        collectUnusedPhotos()
    }

    /// Moves a photo to where `targetID` is, shifting the others along.
    func movePhoto(_ photoID: UUID, to targetID: UUID, in id: UUID) {
        update(id) { widget in
            guard let from = widget.photos.firstIndex(where: { $0.id == photoID }),
                  let to = widget.photos.firstIndex(where: { $0.id == targetID }), from != to else { return }
            widget.photos.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func setCaption(_ caption: String, photo photoID: UUID, in id: UUID) {
        update(id) { widget in
            guard let index = widget.photos.firstIndex(where: { $0.id == photoID }) else { return }
            widget.photos[index].caption = caption
        }
    }

    func makeCover(_ photoID: UUID, in id: UUID) {
        update(id) { widget in
            guard let index = widget.photos.firstIndex(where: { $0.id == photoID }) else { return }
            widget.photos.insert(widget.photos.remove(at: index), at: 0)
        }
        WidgetStorage.resetOffset(for: id)
    }

    func setCrop(_ crop: CropState?, photo photoID: UUID, size: WidgetSize, in id: UUID) {
        update(id) { widget in
            guard let index = widget.photos.firstIndex(where: { $0.id == photoID }) else { return }
            widget.photos[index].crops[size.rawValue] = crop
        }
    }

    // MARK: - Importing

    /// How many more photos a widget can take, counting ones still importing.
    func capacity(of id: UUID) -> Int {
        max((widget(id)?.remainingCapacity ?? 0) - (importing[id] ?? 0), 0)
    }

    func importPhotos(_ items: [PhotosPickerItem], into id: UUID) {
        let items = Array(items.prefix(capacity(of: id)))
        guard !items.isEmpty else { return }
        importing[id, default: 0] += items.count

        Task {
            var failed = 0
            // A few at a time: fast, without holding dozens of full-size photos in memory.
            for batch in stride(from: 0, to: items.count, by: 3).map({ Array(items[$0..<min($0 + 3, items.count)]) }) {
                let photos = await withTaskGroup(of: (Int, WidgetPhoto?).self) { group in
                    for (offset, item) in batch.enumerated() {
                        group.addTask {
                            guard let data = try? await item.loadTransferable(type: Data.self) else { return (offset, nil) }
                            return (offset, try? ImagePipeline.importPhoto(data: data))
                        }
                    }
                    var results = [(Int, WidgetPhoto?)]()
                    for await result in group { results.append(result) }
                    return results.sorted { $0.0 < $1.0 }.map(\.1)
                }

                let imported = photos.compactMap { $0 }
                failed += photos.count - imported.count
                // The widget was deleted while these were importing.
                if widget(id) == nil { removeFiles(of: imported.map(\.id)) }

                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    update(id) { widget in
                        if widget.photos.isEmpty, widget.name == String(localized: "New Widget"), let date = imported.first?.dateTaken {
                            widget.name = date.formatted(.dateTime.month(.wide).year())
                        }
                        widget.photos.append(contentsOf: imported)
                    }
                    importing[id] = max((importing[id] ?? 0) - batch.count, 0)
                }
            }
            if importing[id] == 0 { importing[id] = nil }
            // Usually originals that are only in iCloud while the phone is offline.
            if failed > 0 { importIssue = ImportIssue(failed: failed, total: items.count) }
        }
    }

    /// Brings the single photo from the first version of the app into the new library.
    private func migrateLegacyPhoto() async {
        let legacy = WidgetStorage.legacyImageURL
        guard widgets.isEmpty, let data = try? Data(contentsOf: legacy) else { return }
        let photo = await Task.detached { try? ImagePipeline.importPhoto(data: data) }.value
        guard let photo else { return }
        var widget = PhotoWidgetConfig(name: String(localized: "My Photo"))
        widget.photos = [photo]
        widget.rotation = .never
        widgets.append(widget)
        try? FileManager.default.removeItem(at: legacy)
        scheduleSave()
        scheduleRender(widget.id, delay: .zero)
    }

    // MARK: - Routing

    func handle(_ url: URL) {
        guard url.scheme == "photowidget" else { return }
        switch url.host() {
        case "widget":
            if let id = UUID(uuidString: url.lastPathComponent), widget(id) != nil {
                pendingRoute = .widget(id)
            }
        case "new":
            pendingRoute = .newWidget
        default:
            break
        }
    }

    // MARK: - Home Screen

    func refreshPlacedWidgets() async {
        // The async `currentConfigurations()` needs iOS 18.
        let placed: [WidgetInfo]? = await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { continuation.resume(returning: try? $0.get()) }
        }
        guard let placed else { return }
        var ids = Set<UUID>()
        for info in placed where info.kind == WidgetStorage.widgetKind {
            let chosen = info.widgetConfigurationIntent(of: SelectPhotoWidgetIntent.self)?.widget?.id
            if let shown = WidgetStorage.resolve(chosen, in: widgets)?.id { ids.insert(shown) }
        }
        placedWidgetIDs = ids
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.widgetKind)
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    func save() {
        WidgetStorage.saveWidgets(widgets)
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: WidgetStorage.renderManifestURL, options: .atomic)
        }
    }

    private func collectUnusedPhotos() {
        guard libraryReadable else { return }
        var inUse = Set(widgets.flatMap { $0.photos.map(\.id) })
        if let removed = recentlyRemoved { inUse.insert(removed.photo.id) }
        // Photos still importing are written before they join a widget.
        guard importing.isEmpty else { return }
        let folder = WidgetStorage.photoURL(UUID()).deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        let unused = files.compactMap { UUID(uuidString: String($0.prefix(36))) }.filter { !inUse.contains($0) }
        removeFiles(of: unused)
    }

    private func removeFiles(of photoIDs: [UUID]) {
        for id in photoIDs {
            try? FileManager.default.removeItem(at: WidgetStorage.photoURL(id))
            try? FileManager.default.removeItem(at: WidgetStorage.thumbnailURL(id))
            try? FileManager.default.removeItem(at: WidgetStorage.glowURL(id))
        }
    }

    // MARK: - Rendering

    private struct RenderJob: Sendable {
        let photo: WidgetPhoto
        let sizes: [WidgetSize]
    }

    static var renderedSizes: [WidgetSize] {
        UIDevice.current.userInterfaceIdiom == .pad ? WidgetSize.allCases : [.small, .medium, .large]
    }

    private func signature(_ photo: WidgetPhoto, _ size: WidgetSize, _ style: WidgetStyle, _ collage: CollageLayout) -> String {
        let crop = photo.crop(for: size)
        return "\(crop.centerX),\(crop.centerY),\(crop.zoom)|\(style.filter.rawValue)|\(style.filterIntensity)|\(style.frame.rawValue)|\(collage.rawValue)|2"
    }

    private func manifestKey(_ widget: UUID, _ photo: UUID, _ size: WidgetSize) -> String {
        "\(widget.uuidString)/\(photo.uuidString)/\(size.rawValue)"
    }

    /// Debounced so a flurry of edits (dragging a slider) renders once, when the user settles.
    func scheduleRender(_ id: UUID, delay: Duration = .milliseconds(350)) {
        renderTasks[id]?.cancel()
        renderTasks[id] = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await render(id)
        }
    }

    private func render(_ id: UUID) async {
        guard let widget = widget(id) else { return }
        let style = widget.style
        let collage = widget.effectiveLayout

        let jobs = widget.photos.compactMap { photo -> RenderJob? in
            let stale = Self.renderedSizes.filter { size in
                manifest[manifestKey(id, photo.id, size)] != signature(photo, size, style, collage)
                    || !FileManager.default.fileExists(atPath: WidgetStorage.renderURL(widget: id, photo: photo.id, size: size).path)
            }
            return stale.isEmpty ? nil : RenderJob(photo: photo, sizes: stale)
        }

        if !jobs.isEmpty {
            let total = jobs.reduce(0) { $0 + $1.sizes.count }
            syncing[id] = SyncProgress(done: 0, total: total)

            for job in jobs {
                guard !Task.isCancelled else { return }
                let rendered = await Task.detached(priority: .userInitiated) { () -> [WidgetSize] in
                    guard let source = ImagePipeline.loadImage(at: WidgetStorage.photoURL(job.photo.id)) else { return [] }
                    return job.sizes.filter { size in
                        guard let image = RenderEngine.renderPhoto(source, photo: job.photo, size: size, style: style, collage: collage) else { return false }
                        return (try? ImagePipeline.write(image, to: WidgetStorage.renderURL(widget: id, photo: job.photo.id, size: size), quality: 0.9)) != nil
                    }
                }.value
                for size in rendered {
                    manifest[manifestKey(id, job.photo.id, size)] = signature(job.photo, size, style, collage)
                }
                syncing[id]?.done += job.sizes.count
            }
            renderGeneration[id, default: 0] += 1
        }

        removeStaleRenders(for: widget)
        save()
        reloadWidgets()
        syncing[id] = nil
    }

    private func removeStaleRenders(for widget: PhotoWidgetConfig) {
        let folder = WidgetStorage.renderDirectory(widget: widget.id)
        let current = Set(widget.photos.map(\.id.uuidString))
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for file in files where !current.contains(String(file.prefix(36))) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
        manifest = manifest.filter { key, _ in
            let parts = key.split(separator: "/")
            return parts.first != Substring(widget.id.uuidString) || current.contains(String(parts[1]))
        }
    }
}
