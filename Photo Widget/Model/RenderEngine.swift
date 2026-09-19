import CoreImage
import Foundation

/// Core Image work: filters, the final widget renders, and small derived images.
nonisolated enum RenderEngine {
    static let context = CIContext(options: [.cacheIntermediates: false])
    static let outputColorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    // MARK: - Filters

    static func apply(_ filter: PhotoFilter, intensity: Double, to input: CIImage) -> CIImage {
        guard filter != .original, intensity > 0.001 else { return input }
        let filtered = look(filter, on: input)
        guard intensity < 0.999 else { return filtered }
        return input.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: filtered,
            kCIInputTimeKey: intensity,
        ])
    }

    private static func look(_ filter: PhotoFilter, on input: CIImage) -> CIImage {
        switch filter {
        case .original:
            return input
        case .vivid:
            return input
                .applyingFilter("CIVibrance", parameters: ["inputAmount": 0.6])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.06, kCIInputContrastKey: 1.06])
        case .golden:
            return input
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1.07, y: 0.03, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0.02, y: 1.01, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0.84, w: 0),
                    "inputBiasVector": CIVector(x: 0.025, y: 0.012, z: 0, w: 0),
                ])
                .applyingFilter("CIVibrance", parameters: ["inputAmount": 0.25])
        case .coastal:
            return input
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0.92, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 1.0, z: 0.03, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0.02, z: 1.08, w: 0),
                    "inputBiasVector": CIVector(x: 0, y: 0.01, z: 0.035, w: 0),
                ])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.94, kCIInputBrightnessKey: 0.015])
        case .film:
            return input.applyingFilter("CIPhotoEffectTransfer")
        case .faded:
            return input.applyingFilter("CIPhotoEffectFade")
        case .instant:
            return input.applyingFilter("CIPhotoEffectInstant")
        case .dream:
            let radius = max(input.extent.width, input.extent.height) * 0.014
            return input
                .clampedToExtent()
                .applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: radius, kCIInputIntensityKey: 0.75])
                .cropped(to: input.extent)
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.9, kCIInputBrightnessKey: 0.03, kCIInputContrastKey: 0.94,
                ])
        case .mono:
            return input.applyingFilter("CIPhotoEffectMono")
        case .noir:
            return input.applyingFilter("CIPhotoEffectNoir")
        }
    }

    /// The whole photo with a look applied — the editor crops it live on screen.
    static func filtered(_ image: CGImage, filter: PhotoFilter, intensity: Double) -> CGImage? {
        guard filter != .original else { return image }
        let input = CIImage(cgImage: image)
        let output = apply(filter, intensity: intensity, to: input)
        return context.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: outputColorSpace)
    }

    // MARK: - Widget renders

    /// The photo slot of a widget, exactly as it will appear on the Home Screen.
    static func renderPhoto(_ source: CGImage, photo: WidgetPhoto, size: WidgetSize, style: WidgetStyle) -> CGImage? {
        let layout = WidgetLayout.canonical(size, frame: style.frame)
        let output = CGSize(width: (layout.photoRect.width * size.renderScale).rounded(),
                            height: (layout.photoRect.height * size.renderScale).rounded())
        let crop = photo.crop(for: size).clamped(imageAspect: photo.aspect, targetAspect: layout.photoAspect)
        let unit = crop.rect(imageAspect: photo.aspect, targetAspect: layout.photoAspect)

        let width = CGFloat(source.width), height = CGFloat(source.height)
        // Core Image's origin is bottom-left.
        let region = CGRect(x: unit.minX * width, y: (1 - unit.maxY) * height,
                            width: unit.width * width, height: unit.height * height)
        guard region.width > 1, region.height > 1 else { return nil }

        let scale = output.height / region.height
        var image = CIImage(cgImage: source)
            .cropped(to: region)
            .transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY))
            .clampedToExtent()
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: (output.width / region.width) / scale,
            ])
        let bounds = CGRect(origin: .zero, size: output)
        image = apply(style.filter, intensity: style.filterIntensity, to: image.cropped(to: bounds))
        return context.createCGImage(image, from: bounds, format: .RGBA8, colorSpace: outputColorSpace)
    }

    // MARK: - Derived

    /// A tiny, heavily blurred copy used for "Glow" mats and ambient backgrounds.
    static func glow(from image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let longest = max(input.extent.width, input.extent.height)
        let small = input.transformed(by: CGAffineTransform(scaleX: 120 / longest, y: 120 / longest))
        let output = small
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 9])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.35])
            .cropped(to: small.extent)
        return context.createCGImage(output, from: small.extent, format: .RGBA8, colorSpace: outputColorSpace)
    }

    static func averageColor(of image: CGImage) -> RGBColor {
        let input = CIImage(cgImage: image)
        let average = input.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: input.extent)])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return RGBColor(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }
}
