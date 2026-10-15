import PhotosUI
import StoreKit
import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var zoom

    @State private var path: [UUID] = []
    @State private var showsPicker = false
    @State private var sourceRequest: SourceChoice?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showsSettings = false
    @State private var showsGuide = false
    @State private var renaming: PhotoWidgetConfig?
    @State private var renameText = ""
    @State private var deleting: PhotoWidgetConfig?
    @State private var appeared = false
    @AppStorage("homeTipDismissed") private var tipDismissed = false
    @AppStorage("askedForReview") private var askedForReview = false
    @Environment(\.requestReview) private var requestReview

    private let columns = [GridItem(.adaptive(minimum: 330, maximum: 520), spacing: 22)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 22) {
                    if showsTip {
                        HomeScreenTip(onOpen: { showsGuide = true }, onDismiss: {
                            withAnimation(.snappySpring) { tipDismissed = true }
                        })
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(Array(model.sortedWidgets.enumerated()), id: \.element.id) { index, widget in
                            card(widget)
                                .entrance(appeared, index: index)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 110)
                .animation(.snappySpring, value: model.widgets.map(\.id))
            }
            .scrollIndicators(.hidden)
            .overlay {
                if model.widgets.isEmpty {
                    EmptyLibrary(onChoose: choose)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .background { LibraryBackdrop(colors: model.sortedWidgets.flatMap { $0.photos.prefix(3).map(\.averageColor) }) }
            .navigationTitle(Text(verbatim: "Framed"))
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) {
                if !model.widgets.isEmpty { newWidgetButton }
            }
            .navigationDestination(for: UUID.self) { id in
                EditorView(widgetID: id)
                    .zoomTransition(sourceID: id, in: zoom)
            }
        }
        .photosPicker(isPresented: $showsPicker, selection: $pickerItems, maxSelectionCount: PhotoWidgetConfig.maxPhotos,
                      selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            createWidget(from: items)
        }
        .photoSourceFlow($sourceRequest) { source in createWidget(syncedWith: source) }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .sheet(isPresented: $showsGuide) { AddWidgetGuide() }
        .alert("Rename Widget", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let widget = renaming, !name.isEmpty { model.update(widget.id) { $0.name = name } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Widget", role: .destructive) {
                if let widget = deleting { withAnimation(.snappySpring) { model.delete(widget.id) } }
            }
        } message: {
            model.widgets.count > 1
                ? Text("Home Screen widgets showing it will switch to one of your other widgets.")
                : Text("Home Screen widgets showing it will be empty until you make a new one.")
        }
        .task {
            appeared = true
            await model.refreshPlacedWidgets()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await model.refreshPlacedWidgets()
                await model.syncAll()
            }
        }
        .onChange(of: model.placedWidgetIDs.isEmpty) { _, isEmpty in
            // Their widget made it to the Home Screen: a good moment to ask, once.
            guard !isEmpty, !askedForReview else { return }
            askedForReview = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                requestReview()
            }
        }
        .onChange(of: model.pendingRoute, initial: true) { _, route in
            guard let route else { return }
            model.pendingRoute = nil
            switch route {
            case .widget(let id): path = [id]
            case .newWidget: path = []; showsPicker = true
            }
        }
    }

    private var showsTip: Bool {
        !tipDismissed && !model.widgets.isEmpty && model.placedWidgetIDs.isEmpty
    }

    // MARK: - Pieces

    private func card(_ widget: PhotoWidgetConfig) -> some View {
        NavigationLink(value: widget.id) {
            WidgetCard(widget: widget, isOnHomeScreen: model.placedWidgetIDs.contains(widget.id))
        }
        .buttonStyle(.pressable(scale: 0.97))
        .zoomSource(id: widget.id, in: zoom, cornerRadius: 32)
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                renameText = widget.name
                renaming = widget
            }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                withAnimation(.snappySpring) { _ = model.duplicate(widget.id) }
            }
            Button("Add to Home Screen", systemImage: "apps.iphone.badge.plus") { showsGuide = true }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = widget }
        }
        .scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.93)
                .opacity(phase.isIdentity ? 1 : 0.6)
        }
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    private var newWidgetButton: some View {
        Menu {
            Button("Choose Photos", systemImage: "photo.on.rectangle.angled") { choose(.picked) }
            Button("Sync an Album", systemImage: "rectangle.stack") { choose(.album) }
            Button("On This Day", systemImage: "calendar.badge.clock") { choose(.onThisDay) }
        } label: {
            Label("New Widget", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .prominentButtonStyle()
        .controlSize(.large)
        .padding(.bottom, 8)
        .transition(.scale.combined(with: .opacity))
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Settings", systemImage: "gearshape") { showsSettings = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("How to Add a Widget", systemImage: "apps.iphone.badge.plus") { showsGuide = true }
        }
    }

    private func choose(_ choice: SourceChoice) {
        if choice == .picked { showsPicker = true } else { sourceRequest = choice }
    }

    private func createWidget(from items: [PhotosPickerItem]) {
        let id = withAnimation(.snappySpring) { model.createWidget() }
        model.importPhotos(items, into: id)
        pickerItems = []
        open(id)
    }

    private func createWidget(syncedWith source: PhotoSource) {
        open(withAnimation(.snappySpring) { model.createSyncedWidget(source) })
    }

    private func open(_ id: UUID) {
        Task {
            // Let the new card land before zooming into it.
            try? await Task.sleep(for: .milliseconds(420))
            path.append(id)
        }
    }
}

