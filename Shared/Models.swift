import Foundation
import CoreGraphics

// MARK: - Widget

/// One widget the user has designed: a set of photos plus how they're framed, styled and rotated.
nonisolated struct PhotoWidgetConfig: Codable, Identifiable, Hashable, Sendable {
    /// Keeps each widget's storage and rendering time reasonable.
    static let maxPhotos = 50

    var id = UUID()
    var name: String
    var photos: [WidgetPhoto] = []
    /// Where the photos come from. Synced widgets refill themselves from the photo library.
    var source: PhotoSource = .picked
    var style = WidgetStyle()
    var rotation: RotationInterval = .hourly
    var order: PlaybackOrder = .inOrder
    var tapAction: TapAction = .openApp
    var createdAt = Date()
    var modifiedAt = Date()

    var coverPhoto: WidgetPhoto? { photos.first }

    /// The layout actually used, which falls back to fewer cells when there aren't enough photos.
    var effectiveLayout: CollageLayout { style.layout.effective(photoCount: photos.count) }

    var remainingCapacity: Int { max(Self.maxPhotos - photos.count, 0) }

    /// Synced widgets manage their own photos, so they can't be added, removed or reordered by hand.
    var isSynced: Bool { source != .picked }

    /// Whether the widget looks different from one day to the next.
    var changesDaily: Bool { style.captionChangesDaily || source == .onThisDay }

    /// The photos eligible on `date`: an On This Day widget shows that day's memories, or the
    /// rest of the week's when that day has none; every other widget shows all of its photos.
    func poolIndices(on date: Date, calendar: Calendar = .current) -> [Int] {
        guard source == .onThisDay else { return Array(photos.indices) }
        let key = PhotoSource.dayKey(for: date, calendar: calendar)
        let today = photos.indices.filter { photos[$0].showOnDay == key }
        return today.isEmpty ? Array(photos.indices) : today
    }

    func photo(id: UUID?) -> WidgetPhoto? {
        guard let id else { return nil }
        return photos.first { $0.id == id }
    }

    /// The photo the widget is showing at `date`, honouring rotation, order and tap-to-advance.
    func currentPhoto(at date: Date = .now, offset: Int = 0) -> WidgetPhoto? {
        currentPhotos(at: date, offset: offset).first
    }

    /// Every photo on screen at `date`, one per collage cell.
    func currentPhotos(at date: Date = .now, offset: Int = 0) -> [WidgetPhoto] {
        PhotoSchedule.indices(for: self, at: date, offset: offset).map { photos[$0] }
    }

    var summary: String {
        let count = photos.count == 1 ? String(localized: "1 photo") : String(localized: "\(photos.count) photos")
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
    /// Shown when the widget's caption is set to "Per Photo".
    var caption = ""
    /// The photo library asset this was imported from, for synced widgets.
    var assetID: String?
    /// For On This Day: the day ("MM-dd") this memory belongs to.
    var showOnDay: String?

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
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        case .extraLarge: String(localized: "Extra Large")
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
    var layout: CollageLayout = .single
    var caption: CaptionMode = .none
    var captionText: String = ""
    var font: CaptionFont = .rounded
    var fullColorInTintedMode = true
    /// The day a "Days" caption counts from (in the past) or down to (in the future).
    var countDate = Calendar.current.startOfDay(for: .now)
    /// Words after the number, e.g. "together" → "1,204 days together".
    var countLabel = ""

    /// Whether the caption's text changes from one day to the next.
    var captionChangesDaily: Bool { caption == .timeAgo || caption == .counter }
}

nonisolated enum PhotoFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case original, vivid, golden, coastal, film, faded, instant, dream, mono, noir

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: String(localized: "Original")
        case .vivid: String(localized: "Vivid")
        case .golden: String(localized: "Golden")
        case .coastal: String(localized: "Coastal")
        case .film: String(localized: "Film")
        case .faded: String(localized: "Faded")
        case .instant: String(localized: "filter.instant", defaultValue: "Instant")
        case .dream: String(localized: "Dream")
        case .mono: String(localized: "filter.mono", defaultValue: "Mono")
        case .noir: String(localized: "Noir")
        }
    }
}

nonisolated enum FrameStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case fullBleed, border, polaroid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullBleed: String(localized: "Full Bleed")
        case .border: String(localized: "Border")
        case .polaroid: String(localized: "frame.instant", defaultValue: "Instant")
        }
    }
}

nonisolated enum MatStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, glow, white, paper, charcoal, black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .glow: String(localized: "Glow")
        case .white: String(localized: "White")
        case .paper: String(localized: "Paper")
        case .charcoal: String(localized: "Charcoal")
        case .black: String(localized: "Black")
        }
    }
}

/// How many photos a widget shows at once.
nonisolated enum CollageLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case single, duo, quad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: String(localized: "Single")
        case .duo: String(localized: "Duo")
        case .quad: String(localized: "Grid")
        }
    }

    var symbol: String {
        switch self {
        case .single: "square"
        case .duo: "square.split.2x1"
        case .quad: "square.grid.2x2"
        }
    }

    var cellCount: Int {
        switch self {
        case .single: 1
        case .duo: 2
        case .quad: 4
        }
    }

    /// A collage never shows the same photo twice, so it shrinks to fit the photos there are.
    func effective(photoCount: Int) -> CollageLayout {
        switch self {
        case .quad where photoCount >= 4: .quad
        case .quad, .duo: photoCount >= 2 ? .duo : .single
        case .single: .single
        }
    }
}

