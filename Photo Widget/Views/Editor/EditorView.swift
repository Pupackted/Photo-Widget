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
    @State private var showsFull = false
    @State private var showsGuide = false
    @State private var confirmsDelete = false
    @State private var sourceRequest: SourceChoice?
    @State private var replacing: SourceChoice?

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
                        sizeRow
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
                    sizeRow
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
        .photosPicker(isPresented: $showsPicker, selection: $pickerItems, maxSelectionCount: max(model.capacity(of: widgetID), 1),
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
        .alert("This widget is full", isPresented: $showsFull) {
            Button("OK") {}
        } message: {
            Text("A widget can hold up to \(PhotoWidgetConfig.maxPhotos) photos. Remove a few, or make another widget.")
        }
        .confirmationDialog("Replace this widget’s photos?",
                            isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }),
                            titleVisibility: .visible, presenting: replacing) { choice in
            Button("Replace Photos", role: .destructive) { sourceRequest = choice }
        } message: { _ in
            Text("Its \(widget.photos.count) photos will be swapped for ones from your library, kept up to date automatically.")
        }
        .photoSourceFlow($sourceRequest) { source in
            withAnimation(.snappySpring) { model.setSource(source, for: widgetID) }
        }
        .confirmationDialog("Delete “\(widget.name)”?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Widget", role: .destructive) { delete() }
        } message: {
            model.widgets.count > 1
                ? Text("Home Screen widgets showing it will switch to one of your other widgets.")
                : Text("Home Screen widgets showing it will be empty until you make a new one.")
        }
    }

    // MARK: - Sections

    private func stage(_ widget: PhotoWidgetConfig, photo: WidgetPhoto?) -> some View {
        EditorStage(
            widget: widget,
            photo: photo,
            others: neighbours(of: photo, in: widget),
            size: size,
            image: photo.flatMap { photo in
                proxy?.photoID == photo.id ? proxy?.image : ImageCache.shared.cached("thumb/\(photo.id)")
            },
            isImporting: (model.importing[widgetID] ?? 0) > 0,
            onCommit: { crop in
                guard let photo else { return }
                model.setCrop(crop, photo: photo.id, size: size, in: widgetID)
            },
            onSelect: { id in
                withAnimation(.snappySpring) { selectedPhotoID = id }
            },
            onAddPhotos: { if widget.isSynced { syncNow() } else { addPhotos() } }
        )
        .overlay(alignment: .top) {
            SyncPill(progress: model.syncing[widgetID])
                .padding(.top, 4)
        }
    }

    /// The size picker, briefly swapped for an Undo button after a photo is removed.
    private var sizeRow: some View {
        let showsUndo = model.recentlyRemoved?.widgetID == widgetID
        return ZStack {
            SizeSwitcher(selection: $size)
                .opacity(showsUndo ? 0 : 1)
                .allowsHitTesting(!showsUndo)
            if showsUndo {
                UndoToast { withAnimation(.snappySpring) { model.undoRemove() } }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.snappySpring, value: showsUndo)
    }

    /// The photos that share the widget with `photo` in a collage, in the order they'd appear.
    private func neighbours(of photo: WidgetPhoto?, in widget: PhotoWidgetConfig) -> [WidgetPhoto] {
        let cells = widget.effectiveLayout.cellCount
        guard cells > 1, let photo, let start = widget.photos.firstIndex(of: photo) else { return [] }
        return (1..<cells).map { widget.photos[(start + $0) % widget.photos.count] }
    }

    private func filmstrip(_ widget: PhotoWidgetConfig) -> some View {
        Filmstrip(
            photos: widget.photos,
            selection: $selectedPhotoID,
            importingCount: model.importing[widgetID] ?? 0,
            isSynced: widget.isSynced,
            onAdd: addPhotos,
            onSync: syncNow,
            onMove: { id, target in
                withAnimation(.snappySpring) { model.movePhoto(id, to: target, in: widgetID) }
            },
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
                    slotAspect: WidgetLayout.canonical(size, frame: widget.wrappedValue.style.frame,
                                                       collage: widget.wrappedValue.effectiveLayout).photoAspect,
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
                FramePanel(photo: photo, photoCount: widget.wrappedValue.photos.count, style: widget.style)
            case .caption:
                CaptionPanel(photo: photo, style: widget.style, photoCaption: photoCaption(photo))
            case .timing:
                TimingPanel(widget: widget, onChooseSource: chooseSource)
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
                if !widget.isSynced {
                    Button("Add Photos", systemImage: "photo.badge.plus", action: addPhotos)
                }
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

    /// Hand-picked photos would be replaced by a synced source, so that asks first.
    private func chooseSource(_ choice: SourceChoice) {
        guard let widget = model.widget(widgetID) else { return }
        if choice != .picked, !widget.isSynced, !widget.photos.isEmpty {
            replacing = choice
        } else {
            sourceRequest = choice
        }
    }

    private func syncNow() {
        Task { await model.sync(widgetID, reportFailures: true) }
    }

    private func addPhotos() {
        if model.capacity(of: widgetID) > 0 {
            showsPicker = true
        } else {
            showsFull = true
        }
    }

    /// Edits go straight to the model, which saves and re-renders in the background.
    private func widgetBinding(_ widget: PhotoWidgetConfig) -> Binding<PhotoWidgetConfig> {
        Binding(
            get: { model.widget(widgetID) ?? widget },
            set: { updated in model.update(widgetID) { $0 = updated } }
        )
    }

    private func photoCaption(_ photo: WidgetPhoto?) -> Binding<String>? {
        guard let photo else { return nil }
        return Binding(
            get: { model.widget(widgetID)?.photo(id: photo.id)?.caption ?? "" },
            set: { model.setCaption($0, photo: photo.id, in: widgetID) }
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

/// "Photo removed · Undo", shown for a few seconds after removing a photo.
private struct UndoToast: View {
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label("Photo removed", systemImage: "trash")
                .font(.footnote.weight(.semibold))
            Button("Undo", action: onUndo)
                .font(.footnote.weight(.bold))
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 9)
        .glass(.regular, in: .capsule)
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
