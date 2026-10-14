import SwiftUI

/// The rounded silhouette of a widget at any display size.
struct WidgetOutline: Shape {
    var size: WidgetSize

    func path(in rect: CGRect) -> Path {
        let canonical = size.canonicalSize
        let scale = min(rect.width / canonical.width, rect.height / canonical.height)
        return RoundedRectangle(cornerRadius: size.cornerRadius * scale, style: .continuous).path(in: rect)
    }
}

/// A widget exactly as it looks on the Home Screen, drawn from the images the app rendered for it.
struct WidgetPreview: View {
    let widget: PhotoWidgetConfig
    /// The photos on screen, one per collage cell.
    let photos: [WidgetPhoto]
    let size: WidgetSize
    @Environment(AppModel.self) private var model
    @State private var glow: UIImage?

    var body: some View {
        Group {
            if let lead = photos.first {
                WidgetFace(style: widget.style, size: size,
                           appearance: WidgetAppearance(style: widget.style, photo: lead, size: size),
                           glow: glow.map(Image.init(uiImage:)),
                           collage: widget.style.layout.effective(photoCount: photos.count)) { index in
                    if photos.indices.contains(index) {
                        RenderedPhoto(widgetID: widget.id, photo: photos[index], size: size,
                                      generation: model.renderGeneration[widget.id] ?? 0)
                    }
                }
                .task(id: "\(lead.id)\(widget.style.mat)") {
                    glow = widget.style.mat == .glow ? await ImageCache.shared.glow(lead.id) : nil
                }
            } else {
                EmptyWidgetFace(isImporting: (model.importing[widget.id] ?? 0) > 0)
            }
        }
        .aspectRatio(size.canonicalSize.width / size.canonicalSize.height, contentMode: .fit)
        .clipShape(WidgetOutline(size: size))
        .contentShape(WidgetOutline(size: size))
    }
}

/// A widget's final rendered photo, falling back to the thumbnail while rendering is in flight.
struct RenderedPhoto: View {
    let widgetID: UUID
    let photo: WidgetPhoto
    let size: WidgetSize
    let generation: Int
    @State private var image: UIImage?

    var body: some View {
        Color(photo.averageColor)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            // Clipping only hides the overflow of a filled photo; it would still catch taps.
            .contentShape(Rectangle())
            .task(id: "\(photo.id)\(size)\(generation)") {
                var loaded = await ImageCache.shared.render(widget: widgetID, photo: photo.id, size: size, generation: generation)
                if loaded == nil { loaded = await ImageCache.shared.thumbnail(photo.id) }
                withAnimation(.easeOut(duration: 0.25)) { image = loaded }
            }
    }
}

/// Placeholder face for a widget with no photos.
struct EmptyWidgetFace: View {
    var isImporting = false

    var body: some View {
        ZStack {
            SceneArt(kind: .sunset)
                .blur(radius: 18)
                .overlay(Color.black.opacity(0.18))
            VStack(spacing: 6) {
                if isImporting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.title2.weight(.medium))
                }
                isImporting ? Text("Importing…") : Text("No photos yet")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
        }
    }
}

/// A small square photo thumbnail that fades in once decoded.
struct PhotoThumbnail: View {
    let photo: WidgetPhoto
    @State private var image: UIImage?

    var body: some View {
        Color(photo.averageColor)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task(id: photo.id) {
                if let cached = ImageCache.shared.cached("thumb/\(photo.id)") {
                    image = cached
                    return
                }
                let loaded = await ImageCache.shared.thumbnail(photo.id)
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
    }
}

/// A soft wash of a photo's colors behind the content, cross-fading as the photo changes.
struct AmbientBackground: View {
    let photoID: UUID?
    var strength: Double = 1
    @Environment(\.colorScheme) private var colorScheme
    @State private var layers: [Layer] = []

    private struct Layer: Identifiable {
        let id: UUID
        let image: UIImage
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
            ForEach(layers) { layer in
                Image(uiImage: layer.image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 40)
                    .scaleEffect(1.3)
                    .opacity((colorScheme == .dark ? 0.7 : 0.55) * strength)
                    .transition(.opacity)
            }
            (colorScheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.3))
        }
        .clipped()
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .task(id: photoID) {
            guard let photoID, let image = await ImageCache.shared.glow(photoID) else {
                withAnimation(.easeInOut(duration: 0.6)) { layers.removeAll() }
                return
            }
            withAnimation(.easeInOut(duration: 0.7)) {
                layers = [Layer(id: photoID, image: image)]
            }
        }
    }
}
