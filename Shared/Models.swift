import Foundation
import CoreGraphics

// MARK: - Widget

/// One widget the user has designed: a set of photos plus how they're framed, styled and rotated.
nonisolated struct PhotoWidgetConfig: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var photos: [WidgetPhoto] = []
    var style = WidgetStyle()
    var rotation: RotationInterval = .hourly
    var order: PlaybackOrder = .inOrder
    var tapAction: TapAction = .openApp
    var createdAt = Date()
    var modifiedAt = Date()

    var coverPhoto: WidgetPhoto? { photos.first }

    func photo(id: UUID?) -> WidgetPhoto? {
        guard let id else { return nil }
        return photos.first { $0.id == id }
    }

    /// The photo the widget is showing at `date`, honouring rotation, order and tap-to-advance.
    func currentPhoto(at date: Date = .now, offset: Int = 0) -> WidgetPhoto? {
        guard !photos.isEmpty else { return nil }
        return photos[PhotoSchedule.index(for: self, at: date, offset: offset)]
    }

    var summary: String {
        let count = photos.count == 1 ? "1 photo" : "\(photos.count) photos"
        guard photos.count > 1 else { return count }
        return "\(count) · \(rotation.summary)"
    }
}

// MARK: - Photo

nonisolated struct WidgetPhoto: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var pixelWidth: Int
    var pixelHeight: Int
    /// Where the interesting part of the photo is (faces, or the most salient object), in unit coordinates, top-left origin.
    var focus = UnitPoint2D(x: 0.5, y: 0.45)
    /// Manual framing per widget size. Sizes without an entry are framed automatically around `focus`.
    var crops: [String: CropState] = [:]
    var dateTaken: Date?
    var averageColor = RGBColor(red: 0.55, green: 0.55, blue: 0.58)

    var aspect: Double { Double(pixelWidth) / Double(max(pixelHeight, 1)) }

    func crop(for size: WidgetSize) -> CropState {
        crops[size.rawValue] ?? CropState(centerX: focus.x, centerY: focus.y, zoom: 1)
    }

    func hasCustomCrop(for size: WidgetSize) -> Bool { crops[size.rawValue] != nil }
}

nonisolated struct UnitPoint2D: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
}

nonisolated struct RGBColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxV = max(red, green, blue), minV = min(red, green, blue)
        let delta = maxV - minV
        var hue = 0.0
        if delta > 0 {
            if maxV == red { hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxV == green { hue = (blue - red) / delta + 2 }
            else { hue = (red - green) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maxV == 0 ? 0 : delta / maxV, maxV)
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        let h = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (r, g, b): (Double, Double, Double) = switch Int(h) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        self.init(red: r + m, green: g + m, blue: b + m)
    }
}

// MARK: - Crop

/// Aspect-independent framing: a focus point and a zoom factor. The same state can be
/// projected onto any widget shape, so switching frame styles never loses the user's framing.
nonisolated struct CropState: Codable, Hashable, Sendable {
    static let minZoom = 1.0
    static let maxZoom = 5.0

    var centerX: Double
    var centerY: Double
    var zoom: Double

    /// Normalized (0...1, top-left origin) size of the crop for a target aspect ratio.
    static func cropSize(imageAspect: Double, targetAspect: Double, zoom: Double) -> CGSize {
        let base: CGSize = targetAspect > imageAspect
            ? CGSize(width: 1, height: imageAspect / targetAspect)
            : CGSize(width: targetAspect / imageAspect, height: 1)
        let z = max(zoom, 0.01)
        return CGSize(width: base.width / z, height: base.height / z)
    }

    /// The crop rectangle in unit image coordinates. Not clamped — call `clamped` first when needed.
    func rect(imageAspect: Double, targetAspect: Double) -> CGRect {
        let size = Self.cropSize(imageAspect: imageAspect, targetAspect: targetAspect, zoom: zoom)
        return CGRect(x: centerX - size.width / 2, y: centerY - size.height / 2, width: size.width, height: size.height)
    }

    /// Keeps zoom in range and the crop fully inside the image.
    func clamped(imageAspect: Double, targetAspect: Double) -> CropState {
        var state = self
        state.zoom = min(max(zoom, Self.minZoom), Self.maxZoom)
        let size = Self.cropSize(imageAspect: imageAspect, targetAspect: targetAspect, zoom: state.zoom)
        state.centerX = Self.clamp(centerX, half: size.width / 2)
        state.centerY = Self.clamp(centerY, half: size.height / 2)
        return state
    }

    private static func clamp(_ value: Double, half: Double) -> Double {
        guard half < 0.5 else { return 0.5 }
        return min(max(value, half), 1 - half)
    }
}

