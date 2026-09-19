import SwiftUI

/// The widget's photos in order. The first one is the cover.
struct Filmstrip: View {
    let photos: [WidgetPhoto]
    @Binding var selection: UUID?
    let importingCount: Int
    let onAdd: () -> Void
    let onMakeCover: (UUID) -> Void
    let onResetFraming: (UUID) -> Void
    let onRemove: (UUID) -> Void

    private var selectedID: UUID? { selection ?? photos.first?.id }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        tile(photo, isCover: index == 0, isSelected: photo.id == selectedID)
                            .id(photo.id)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                    ForEach(0..<importingCount, id: \.self) { _ in
                        ShimmerTile()
                            .frame(width: 42, height: 52)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                    addTile
                }
                .padding(.horizontal, 20)
                .frame(height: 68)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .onChange(of: selection) { _, id in
                guard let id else { return }
                withAnimation(.snappySpring) { reader.scrollTo(id, anchor: .center) }
            }
        }
        .haptic(.selection, trigger: selection)
    }

    private func tile(_ photo: WidgetPhoto, isCover: Bool, isSelected: Bool) -> some View {
        Button {
            withAnimation(.snappySpring) { selection = photo.id }
        } label: {
            PhotoThumbnail(photo: photo)
                .frame(width: isSelected ? 50 : 42, height: isSelected ? 64 : 52)
                .clipShape(RoundedRectangle(cornerRadius: isSelected ? 12 : 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: isSelected ? 12 : 10, style: .continuous)
                        .strokeBorder(.white, lineWidth: isSelected ? 2.5 : 0)
                }
                .overlay(alignment: .topLeading) {
                    if isCover {
                        Image(systemName: "star.fill")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.white)
                            .padding(3.5)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .shadow(color: .black.opacity(isSelected ? 0.25 : 0.1), radius: isSelected ? 8 : 3, y: isSelected ? 4 : 1)
        }
        .buttonStyle(.pressable(scale: 0.88))
        .contextMenu {
            if !isCover {
                Button("Make Cover", systemImage: "star") { onMakeCover(photo.id) }
            }
            Button("Reset Framing", systemImage: "arrow.counterclockwise") { onResetFraming(photo.id) }
            Divider()
            Button("Remove Photo", systemImage: "trash", role: .destructive) { onRemove(photo.id) }
        } preview: {
            PhotoThumbnail(photo: photo)
                .aspectRatio(photo.aspect, contentMode: .fit)
                .frame(width: 280)
        }
        .accessibilityLabel(isCover ? "Cover photo" : "Photo")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var addTile: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 42, height: 52)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.pressable(scale: 0.88))
        .accessibilityLabel("Add photos")
    }
}

/// A shimmering stand-in for a photo that's still importing.
struct ShimmerTile: View {
    @State private var sweep = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.secondary.opacity(0.25))
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.8)
                        .offset(x: sweep ? proxy.size.width * 1.2 : -proxy.size.width)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { sweep = true }
            }
    }
}
