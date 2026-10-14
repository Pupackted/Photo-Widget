import SwiftUI

// MARK: - Layout

/// Geometry of a widget face for a given frame style. The app renders images with the exact
/// photo aspect this produces, and the widget and the in-app previews lay out with it, so all
/// three always line up.
nonisolated struct WidgetLayout {
    let bounds: CGSize
    let scale: CGFloat
    let outerRadius: CGFloat
    let photoRect: CGRect
    let captionRect: CGRect
    let photoRadius: CGFloat
    let captionPointSize: CGFloat
    /// One rectangle per photo, relative to `photoRect`. A single photo fills it.
    let cells: [CGRect]
    let cellRadius: CGFloat

    init(bounds: CGSize, size: WidgetSize, frame: FrameStyle, collage: CollageLayout = .single) {
        let canonical = size.canonicalSize
        let scale = max(min(bounds.width / canonical.width, bounds.height / canonical.height), 0.01)
        let roomy = size == .large || size == .extraLarge

        var insets = EdgeInsets()
        switch frame {
        case .fullBleed:
            break
        case .border:
            let inset = (roomy ? 12 : 10) * scale
            insets = EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset)
        case .polaroid:
            let inset = (roomy ? 12 : 10) * scale
            insets = EdgeInsets(top: inset, leading: inset, bottom: (roomy ? 40 : 30) * scale, trailing: inset)
        }

        self.bounds = bounds
        self.scale = scale
        self.outerRadius = size.cornerRadius * scale
        self.photoRect = CGRect(
            x: insets.leading,
            y: insets.top,
            width: max(bounds.width - insets.leading - insets.trailing, 1),
            height: max(bounds.height - insets.top - insets.bottom, 1)
        )
        self.captionRect = CGRect(x: insets.leading, y: photoRect.maxY, width: photoRect.width, height: insets.bottom)
        self.photoRadius = switch frame {
        case .fullBleed: 0
        case .border: max(outerRadius - insets.top, 4 * scale)
        case .polaroid: 5 * scale
        }
        self.captionPointSize = size.captionPointSize * scale
        self.cells = Self.cells(in: photoRect.size, collage: collage, gap: (frame == .fullBleed ? 3 : 6) * scale)
        self.cellRadius = collage == .single || frame == .fullBleed ? 0 : 4 * scale
    }

    /// Layout at the reference size a widget image is rendered for.
    static func canonical(_ size: WidgetSize, frame: FrameStyle, collage: CollageLayout = .single) -> WidgetLayout {
        WidgetLayout(bounds: size.canonicalSize, size: size, frame: frame, collage: collage)
    }

    /// Aspect ratio of each photo. Every cell in a collage has the same shape, so a photo
    /// rendered once fits whichever cell it lands in.
    var photoAspect: Double { cells[0].width / cells[0].height }

    /// Two photos split along the longer side; four make a grid.
    private static func cells(in area: CGSize, collage: CollageLayout, gap: CGFloat) -> [CGRect] {
        let w = area.width, h = area.height
        switch collage {
        case .single:
            return [CGRect(origin: .zero, size: area)]
        case .duo where h > w:
            let half = max((h - gap) / 2, 1)
            return [CGRect(x: 0, y: 0, width: w, height: half), CGRect(x: 0, y: half + gap, width: w, height: half)]
        case .duo:
            let half = max((w - gap) / 2, 1)
            return [CGRect(x: 0, y: 0, width: half, height: h), CGRect(x: half + gap, y: 0, width: half, height: h)]
        case .quad:
            let cw = max((w - gap) / 2, 1), ch = max((h - gap) / 2, 1)
            return [CGRect(x: 0, y: 0, width: cw, height: ch), CGRect(x: cw + gap, y: 0, width: cw, height: ch),
                    CGRect(x: 0, y: ch + gap, width: cw, height: ch), CGRect(x: cw + gap, y: ch + gap, width: cw, height: ch)]
        }
    }
}

// MARK: - Appearance

/// Everything about a face that depends on the photo or the moment it's shown.
struct WidgetAppearance {
    var matColor: Color
    var inkColor: Color
    var caption: String?