// MARK: - Sizes

nonisolated enum WidgetSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    /// Size on the largest iPhones (iPad for extra large), in points. Everything else scales from this.
    var canonicalSize: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        case .extraLarge: CGSize(width: 715, height: 338)
        }
    }

    var cornerRadius: CGFloat { self == .extraLarge ? 24 : 22 }

    /// Pixel density used when rendering the widget image.
    var renderScale: CGFloat { self == .extraLarge ? 2 : 3 }

    var captionPointSize: CGFloat {
        switch self {
        case .small, .medium: 13
        case .large, .extraLarge: 15
        }
    }
}

// MARK: - Style

nonisolated struct WidgetStyle: Codable, Hashable, Sendable {
    var filter: PhotoFilter = .original
    var filterIntensity: Double = 1
    var frame: FrameStyle = .fullBleed
    var mat: MatStyle = .auto
    var caption: CaptionMode = .none
    var captionText: String = ""
    var font: CaptionFont = .rounded
    var fullColorInTintedMode = true
}

nonisolated enum PhotoFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case original, vivid, golden, coastal, film, faded, instant, dream, mono, noir

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "Original"
        case .vivid: "Vivid"
        case .golden: "Golden"
        case .coastal: "Coastal"
        case .film: "Film"
        case .faded: "Faded"
        case .instant: "Instant"
        case .dream: "Dream"
        case .mono: "Mono"
        case .noir: "Noir"
        }
    }
}

nonisolated enum FrameStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case fullBleed, border, polaroid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullBleed: "Full Bleed"
        case .border: "Border"
        case .polaroid: "Instant"
        }
    }
}

nonisolated enum MatStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, glow, white, paper, charcoal, black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .glow: "Glow"
        case .white: "White"
        case .paper: "Paper"
        case .charcoal: "Charcoal"
        case .black: "Black"
        }
    }
}

nonisolated enum CaptionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, text, date, timeAgo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .text: "Text"
        case .date: "Date"
        case .timeAgo: "Time Ago"
        }
    }
}

nonisolated enum CaptionFont: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, rounded, serif, mono, script

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Classic"
        case .rounded: "Rounded"
        case .serif: "Serif"
        case .mono: "Mono"
        case .script: "Script"
        }
    }
}

// MARK: - Behaviour

nonisolated enum RotationInterval: String, Codable, CaseIterable, Identifiable, Sendable {
    case never, fifteenMinutes, thirtyMinutes, hourly, threeHours, sixHours, daily

    var id: String { rawValue }

    var seconds: TimeInterval? {
        switch self {
        case .never: nil
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .hourly: 3600
        case .threeHours: 3 * 3600
        case .sixHours: 6 * 3600
        case .daily: 86_400
        }
    }

    var title: String {
        switch self {
        case .never: "Never"
        case .fifteenMinutes: "15 min"
        case .thirtyMinutes: "30 min"
        case .hourly: "Hourly"
        case .threeHours: "3 hours"
        case .sixHours: "6 hours"
        case .daily: "Daily"
        }
    }

    var summary: String {
        switch self {
        case .never: "Stays on cover"
        case .fifteenMinutes: "Every 15 min"
        case .thirtyMinutes: "Every 30 min"
        case .hourly: "Hourly"
        case .threeHours: "Every 3 hours"
        case .sixHours: "Every 6 hours"
        case .daily: "Daily"
        }
    }
}

nonisolated enum PlaybackOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case inOrder, shuffle

    var id: String { rawValue }
    var title: String { self == .inOrder ? "In Order" : "Shuffle" }
}

nonisolated enum TapAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case openApp, nextPhoto

    var id: String { rawValue }
    var title: String { self == .openApp ? "Open App" : "Next Photo" }
}