nonisolated enum CaptionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, text, perPhoto, date, timeAgo, counter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: String(localized: "None")
        case .text: String(localized: "Text")
        case .perPhoto: String(localized: "Per Photo")
        case .date: String(localized: "Date")
        case .timeAgo: String(localized: "Time Ago")
        case .counter: String(localized: "Day Counter")
        }
    }
}

nonisolated enum CaptionFont: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, rounded, serif, mono, script

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "Classic")
        case .rounded: String(localized: "Rounded")
        case .serif: String(localized: "Serif")
        case .mono: String(localized: "font.mono", defaultValue: "Mono")
        case .script: String(localized: "Script")
        }
    }
}

// MARK: - Source

nonisolated enum PhotoSource: Codable, Hashable, Sendable {
    /// Photos the user chose with the photo picker.
    case picked
    /// Kept in step with an album in the user's photo library.
    case album(id: String, title: String)
    /// Photos taken on this day in past years, refreshed every day.
    case onThisDay

    var title: String {
        switch self {
        case .picked: String(localized: "Photos You Choose")
        case .album(_, let title): title
        case .onThisDay: String(localized: "On This Day")
        }
    }

    var symbol: String {
        switch self {
        case .picked: "hand.tap"
        case .album: "rectangle.stack"
        case .onThisDay: "calendar.badge.clock"
        }
    }

    /// "10-15" for October 15th, in the user's calendar.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d-%02d", parts.month ?? 0, parts.day ?? 0)
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
        case .never: String(localized: "Never")
        case .fifteenMinutes: String(localized: "15 min")
        case .thirtyMinutes: String(localized: "30 min")
        case .hourly: String(localized: "Hourly")
        case .threeHours: String(localized: "3 hours")
        case .sixHours: String(localized: "6 hours")
        case .daily: String(localized: "Daily")
        }
    }

    var summary: String {
        switch self {
        case .never: String(localized: "Stays on cover")
        case .fifteenMinutes: String(localized: "Every 15 min")
        case .thirtyMinutes: String(localized: "Every 30 min")
        case .hourly: String(localized: "Hourly")
        case .threeHours: String(localized: "Every 3 hours")
        case .sixHours: String(localized: "Every 6 hours")
        case .daily: String(localized: "Daily")
        }
    }
}

nonisolated enum PlaybackOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case inOrder, shuffle

    var id: String { rawValue }
    var title: String { self == .inOrder ? String(localized: "In Order") : String(localized: "Shuffle") }
}

nonisolated enum TapAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case openApp, nextPhoto

    var id: String { rawValue }
    var title: String { self == .openApp ? String(localized: "Open App") : String(localized: "Next Photo") }
}

// MARK: - Decoding

// Every field falls back to its default when it's missing or unreadable, so a library saved by
// an older (or newer) version of the app always loads instead of being thrown away.

extension PhotoWidgetConfig {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = PhotoWidgetConfig(name: "")
        id = try c.decode(UUID.self, forKey: .id)
        name = c.value(.name, default: fallback.name)
        photos = (try? c.decodeIfPresent([Lenient<WidgetPhoto>].self, forKey: .photos))?.compactMap(\.value) ?? []
        source = c.value(.source, default: fallback.source)
        style = c.value(.style, default: fallback.style)
        rotation = c.value(.rotation, default: fallback.rotation)
        order = c.value(.order, default: fallback.order)
        tapAction = c.value(.tapAction, default: fallback.tapAction)
        createdAt = c.value(.createdAt, default: fallback.createdAt)
        modifiedAt = c.value(.modifiedAt, default: fallback.modifiedAt)
    }
}

extension WidgetPhoto {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = WidgetPhoto(pixelWidth: 1, pixelHeight: 1)
        id = try c.decode(UUID.self, forKey: .id)
        pixelWidth = try c.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try c.decode(Int.self, forKey: .pixelHeight)
        focus = c.value(.focus, default: fallback.focus)
        crops = c.value(.crops, default: fallback.crops)
        dateTaken = try? c.decodeIfPresent(Date.self, forKey: .dateTaken)
        averageColor = c.value(.averageColor, default: fallback.averageColor)
        caption = c.value(.caption, default: fallback.caption)
        assetID = try? c.decodeIfPresent(String.self, forKey: .assetID)
        showOnDay = try? c.decodeIfPresent(String.self, forKey: .showOnDay)
    }
}

extension WidgetStyle {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = WidgetStyle()
        filter = c.value(.filter, default: fallback.filter)
        filterIntensity = c.value(.filterIntensity, default: fallback.filterIntensity)
        frame = c.value(.frame, default: fallback.frame)
        mat = c.value(.mat, default: fallback.mat)
        layout = c.value(.layout, default: fallback.layout)
        caption = c.value(.caption, default: fallback.caption)
        captionText = c.value(.captionText, default: fallback.captionText)
        font = c.value(.font, default: fallback.font)
        fullColorInTintedMode = c.value(.fullColorInTintedMode, default: fallback.fullColorInTintedMode)
        countDate = c.value(.countDate, default: fallback.countDate)
        countLabel = c.value(.countLabel, default: fallback.countLabel)
    }
}

/// Decodes an element if it can, so one damaged photo doesn't take the rest of the widget with it.
private nonisolated struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

extension KeyedDecodingContainer {
    nonisolated func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}
