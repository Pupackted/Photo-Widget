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

    enum Route: Equatable {
        case widget(UUID)
        case newWidget
    }

    struct SyncProgress: Equatable {
        var done: Int
        var total: Int
    }

    @ObservationIgnored private var manifest: [String: String] = [:]
    @ObservationIgnored private var renderTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        widgets = WidgetStorage.loadWidgets()
        if let data = try? Data(contentsOf: WidgetStorage.renderManifestURL),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            manifest = saved
        }
        Task { await migrateLegacyPhoto() }
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
    func createWidget(named name: String = "New Widget") -> UUID {
        let widget = PhotoWidgetConfig(name: name)
        widgets.append(widget)
        scheduleSave()
        return widget.id
    }

    @discardableResult
    func duplicate(_ id: UUID) -> UUID? {
        guard var copy = widget(id) else { return nil }
        copy.id = UUID()
        copy.name = "\(copy.name) Copy"
        copy.createdAt = .now
        copy.modifiedAt = .now
        widgets.append(copy)
        scheduleSave()
        scheduleRender(copy.id, delay: .zero)
        return copy.id
    }

    func delete(_ id: UUID) {
        renderTasks[id]?.cancel()
        widgets.removeAll { $0.id == id }
        manifest = manifest.filter { !$0.key.hasPrefix(id.uuidString) }
        try? FileManager.default.removeItem(at: WidgetStorage.renderDirectory(widget: id))
        WidgetStorage.resetOffset(for: id)
        collectUnusedPhotos()
        scheduleSave()
        reloadWidgets()
    }

    func removePhoto(_ photoID: UUID, from id: UUID) {
        update(id) { $0.photos.removeAll { $0.id == photoID } }
        collectUnusedPhotos()
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

    func importPhotos(_ items: [PhotosPickerItem], into id: UUID) {
        guard !items.isEmpty else { return }
        importing[id, default: 0] += items.count

        Task {
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

                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    let imported = photos.compactMap { $0 }
                    update(id) { widget in
                        if widget.photos.isEmpty, widget.name == "New Widget", let date = imported.first?.dateTaken {
                            widget.name = date.formatted(.dateTime.month(.wide).year())
                        }
                        widget.photos.append(contentsOf: imported)
                    }
                    importing[id] = max((importing[id] ?? 0) - batch.count, 0)
                }
            }
            if importing[id] == 0 { importing[id] = nil }
        }
    }

    /// Brings the single photo from the first version of the app into the new library.
    private func migrateLegacyPhoto() async {
        let legacy = WidgetStorage.legacyImageURL
        guard widgets.isEmpty, let data = try? Data(contentsOf: legacy) else { return }
        let photo = await Task.detached { try? ImagePipeline.importPhoto(data: data) }.value
        guard let photo else { return }
        var widget = PhotoWidgetConfig(name: "My Photo")
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
        guard let placed = try? await WidgetCenter.shared.currentConfigurations() else { return }
        let fallback = WidgetStorage.mostRecentWidget(in: widgets)?.id
        var ids = Set<UUID>()
        for info in placed where info.kind == WidgetStorage.widgetKind {
            if let chosen = info.widgetConfigurationIntent(of: SelectPhotoWidgetIntent.self)?.widget?.id {
                ids.insert(chosen)
            } else if let fallback {
                ids.insert(fallback)
            }
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
        let inUse = Set(widgets.flatMap { $0.photos.map(\.id) })
        let folder = WidgetStorage.photoURL(UUID()).deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for file in files {
            guard let id = UUID(uuidString: String(file.prefix(36))), !inUse.contains(id) else { continue }
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

    private func signature(_ photo: WidgetPhoto, _ size: WidgetSize, _ style: WidgetStyle) -> String {
        let crop = photo.crop(for: size)
        return "\(crop.centerX),\(crop.centerY),\(crop.zoom)|\(style.filter.rawValue)|\(style.filterIntensity)|\(style.frame.rawValue)|1"
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

        let jobs = widget.photos.compactMap { photo -> RenderJob? in
            let stale = Self.renderedSizes.filter { size in
                manifest[manifestKey(id, photo.id, size)] != signature(photo, size, style)
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
                        guard let image = RenderEngine.renderPhoto(source, photo: job.photo, size: size, style: style) else { return false }
                        return (try? ImagePipeline.write(image, to: WidgetStorage.renderURL(widget: id, photo: job.photo.id, size: size), quality: 0.9)) != nil
                    }
                }.value
                for size in rendered {
                    manifest[manifestKey(id, job.photo.id, size)] = signature(job.photo, size, style)
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
