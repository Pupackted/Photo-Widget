import AppIntents
import WidgetKit
import SwiftUI

// MARK: - Timeline

struct PhotoEntry: TimelineEntry {
    enum Content {
        /// The photos on screen, one per collage cell.
        case photos(PhotoWidgetConfig, [WidgetPhoto])
        /// A widget with no photos yet, or none created at all.
        case empty(PhotoWidgetConfig?)
        /// Shown in the widget gallery before the user has made anything.
        case sample(SceneKind)
    }

    let date: Date
    let content: Content
}

struct PhotoTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PhotoEntry {
        PhotoEntry(date: .now, content: .sample(.sunset))
    }

    func snapshot(for configuration: SelectPhotoWidgetIntent, in context: Context) async -> PhotoEntry {
        let widget = resolve(configuration)
        if let widget, !widget.photos.isEmpty {
            let photos = widget.currentPhotos(offset: WidgetStorage.tapOffset(for: widget.id))
            return PhotoEntry(date: .now, content: .photos(widget, photos))
        }
        return PhotoEntry(date: .now, content: context.isPreview ? .sample(.sunset) : .empty(widget))
    }

    func timeline(for configuration: SelectPhotoWidgetIntent, in context: Context) async -> Timeline<PhotoEntry> {
        guard let widget = resolve(configuration), !widget.photos.isEmpty else {
            return Timeline(entries: [PhotoEntry(date: .now, content: .empty(resolve(configuration)))], policy: .never)
        }

        let offset = WidgetStorage.tapOffset(for: widget.id)
        let dates = PhotoSchedule.timelineDates(for: widget, from: .now)
        let entries = dates.map { date in
            PhotoEntry(date: date, content: .photos(widget, widget.currentPhotos(at: date, offset: offset)))
        }
        return Timeline(entries: entries, policy: dates.count > 1 ? .atEnd : .never)
    }

    private func resolve(_ configuration: SelectPhotoWidgetIntent) -> PhotoWidgetConfig? {
        WidgetStorage.resolve(configuration.widget?.id, in: WidgetStorage.loadWidgets())
    }
}

// MARK: - Views

struct PhotoWidgetView: View {
    let entry: PhotoEntry
    @Environment(\.widgetFamily) private var family

    private var size: WidgetSize {
        switch family {
        case .systemMedium: .medium
        case .systemLarge: .large
        case .systemExtraLarge: .extraLarge
        default: .small
        }
    }

    var body: some View {
        switch entry.content {
        case let .photos(widget, photos):
            PhotoFace(widget: widget, photos: photos, size: size, date: entry.date)
        case let .empty(widget):
            EmptyFace(widget: widget, size: size)
        case let .sample(scene):
            SampleFace(scene: scene, size: size)
        }
    }
}

private struct PhotoFace: View {
    let widget: PhotoWidgetConfig
    let photos: [WidgetPhoto]
    let size: WidgetSize
    let date: Date

    var body: some View {
        let lead = photos.first
        let appearance = WidgetAppearance(style: widget.style, photo: lead, size: size, date: date)
        let glow = widget.style.mat == .glow ? lead.flatMap { UIImage(contentsOfFile: WidgetStorage.glowURL($0.id).path) } : nil

        tappable {
            WidgetFace(style: widget.style, size: size, appearance: appearance, isWidget: true,
                       collage: widget.effectiveLayout) { index in
                if photos.indices.contains(index) {
                    photoImage(photos[index])
                        .id(photos[index].id)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.08)), removal: .opacity))
                }
            }
        }
        .containerBackground(for: .widget) {
            WidgetMat(mat: widget.style.mat, color: appearance.matColor, glow: glow.map { Image(uiImage: $0) })
        }
        .widgetURL(URL(string: "photowidget://widget/\(widget.id.uuidString)"))
    }

    @ViewBuilder
    private func photoImage(_ photo: WidgetPhoto) -> some View {
        let rendered = UIImage(contentsOfFile: WidgetStorage.renderURL(widget: widget.id, photo: photo.id, size: size).path)
        // Fall back to the thumbnail if the app hasn't finished rendering this size yet.
        if let image = rendered ?? UIImage(contentsOfFile: WidgetStorage.thumbnailURL(photo.id).path) {
            Image(uiImage: image)
                .resizable()
                .accentedRendering(fullColor: widget.style.fullColorInTintedMode)
                .scaledToFill()
        } else {
            Color(photo.averageColor)
        }
    }

    @ViewBuilder
    private func tappable<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if widget.tapAction == .nextPhoto, widget.photos.count > widget.effectiveLayout.cellCount {
            Button(intent: NextPhotoIntent(widgetID: widget.id), label: content)
                .buttonStyle(.plain)
        } else {
            content()
        }
    }
}

private extension Image {
    /// On a tinted Home Screen (iOS 18+), either keep the photo's colors or let it take the tint.
    @ViewBuilder
    func accentedRendering(fullColor: Bool) -> some View {
        if #available(iOS 18.0, *) {
            widgetAccentedRenderingMode(fullColor ? .fullColor : .desaturated)
        } else {
            self
        }
    }
}

private struct EmptyFace: View {
    let widget: PhotoWidgetConfig?
    let size: WidgetSize

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: size == .small ? 30 : 34, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
            Text(widget.map { String(localized: "\($0.name) is empty") } ?? String(localized: "Add Photos"))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if size != .small {
                Text("Tap to choose photos in the app")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            SceneArt(kind: .sunset).overlay(Color.black.opacity(0.25))
        }
        .widgetURL(URL(string: widget.map { "photowidget://widget/\($0.id.uuidString)" } ?? "photowidget://new"))
    }
}

private struct SampleFace: View {
    let scene: SceneKind
    let size: WidgetSize

    var body: some View {
        let style = WidgetStyle(caption: .text, captionText: scene.caption, font: .serif)
        let appearance = WidgetAppearance(style: style, photo: nil, size: size)
        WidgetFace(style: style, size: size, appearance: appearance, isWidget: true) {
            SceneArt(kind: scene)
        }
        .containerBackground(for: .widget) { Color.black }
    }
}

// MARK: - Widget

struct PhotoWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetStorage.widgetKind, intent: SelectPhotoWidgetIntent.self, provider: PhotoTimelineProvider()) { entry in
            PhotoWidgetView(entry: entry)
        }
        .configurationDisplayName("Photo")
        .description("Your favorite photos, beautifully framed.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

#Preview(as: .systemSmall) {
    PhotoWidget()
} timeline: {
    PhotoEntry(date: .now, content: .sample(.sunset))
    PhotoEntry(date: .now, content: .sample(.ocean))
}

#Preview(as: .systemMedium) {
    PhotoWidget()
} timeline: {
    PhotoEntry(date: .now, content: .sample(.alpine))
    PhotoEntry(date: .now, content: .empty(nil))
}