    init(style: WidgetStyle, photo: WidgetPhoto?, size: WidgetSize, date: Date = .now) {
        let (mat, ink) = Self.matColors(style.mat, average: photo?.averageColor)
        matColor = Color(mat)
        inkColor = Color(ink)
        caption = Self.captionText(style: style, photo: photo, size: size, date: date)
    }

    static func matColors(_ mat: MatStyle, average: RGBColor?) -> (mat: RGBColor, ink: RGBColor) {
        let base = average ?? RGBColor(red: 0.6, green: 0.6, blue: 0.62)
        let hsb = base.hsb
        switch mat {
        case .auto:
            return (RGBColor(hue: hsb.hue, saturation: min(hsb.saturation * 0.45, 0.22), brightness: 0.95),
                    RGBColor(hue: hsb.hue, saturation: min(hsb.saturation, 0.5), brightness: 0.26))
        case .glow:
            return (RGBColor(hue: hsb.hue, saturation: min(hsb.saturation * 1.1, 0.8), brightness: hsb.brightness * 0.55),
                    RGBColor(red: 1, green: 1, blue: 1))
        case .white:
            return (RGBColor(red: 1, green: 1, blue: 1), RGBColor(red: 0.11, green: 0.11, blue: 0.12))
        case .paper:
            return (RGBColor(red: 0.96, green: 0.94, blue: 0.89), RGBColor(red: 0.27, green: 0.23, blue: 0.19))
        case .charcoal:
            return (RGBColor(red: 0.14, green: 0.14, blue: 0.15), RGBColor(red: 0.93, green: 0.92, blue: 0.9))
        case .black:
            return (RGBColor(red: 0, green: 0, blue: 0), RGBColor(red: 0.92, green: 0.92, blue: 0.92))
        }
    }

    static func captionText(style: WidgetStyle, photo: WidgetPhoto?, size: WidgetSize, date: Date) -> String? {
        switch style.caption {
        case .none:
            return nil
        case .text:
            let text = style.captionText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        case .date:
            guard let taken = photo?.dateTaken else { return nil }
            return size == .small
                ? taken.formatted(.dateTime.month(.abbreviated).day().year())
                : taken.formatted(date: .long, time: .omitted)
        case .perPhoto:
            let text = photo?.caption.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        case .timeAgo:
            guard let taken = photo?.dateTaken else { return nil }
            let calendar = Calendar.current
            if calendar.isDate(taken, inSameDayAs: date) { return String(localized: "Today") }
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            formatter.unitsStyle = .full
            // Whole days, so a photo from this date in 2019 reads "7 years ago" all day, not "6 years ago" until the hour it was taken.
            let text = formatter.localizedString(for: calendar.startOfDay(for: taken), relativeTo: calendar.startOfDay(for: date))
            return text.prefix(1).uppercased() + text.dropFirst()
        case .counter:
            return counterText(to: style.countDate, label: style.countLabel, on: date)
        }
    }

    /// "12 days until Bali", "1204 days together", "Today".
    static func counterText(to target: Date, label: String, on date: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: target)).day ?? 0
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if days > 0 {
            return label.isEmpty ? String(localized: "\(days) days to go") : String(localized: "\(days) days until \(label)")
        }
        if days < 0 {
            let elapsed = -days
            return label.isEmpty ? String(localized: "\(elapsed) days") : String(localized: "\(elapsed) days \(label)")
        }
        return label.isEmpty ? String(localized: "Today") : String(localized: "Today · \(label)")
    }
}

