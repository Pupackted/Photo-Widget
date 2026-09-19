import SwiftUI

/// A widget on display: the real thing, floating over a glow of its current photo.
struct WidgetCard: View {
    let widget: PhotoWidgetConfig
    let isOnHomeScreen: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let photo = widget.currentPhoto(at: context.date, offset: WidgetStorage.tapOffset(for: widget.id))

            VStack(alignment: .leading, spacing: 18) {
                WidgetPreview(widget: widget, photo: photo, size: .medium)
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 12)
                    .padding(.horizontal, 6)

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(widget.name)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 0)
                    if isOnHomeScreen {
                        Label("On Home Screen", systemImage: "checkmark")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(.clear, in: .capsule)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 6)
            }
            .padding(18)
            .foregroundStyle(.white)
            .background { CardBackdrop(photoID: photo?.id, fallback: photo?.averageColor) }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the editor")
    }

    private var subtitle: String {
        if let importing = model.importing[widget.id], importing > 0 {
            return "Importing \(importing) photo\(importing == 1 ? "" : "s")…"
        }
        return widget.photos.isEmpty ? "No photos yet" : widget.summary
    }
}

/// Blurred, deepened color from the photo so white text always reads.
private struct CardBackdrop: View {
    let photoID: UUID?
    let fallback: RGBColor?
    @State private var glow: UIImage?

    var body: some View {
        ZStack {
            Color(fallback ?? RGBColor(red: 0.3, green: 0.28, blue: 0.35))
            if let glow {
                Image(uiImage: glow)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 24)
                    .scaleEffect(1.25)
                    .saturation(1.2)
                    .transition(.opacity)
            }
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.42)], startPoint: .top, endPoint: .bottom)
        }
        .task(id: photoID) {
            guard let photoID else { glow = nil; return }
            let image = await ImageCache.shared.glow(photoID)
            withAnimation(.easeInOut(duration: 0.6)) { glow = image }
        }
    }
}
