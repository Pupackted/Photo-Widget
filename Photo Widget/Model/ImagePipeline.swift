import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Turns picked photos into files the app and widget can use, and learns a little about each
/// one along the way: where the faces are, its overall tone and when it was taken.
nonisolated enum ImagePipeline {
    static let masterMaxPixel = 2560
    static let thumbnailMaxPixel = 540
    static let proxyMaxPixel = 1600

    enum PipelineError: Error {
        case unreadable
        case unwritable
    }

    static func importPhoto(data: Data) throws -> WidgetPhoto {
        // Decode the original once; everything smaller is scaled down from the master.
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let master = downsample(source, maxPixel: masterMaxPixel),
              let thumbnail = resized(master, maxPixel: thumbnailMaxPixel) else {
            throw PipelineError.unreadable
        }

        var photo = WidgetPhoto(pixelWidth: master.width, pixelHeight: master.height)
        try write(master, to: WidgetStorage.photoURL(photo.id), quality: 0.9)
        try write(thumbnail, to: WidgetStorage.thumbnailURL(photo.id), quality: 0.85)
        if let glow = RenderEngine.glow(from: thumbnail) {
            try? write(glow, to: WidgetStorage.glowURL(photo.id), quality: 0.8)
        }

        photo.focus = focusPoint(in: resized(master, maxPixel: 768) ?? thumbnail)
        photo.dateTaken = dateTaken(source)
        photo.averageColor = RenderEngine.averageColor(of: thumbnail)
        return photo
    }

    // MARK: - Reading

    static func downsample(_ source: CGImageSource, maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func resized(_ image: CGImage, maxPixel: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxPixel else { return image }
        let scale = Double(maxPixel) / Double(longest)
        let width = max(Int((Double(image.width) * scale).rounded()), 1)
        let height = max(Int((Double(image.height) * scale).rounded()), 1)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: RenderEngine.outputColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    static func loadImage(at url: URL, maxPixel: Int? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        if let maxPixel {
            return downsample(source, maxPixel: maxPixel)
        }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    // MARK: - Writing

    /// Encodes in memory and writes atomically, so the widget never reads a half-written file.
    static func write(_ image: CGImage, to url: URL, quality: Double) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PipelineError.unwritable
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PipelineError.unwritable }
        try (data as Data).write(to: url, options: .atomic)
    }

    // MARK: - Understanding

    /// Faces win; otherwise whatever Vision finds most eye-catching; otherwise just above center.
    static func focusPoint(in image: CGImage) -> UnitPoint2D {
        let faces = VNDetectFaceRectanglesRequest()
        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([faces, saliency])

        // Vision uses a bottom-left origin.
        if let found = faces.results, !found.isEmpty {
            let box = found.map(\.boundingBox).reduce(found[0].boundingBox) { $0.union($1) }
            // Sit faces a little above center so there's room for shoulders.
            return UnitPoint2D(x: box.midX, y: min(1 - box.midY + box.height * 0.35, 0.95))
        }
        if let objects = saliency.results?.first?.salientObjects, !objects.isEmpty {
            let box = objects.map(\.boundingBox).reduce(objects[0].boundingBox) { $0.union($1) }
            return UnitPoint2D(x: box.midX, y: 1 - box.midY)
        }
        return UnitPoint2D(x: 0.5, y: 0.45)
    }

    static func dateTaken(_ source: CGImageSource) -> Date? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        guard let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: raw)
    }
}
