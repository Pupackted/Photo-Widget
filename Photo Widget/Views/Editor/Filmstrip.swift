import SwiftUI
import UniformTypeIdentifiers

/// The widget's photos in order. The first one is the cover. Drag a photo to reorder; the
/// selected photo carries a menu with everything else you can do to it. A synced widget's photos
/// follow the library, so they can only be reframed, and the add button becomes "sync now".
struct Filmstrip: View {
    let photos: [WidgetPhoto]
    @Binding var selection: UUID?
    let importingCount: Int
    var isSynced = false
    let onAdd: () -> Void
    let onSync: () -> Void
    let onMove: (_ photo: UUID, _ target: UUID) -> Void
    let onMakeCover: (UUID) -> Void
    let onResetFraming: (UUID) -> Void
    let onRemove: (UUID) -> Void

    @State private var dragging: UUID?
    @State private var width: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var selectedID: UUID? { selection ?? photos.first?.id }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        reorderable(tile(photo, isCover: index == 0, isSelected: photo.id == selectedID), photo: photo)
                            .id(photo.id)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                    ForEach(0..<importingCount, id: \.self) { _ in
                        ShimmerTile()
                            .frame(width: 42, height: 52)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                    if isSynced { syncTile } else { addTile }
                }
                .padding(.horizontal, 20)
                .frame(height: 68)
                // On iPad a few photos sit centered under the preview instead of off in a corner.
                .frame(minWidth: horizontalSizeClass == .regular ? width : 0)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .edgeFade(horizontalSizeClass == .regular)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .onChange(of: selection) { _, id in
                guard let id else { return }
                withAnimation(.snappySpring) { reader.scrollTo(id, anchor: .center) }
            }
        }
        .haptic(.selection, trigger: selection)
        .haptic(.impact(weight: .light), trigger: photos.map(\.id)) { old, new in Set(old) == Set(new) && old != new }
    }

    @ViewBuilder
    private func reorderable(_ tile: some View, photo: WidgetPhoto) -> some View {
        if isSynced {
            tile
        } else {
            tile
                .onDrag {
                    dragging = photo.id
                    return NSItemProvider(object: photo.id.uuidString as NSString)
                } preview: {
                    PhotoThumbnail(photo: photo)
                        .frame(width: 50, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .onDrop(of: [.text], delegate: ReorderDropDelegate(target: photo.id, dragging: $dragging, onMove: onMove))
        }
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
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Menu {
                    actions(for: photo, isCover: isCover)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.primary)
                        .frame(width: 20, height: 20)
                        .background(.regularMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        // A bigger target than it looks.
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .offset(x: 12, y: -12)
                .accessibilityLabel("Photo options")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .contextMenu {
            actions(for: photo, isCover: isCover)
        } preview: {
            PhotoThumbnail(photo: photo)
                .aspectRatio(photo.aspect, contentMode: .fit)
                .frame(width: 280)
        }
        .accessibilityLabel(isCover ? Text("Cover photo") : Text("Photo"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityActions {
            actions(for: photo, isCover: isCover)
        }
    }

    @ViewBuilder
    private func actions(for photo: WidgetPhoto, isCover: Bool) -> some View {
        if !isCover, !isSynced {
            Button("Make Cover", systemImage: "star") { onMakeCover(photo.id) }
        }
        Button("Reset Framing", systemImage: "arrow.counterclockwise") { onResetFraming(photo.id) }
        if !isSynced {
            Divider()
            Button("Remove Photo", systemImage: "trash", role: .destructive) { onRemove(photo.id) }
        }
    }

    private var syncTile: some View {
        Button(action: onSync) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 16, weight: .semibold))
                .symbolEffect(.pulse, isActive: importingCount > 0)
                .frame(width: 42, height: 52)
                .glass(.interactive, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.pressable(scale: 0.88))
        .disabled(importingCount > 0)
        .accessibilityLabel("Sync now")
    }

    private var addTile: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 42, height: 52)
                .glass(.interactive, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.pressable(scale: 0.88))
        .accessibilityLabel("Add photos")
    }
}

/// Reorders live: as a dragged photo passes over another, they swap places.
private struct ReorderDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let onMove: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        onMove(dragging, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
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