extension Color {
    init(_ rgb: RGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension CaptionFont {
    func font(size: CGFloat) -> Font {
        switch self {
        case .system: .system(size: size, weight: .semibold)
        case .rounded: .system(size: size, weight: .semibold, design: .rounded)
        case .serif: .system(size: size * 1.05, weight: .medium, design: .serif)
        case .mono: .system(size: size * 0.9, weight: .medium, design: .monospaced)
        case .script: .custom("SnellRoundhand-Bold", size: size * 1.35)
        }
    }
}

// MARK: - Face

/// The visual of a widget: mat, photo slot and caption. Shared by the real widget and every
/// preview in the app. The photo itself is supplied by the caller, because the widget shows a
/// pre-rendered image while the editor shows a live, draggable one.
struct WidgetFace<Photo: View>: View {
    var style: WidgetStyle
    var size: WidgetSize
    var appearance: WidgetAppearance
    var glow: Image?
    /// Inside a real widget the mat is the container background and corners follow the container shape.
    var isWidget = false
    var collage: CollageLayout = .single
    /// The photo for each collage cell.
    @ViewBuilder var cell: (Int) -> Photo

    init(style: WidgetStyle, size: WidgetSize, appearance: WidgetAppearance, glow: Image? = nil,
         isWidget: Bool = false, collage: CollageLayout, @ViewBuilder cell: @escaping (Int) -> Photo) {
        self.style = style
        self.size = size
        self.appearance = appearance
        self.glow = glow
        self.isWidget = isWidget
        self.collage = collage
        self.cell = cell
    }

    /// A face showing one photo.
    init(style: WidgetStyle, size: WidgetSize, appearance: WidgetAppearance, glow: Image? = nil,
         isWidget: Bool = false, @ViewBuilder photo: @escaping () -> Photo) {
        self.init(style: style, size: size, appearance: appearance, glow: glow, isWidget: isWidget, collage: .single) { _ in photo() }
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = WidgetLayout(bounds: proxy.size, size: size, frame: style.frame, collage: collage)
            ZStack(alignment: .topLeading) {
                if !isWidget {
                    WidgetMat(mat: style.mat, color: appearance.matColor, glow: glow)
                }

                ZStack(alignment: .topLeading) {
                    ForEach(layout.cells.indices, id: \.self) { index in
                        let rect = layout.cells[index]
                        cell(index)
                            .frame(width: rect.width, height: rect.height)
                            .clipShape(RoundedRectangle(cornerRadius: layout.cellRadius, style: .continuous))
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
                .frame(width: layout.photoRect.width, height: layout.photoRect.height, alignment: .topLeading)
                .overlay(alignment: .bottomLeading) {
                    if style.frame != .polaroid, let caption = appearance.caption {
                        overlayCaption(caption, layout: layout)
                    }
                }
                .clipShape(photoShape(layout))
                .offset(x: layout.photoRect.minX, y: layout.photoRect.minY)

                if style.frame == .polaroid, let caption = appearance.caption {
                    Text(caption)
                        .font(style.font.font(size: layout.captionPointSize))
                        .foregroundStyle(appearance.inkColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 2 * layout.scale)
                        .frame(width: layout.captionRect.width, height: layout.captionRect.height, alignment: .leading)
                        .offset(x: layout.captionRect.minX, y: layout.captionRect.minY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private func overlayCaption(_ caption: String, layout: WidgetLayout) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                .frame(height: min(layout.photoRect.height * 0.55, 90 * layout.scale))
                .frame(maxHeight: .infinity, alignment: .bottom)
            Text(caption)
                .font(style.font.font(size: layout.captionPointSize))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 3 * layout.scale, y: 1 * layout.scale)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12 * layout.scale)
                .padding(.bottom, 11 * layout.scale)
        }
        .allowsHitTesting(false)
    }

    private func photoShape(_ layout: WidgetLayout) -> AnyShape {
        switch style.frame {
        case .fullBleed:
            AnyShape(Rectangle())
        case .border where isWidget:
            AnyShape(ContainerRelativeShape())
        case .border, .polaroid:
            AnyShape(RoundedRectangle(cornerRadius: layout.photoRadius, style: .continuous))
        }
    }
}

/// The paper behind the photo.
struct WidgetMat: View {
    var mat: MatStyle
    var color: Color
    var glow: Image?

    var body: some View {
        if mat == .glow, let glow {
            Color.clear
                .overlay { glow.resizable().scaledToFill() }
                .overlay(Color.black.opacity(0.12))
                .clipped()
                .allowsHitTesting(false)
        } else {
            color
        }
    }
}