// MARK: - Supporting views

private struct HomeScreenTip: View {
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                Image(systemName: "apps.iphone.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .attentionWiggle()
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Put it on your Home Screen")
                        .font(.subheadline.weight(.semibold))
                    Text(AddWidgetGuide.shortInstructions)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.pressable(scale: 0.85))
                .accessibilityLabel("Dismiss")
            }
            .padding(16)
            .glass(.interactive, in: .rect(cornerRadius: 24))
        }
        .buttonStyle(.pressable(scale: 0.98))
        .foregroundStyle(.primary)
    }
}

private struct EmptyLibrary: View {
    let onChoose: (SourceChoice) -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 26) {
            WidgetCollage(appeared: appeared)
                .frame(maxWidth: 340)

            VStack(spacing: 10) {
                Text("Make your first widget")
                    .font(.system(.title, design: .serif, weight: .semibold))
                    .entrance(appeared, index: 2)
                Text("Pick a few favorite photos and we’ll frame them beautifully for your Home Screen.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .entrance(appeared, index: 3)
            }
            .padding(.horizontal, 36)

            VStack(spacing: 14) {
                Button {
                    onChoose(.picked)
                } label: {
                    Label("Choose Photos", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .prominentButtonStyle()
                .controlSize(.large)

                HStack(spacing: 10) {
                    secondary("Sync an Album", symbol: "rectangle.stack") { onChoose(.album) }
                    secondary("On This Day", symbol: "calendar.badge.clock") { onChoose(.onThisDay) }
                }
            }
            .entrance(appeared, index: 4)
        }
        .padding(.bottom, 40)
        .onAppear { appeared = true }
    }

    private func secondary(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glass(.interactive, in: .capsule)
        }
        .buttonStyle(.pressable(scale: 0.94))
        .foregroundStyle(.primary)
    }
}

/// A slow-drifting wash of the colors in the user's photos.
private struct LibraryBackdrop: View {
    let colors: [RGBColor]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: [Color] {
        let base = colors.isEmpty
            ? [RGBColor(red: 1, green: 0.62, blue: 0.45), RGBColor(red: 0.72, green: 0.6, blue: 1), RGBColor(red: 0.5, green: 0.78, blue: 1)]
            : Array(colors.prefix(4))
        let tones = base.map { rgb -> Color in
            let hsb = rgb.hsb
            return Color(RGBColor(hue: hsb.hue, saturation: max(hsb.saturation, 0.45), brightness: 0.95))
        }
        return (0..<9).map { tones[($0 * 2) % tones.count] }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
            if #available(iOS 18.0, *) {
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5 + 0.12 * sin(t * 0.21), 0], [1, 0],
                    [0, 0.5 + 0.1 * cos(t * 0.17)], [0.5 + 0.16 * sin(t * 0.13), 0.45 + 0.14 * cos(t * 0.19)], [1, 0.5 + 0.1 * sin(t * 0.23)],
                    [0, 1], [0.5 + 0.12 * cos(t * 0.15), 1], [1, 1],
                ], colors: palette)
            } else {
                LinearGradient(colors: [palette[0], palette[4], palette[8]],
                               startPoint: UnitPoint(x: 0.5 + 0.3 * Double(sin(t * 0.13)), y: 0),
                               endPoint: UnitPoint(x: 0.5 - 0.3 * Double(sin(t * 0.13)), y: 1))
            }
        }
        .opacity(colorScheme == .dark ? 0.3 : 0.22)
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.2), value: colors)
    }
}
