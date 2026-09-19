import UIKit

/// Decodes images off the main thread and keeps recently used ones around.
final class ImageCache {
    static let shared = ImageCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 160 * 1024 * 1024
        return cache
    }()

    func cached(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func thumbnail(_ photoID: UUID) async -> UIImage? {
        await image(key: "thumb/\(photoID)") {
            ImagePipeline.loadImage(at: WidgetStorage.thumbnailURL(photoID))
        }
    }

    func glow(_ photoID: UUID) async -> UIImage? {
        await image(key: "glow/\(photoID)") {
            ImagePipeline.loadImage(at: WidgetStorage.glowURL(photoID))
        }
    }

    func render(widget: UUID, photo: UUID, size: WidgetSize, generation: Int) async -> UIImage? {
        await image(key: "render/\(widget)/\(photo)/\(size.rawValue)/\(generation)") {
            ImagePipeline.loadImage(at: WidgetStorage.renderURL(widget: widget, photo: photo, size: size))
        }
    }

    /// The editing copy of a photo with the widget's look applied, cropped live on screen.
    func proxy(_ photoID: UUID, filter: PhotoFilter, intensity: Double) async -> UIImage? {
        let level = (intensity * 20).rounded() / 20
        return await image(key: "proxy/\(photoID)/\(filter.rawValue)/\(level)") {
            guard let base = ImagePipeline.loadImage(at: WidgetStorage.photoURL(photoID), maxPixel: ImagePipeline.proxyMaxPixel) else { return nil }
            return RenderEngine.filtered(base, filter: filter, intensity: level)
        }
    }

    /// Small previews for the filter picker.
    func swatch(_ photoID: UUID, filter: PhotoFilter) async -> UIImage? {
        await image(key: "swatch/\(photoID)/\(filter.rawValue)") {
            guard let base = ImagePipeline.loadImage(at: WidgetStorage.thumbnailURL(photoID), maxPixel: 200) else { return nil }
            return RenderEngine.filtered(base, filter: filter, intensity: 1)
        }
    }

    private func image(key: String, load: @escaping @Sendable () -> CGImage?) async -> UIImage? {
        if let hit = cached(key) { return hit }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            load().map { UIImage(cgImage: $0) }
        }.value
        if let image, let cg = image.cgImage {
            cache.setObject(image, forKey: key as NSString, cost: cg.bytesPerRow * cg.height)
        }
        return image
    }
}
