import PhotosUI
import SwiftUI

struct EditorView: View {
    let widgetID: UUID

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var size: WidgetSize = .small
    @State private var selectedPhotoID: UUID?
    @State private var tool: EditorTool = .crop
    @State private var proxy: (photoID: UUID, image: UIImage)?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showsPicker = false
    @State private var showsGuide = false
    @State private var confirmsDelete = false

    var body: some View {
        if let widget = model.widget(widgetID) {
            editor(widget)
        } else {
            Color(.systemBackground)
        }
    }

    private func editor(_ widget: PhotoWidgetConfig) -> some View {
        let photo = widget.photo(id: selectedPhotoID) ?? widget.coverPhoto
        let binding = widgetBinding(widget)

        return Group {
            if horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    VStack(spacing: 16) {
                        stage(widget, photo: photo)
                        SizeSwitcher(selection: $size)
                        filmstrip(widget)
                    }
                    .padding(.bottom, 20)

                    VStack(spacing: 22) {
                        ToolBar(selection: $tool)
                        toolPanel(binding, photo: photo)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(width: 420)
                    .padding(.top, 16)
                }
            } else {
                VStack(spacing: 12) {
                    stage(widget, photo: photo)
                    SizeSwitcher(selection: $size)
                    filmstrip(widget)
                    toolPanel(binding, photo: photo)
                        .frame(height: 176)
                    ToolBar(selection: $tool)
                        .padding(.bottom, 6)
                }
            }
        }
        .background { AmbientBackground(photoID: photo?.id) }
        .navigationTitle(Binding(get: { widget.name }, set: { name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            model.update(widgetID) { $0.name = trimmed }
        }))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .toolbar { toolbar(widget) }
        .task(id: "\(photo?.id.uuidString ?? "")|\(widget.style.filter)|\(widget.style.filterIntensity)") {
            guard let photo else { return }
            if let image = await ImageCache.shared.proxy(photo.id, filter: widget.style.filter, intensity: widget.style.filterIntensity) {
                proxy = (photo.id, image)
            }
        }
        .photosPicker(isPresented: $showsPicker, selection: $pickerItems, maxSelectionCount: 50,
                      selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            model.importPhotos(items, into: widgetID)
            pickerItems = []
        }
        .onChange(of: widget.photos.map(\.id)) { _, ids in
            if let selected = selectedPhotoID, !ids.contains(selected) {
                withAnimation(.snappySpring) { selectedPhotoID = ids.first }
            }
        }
        .sheet(isPresented: $showsGuide) { AddWidgetGuide() }
        .confirmationDialog("Delete “\(widget.name)”?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Widget", role: .destructive) { delete() }
        } message: {
            Text("It will be removed from your Home Screen too.")
        }
    }

    // MARK: - Sections

    private func stage(_ widget: PhotoWidgetConfig, photo: WidgetPhoto?) -> some View {
        EditorStage(
            widget: widget,
            photo: photo,
            size: size,
            image: photo.flatMap { photo in
                proxy?.photoID == photo.id ? proxy?.image : ImageCache.shared.cached("thumb/\(photo.id)")
            },
            isImporting: (model.importing[widgetID] ?? 0) > 0,
            onCommit: { crop in
                guard let photo else { return }
                model.setCrop(crop, photo: photo.id, size: size, in: widgetID)
            },
            onAddPhotos: { showsPicker = true }
        )
        .overlay(alignment: .top) {
            SyncPill(progress: model.syncing[widgetID])
                .padding(.top, 4)
        }
    }

    private func filmstrip(_ widget: PhotoWidgetConfig) -> some View {
        Filmstrip(
            photos: widget.photos,
            selection: $selectedPhotoID,
            importingCount: model.importing[widgetID] ?? 0,
            onAdd: { showsPicker = true },
            onMakeCover: { id in
                withAnimation(.snappySpring) { model.makeCover(id, in: widgetID) }
            },
            onResetFraming: { id in
                withAnimation(.morph) {
                    model.update(widgetID) { widget in
                        guard let index = widget.photos.firstIndex(where: { $0.id == id }) else { return }
                        widget.photos[index].crops = [:]
                    }
                }
            },
            onRemove: { id in
                withAnimation(.snappySpring) { model.removePhoto(id, from: widgetID) }
            }
        )
    }

    @ViewBuilder
    private func toolPanel(_ widget: Binding<PhotoWidgetConfig>, photo: WidgetPhoto?) -> some View {
        ZStack {
            switch tool {
            case .crop:
                CropPanel(
                    photo: photo,
                    size: size,
                    slotAspect: WidgetLayout.canonical(size, frame: widget.wrappedValue.style.frame).photoAspect,
                    setCrop: { crop in
                        guard let photo else { return }
                        model.setCrop(crop, photo: photo.id, size: size, in: widgetID)
                    },
                    applyToAllSizes: {
                        guard let photo else { return }
                        let crop = photo.crop(for: size)
                        model.update(widgetID) { widget in
                            guard let index = widget.photos.firstIndex(where: { $0.id == photo.id }) else { return }
                            for size in WidgetSize.allCases { widget.photos[index].crops[size.rawValue] = crop }
                        }
                    }
                )
            case .filter:
                FilterPanel(photo: photo, style: widget.style)
            case .frame:
                FramePanel(photo: photo, style: widget.style)
            case .caption:
                CaptionPanel(photo: photo, style: widget.style)
            case .timing:
                TimingPanel(widget: widget)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .id(tool)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 14)).combined(with: .scale(scale: 0.98)),
            removal: .opacity.animation(.easeOut(duration: 0.1))
        ))
    }

    @ToolbarContentBuilder
    private func toolbar(_ widget: PhotoWidgetConfig) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Add Photos", systemImage: "photo.badge.plus") { showsPicker = true }
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    withAnimation(.snappySpring) { _ = model.duplicate(widgetID) }
                }
                Button("Add to Home Screen", systemImage: "apps.iphone.badge.plus") { showsGuide = true }
                Divider()
                Button("Delete Widget", systemImage: "trash", role: .destructive) { confirmsDelete = true }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }

    // MARK: - Helpers

    /// Edits go straight to the model, which saves and re-renders in the background.
    private func widgetBinding(_ widget: PhotoWidgetConfig) -> Binding<PhotoWidgetConfig> {
        Binding(
            get: { model.widget(widgetID) ?? widget },
            set: { updated in model.update(widgetID) { $0 = updated } }
        )
    }

    private func delete() {
        let id = widgetID
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.snappySpring) { model.delete(id) }
        }
    }
}

/// Small / Medium / Large, each with a tiny outline of its shape.
struct SizeSwitcher: View {
    @Binding var selection: WidgetSize

    var body: some View {
        GlassSegmented(options: AppModel.renderedSizes, selection: $selection) { size, selected in
            HStack(spacing: 7) {
                SizeGlyph(size: size)
                Text(size.title)
                    .font(.subheadline.weight(selected ? .semibold : .medium))
            }
        }
        .accessibilityLabel("Widget size")
    }
}

private struct SizeGlyph: View {
    let size: WidgetSize

    var body: some View {
        let canonical = size.canonicalSize
        let scale = 15 / max(canonical.width, canonical.height)
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .strokeBorder(lineWidth: 1.6)
            .frame(width: max(canonical.width * scale, 9), height: max(canonical.height * scale, 7))
            .frame(width: 16, height: 16)
    }
}
