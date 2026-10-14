import SwiftUI

/// Where the user wants a widget's photos to come from.
enum SourceChoice: Equatable {
    case picked, album, onThisDay
}

extension View {
    /// Turns a source choice into a `PhotoSource`: asks for photo library access when it's needed,
    /// lets the user pick an album, and explains what to do if access was turned down.
    func photoSourceFlow(_ request: Binding<SourceChoice?>, onChoose: @escaping (PhotoSource) -> Void) -> some View {
        modifier(PhotoSourceFlow(request: request, onChoose: onChoose))
    }
}

private struct PhotoSourceFlow: ViewModifier {
    @Binding var request: SourceChoice?
    let onChoose: (PhotoSource) -> Void
    @State private var showsAlbums = false
    @State private var showsDenied = false
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, choice in
                guard let choice else { return }
                request = nil
                guard choice != .picked else { return onChoose(.picked) }
                Task {
                    guard await PhotoLibrarySync.requestAccess() else {
                        showsDenied = true
                        return
                    }
                    if choice == .album { showsAlbums = true } else { onChoose(.onThisDay) }
                }
            }
            .sheet(isPresented: $showsAlbums) {
                AlbumPicker { album in onChoose(.album(id: album.id, title: album.title)) }
            }
            .alert("Allow Access to Photos", isPresented: $showsDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("To sync albums and find On This Day memories, Photo Widget needs access to your photo library. Your photos never leave your device.")
            }
    }
}

/// The user's albums, to keep a widget in step with one.
struct AlbumPicker: View {
    let onPick: (PhotoLibrarySync.Album) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var albums: [PhotoLibrarySync.Album]?

    var body: some View {
        NavigationStack {
            Group {
                if let albums, albums.isEmpty {
                    ContentUnavailableView("No Albums", systemImage: "rectangle.stack",
                                           description: Text("Albums with photos in them show up here."))
                } else if let albums {
                    List {
                        Section {
                            ForEach(albums) { album in
                                Button {
                                    onPick(album)
                                    dismiss()
                                } label: {
                                    AlbumRow(album: album)
                                }
                                .foregroundStyle(.primary)
                            }
                        } footer: {
                            if PhotoLibrarySync.isLimited {
                                Text("Photo Widget can only see the photos you’ve allowed. You can change this in Settings → Privacy & Security → Photos.")
                            } else {
                                Text("The widget shows the album’s newest \(PhotoWidgetConfig.maxPhotos) photos and updates as you add more.")
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Choose an Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                albums = await Task.detached(priority: .userInitiated) { PhotoLibrarySync.albums() }.value
            }
        }
    }
}

private struct AlbumRow: View {
    let album: PhotoLibrarySync.Album
    @State private var cover: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let cover {
                    Image(uiImage: cover).resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.body.weight(.medium))
                Text(album.count == 1 ? String(localized: "1 photo") : String(localized: "\(album.count) photos"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .task(id: album.coverID) {
            guard let id = album.coverID else { return }
            cover = await PhotoLibrarySync.thumbnail(for: id, side: 54 * displayScale)
        }
    }
}
