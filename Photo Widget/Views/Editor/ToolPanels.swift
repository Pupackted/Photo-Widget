import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case crop, filter, frame, caption, timing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crop: String(localized: "Crop")
        case .filter: String(localized: "Filters")
        case .frame: String(localized: "Layout")
        case .caption: String(localized: "Caption")
        case .timing: String(localized: "Timing")
        }
    }

    var symbol: String {
        switch self {
        case .crop: "crop"
        case .filter: "camera.filters"
        case .frame: "square.grid.2x2"
        case .caption: "textformat"
        case .timing: "clock.arrow.2.circlepath"
        }
    }
}

// MARK: - Tool bar

/// The editor's tabs, each with its name so every tool is easy to find. The tint glides to the selected one.
struct ToolBar: View {
    @Binding var selection: EditorTool
    @Namespace private var namespace
    @State private var bounces: [EditorTool: Int] = [:]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EditorTool.allCases) { tool in
                let selected = tool == selection
                Button {
                    bounces[tool, default: 0] += 1
                    withAnimation(.snappySpring) { selection = tool }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .symbolEffect(.bounce, value: bounces[tool, default: 0])
                            .frame(height: 20)
                        Text(tool.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(width: 58, height: 48)
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .background {
                        if selected {
                            Capsule()
                                .fill(.tint)
                                .shadow(color: .accentColor.opacity(0.4), radius: 10, y: 4)
                                .matchedGeometryEffect(id: "tool", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.pressable(scale: 0.9))
                .accessibilityLabel(tool.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(5)
        .glass(.interactive, in: .capsule)
        .haptic(.selection, trigger: selection)
    }
}

// MARK: - Shared bits

private struct PanelButton: View {
    let title: String
    let symbol: String
    var isActive = false
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolEffect(.bounce, value: taps)
                    .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .glass(.interactive, in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.pressable(scale: 0.94))
        .haptic(.impact(weight: .light), trigger: taps)
    }
}

/// A compact glass button showing a setting and its value; tapping opens a menu of choices.
private struct MenuPill<Value: Hashable>: View {
    let title: LocalizedStringKey
    let symbol: String
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
        } label: {
            PillLabel(title: title, symbol: symbol, value: label(selection))
        }
        .buttonStyle(.plain)
        .animation(.snappySpring, value: selection)
        .haptic(.selection, trigger: selection)
    }
}

/// Where the widget's photos come from: picked by hand, an album, or On This Day.
private struct SourcePill: View {
    let source: PhotoSource
    let onChoose: (SourceChoice) -> Void

    private var choice: SourceChoice {
        switch source {
        case .picked: .picked
        case .album: .album
        case .onThisDay: .onThisDay
        }
    }

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { choice }, set: onChoose)) {
                Label("Photos You Choose", systemImage: PhotoSource.picked.symbol).tag(SourceChoice.picked)
                Label("Sync an Album", systemImage: "rectangle.stack").tag(SourceChoice.album)
                Label("On This Day", systemImage: "calendar.badge.clock").tag(SourceChoice.onThisDay)
            } label: {
                Text("Photos from")
            }
            if choice == .album {
                Button("Choose Another Album", systemImage: "rectangle.stack.badge.plus") { onChoose(.album) }
            }
        } label: {
            PillLabel(title: "Photos from", symbol: source.symbol, value: source.title)
        }
        .buttonStyle(.plain)
        .animation(.snappySpring, value: source)
    }
}

private struct PillLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .contentTransition(.interpolate)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .glass(.interactive, in: .rect(cornerRadius: 18))
    }
}

// MARK: - Crop

struct CropPanel: View {
    let photo: WidgetPhoto?
    let size: WidgetSize
    let slotAspect: Double
    let setCrop: (CropState?) -> Void
    let applyToAllSizes: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                PanelButton(title: "Smart Frame", symbol: "sparkles", isActive: isAuto) {
                    withAnimation(.morph) { setCrop(nil) }
                }
                PanelButton(title: "Center", symbol: "viewfinder") {
                    withAnimation(.morph) { setCrop(CropState(centerX: 0.5, centerY: 0.5, zoom: 1)) }
                }
                PanelButton(title: "All Sizes", symbol: "square.on.square") {
                    applyToAllSizes()
                }
            }
            .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Image(systemName: "minus.magnifyingglass")
                Slider(value: zoomBinding, in: CropState.minZoom...CropState.maxZoom)
                Image(systemName: "plus.magnifyingglass")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)

            Label(isAuto ? "Framed around what matters in the photo" : "Pinch, drag or double-tap the photo",
                  systemImage: isAuto ? "sparkles" : "hand.draw")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .disabled(photo == nil)
        .animation(.snappySpring, value: isAuto)
    }

    private var isAuto: Bool { !(photo?.hasCustomCrop(for: size) ?? false) }

    private var zoomBinding: Binding<Double> {
        Binding {
            photo?.crop(for: size).clamped(imageAspect: photo?.aspect ?? 1, targetAspect: slotAspect).zoom ?? 1
        } set: { zoom in
            guard let photo else { return }
            var crop = photo.crop(for: size)
            crop.zoom = zoom
            setCrop(crop.clamped(imageAspect: photo.aspect, targetAspect: slotAspect))
        }
    }
}

// MARK: - Filters

struct FilterPanel: View {
    let photo: WidgetPhoto?
    @Binding var style: WidgetStyle

    var body: some View {
        VStack(spacing: 14) {
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(PhotoFilter.allCases) { filter in
                            FilterSwatch(filter: filter, photo: photo, isSelected: style.filter == filter) {
                                withAnimation(.snappySpring) {
                                    style.filter = filter
                                    style.filterIntensity = 1
                                }
                            }
                            .id(filter)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .onAppear { reader.scrollTo(style.filter, anchor: .center) }
            }

            if style.filter != .original {
                HStack(spacing: 12) {
                    Text("Intensity")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Slider(value: $style.filterIntensity, in: 0...1)
                    Text("\(Int((style.filterIntensity * 100).rounded()))")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .frame(width: 34, alignment: .trailing)
                        .contentTransition(.numericText(value: style.filterIntensity))
                }
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .haptic(.selection, trigger: style.filter)
    }
}

private struct FilterSwatch: View {
    let filter: PhotoFilter
    let photo: WidgetPhoto?
    let isSelected: Bool
    let action: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
                    } else {
                        Color.secondary.opacity(0.2)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(3)
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(.tint, lineWidth: isSelected ? 2.5 : 0)
                }
                .scaleEffect(isSelected ? 1.04 : 1)

                Text(filter.title)
                    .font(.caption.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
        }
        .buttonStyle(.pressable(scale: 0.92))
        .task(id: photo?.id) {
            guard let photo else { return }
            let loaded = await ImageCache.shared.swatch(photo.id, filter: filter)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
        .accessibilityLabel(filter.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Frame

struct FramePanel: View {
    let photo: WidgetPhoto?
    let photoCount: Int
    @Binding var style: WidgetStyle
    @State private var glow: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ChipPicker(options: CollageLayout.allCases, selection: $style.layout, title: \.title,
                           symbol: \.symbol, isEnabled: { photoCount >= $0.cellCount })

                HStack(spacing: 10) {
                    ForEach(FrameStyle.allCases) { frame in
                        FrameOption(frame: frame, isSelected: style.frame == frame, photo: photo) {
                            withAnimation(.morph) { style.frame = frame }
                        }
                    }
                }
                .padding(.horizontal, 20)

                ZStack {
                    if style.frame == .fullBleed {
                        Label("Add a border to choose its color", systemImage: "square.dashed")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    } else {
                        matSwatches
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .frame(height: 48)

                // Tinted Home Screens arrived in iOS 18.
                if #available(iOS 18.0, *) {
                    Toggle(isOn: $style.fullColorInTintedMode) {
                        Label("Keep colors on tinted Home Screen", systemImage: "paintpalette")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .haptic(.selection, trigger: style.frame)
        .haptic(.selection, trigger: style.mat)
        .task(id: photo?.id) {
            guard let photo else { return }
            glow = await ImageCache.shared.glow(photo.id)
        }
    }

    private var matSwatches: some View {
        HStack(spacing: 12) {
            ForEach(MatStyle.allCases) { mat in
                let selected = style.mat == mat
                Button {
                    withAnimation(.snappySpring) { style.mat = mat }
                } label: {
                    swatchFill(mat)
                        .frame(width: 34, height: 34)
                        .clipShape(Circle())
                        .contentShape(Circle())
                        .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                        .padding(4)
                        .overlay(Circle().strokeBorder(.tint, lineWidth: selected ? 2.5 : 0))
                        .scaleEffect(selected ? 1.06 : 1)
                }
                .buttonStyle(.pressable(scale: 0.88))
                .accessibilityLabel(mat.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func swatchFill(_ mat: MatStyle) -> some View {
        let colors = WidgetAppearance.matColors(mat, average: photo?.averageColor)
        switch mat {
        case .glow:
            Color(colors.mat)
                .overlay {
                    if let glow {
                        Image(uiImage: glow).resizable().scaledToFill().scaleEffect(1.6).blur(radius: 2)
                    }
                }
                .overlay(Image(systemName: "sparkle").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
        case .auto:
            Color(colors.mat)
                .overlay(Image(systemName: "wand.and.stars").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(colors.ink)))
        default:
            Color(colors.mat)
        }
    }
}

private struct FrameOption: View {
    let frame: FrameStyle
    let isSelected: Bool
    let photo: WidgetPhoto?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                diagram
                    .frame(width: 44, height: 44)
                Text(frame.title)
                    .font(.caption.weight(isSelected ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.tint, lineWidth: isSelected ? 2 : 0)
            }
            .glass(.interactive, in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.pressable(scale: 0.94))
        .accessibilityLabel(frame.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var diagram: some View {
        let layout = WidgetLayout(bounds: CGSize(width: 44, height: 44), size: .small, frame: frame)
        let tone = photo.map { Color($0.averageColor) } ?? .orange
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: layout.outerRadius, style: .continuous)
                .fill(.white.opacity(0.9))
            RoundedRectangle(cornerRadius: layout.photoRadius, style: .continuous)
                .fill(LinearGradient(colors: [tone.opacity(0.7), tone], startPoint: .top, endPoint: .bottom))
                .frame(width: layout.photoRect.width, height: layout.photoRect.height)
                .offset(x: layout.photoRect.minX, y: layout.photoRect.minY)
        }
        .clipShape(RoundedRectangle(cornerRadius: layout.outerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }
}

// MARK: - Caption

struct CaptionPanel: View {
    let photo: WidgetPhoto?
    @Binding var style: WidgetStyle
    /// The selected photo's own caption, for "Per Photo".
    let photoCaption: Binding<String>?
    @FocusState private var editing: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ChipPicker(options: CaptionMode.allCases, selection: $style.caption, title: \.title)

                Group {
                    switch style.caption {
                    case .none:
                        Label("Add a caption, the date or a day counter", systemImage: "text.bubble")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    case .text:
                        captionField("Write a caption", text: $style.captionText)
                    case .perPhoto:
                        if let photoCaption {
                            captionField("Caption for this photo", text: photoCaption)
                        }
                    case .date, .timeAgo:
                        if photo != nil, photo?.dateTaken == nil {
                            Label("This photo doesn't include a date", systemImage: "calendar.badge.exclamationmark")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            fontPicker
                        }
                    case .counter:
                        counterFields
                    }
                }
                .frame(minHeight: 44)
                .transition(.opacity)

                if [.text, .perPhoto, .counter].contains(style.caption) {
                    fontPicker
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .animation(.snappySpring, value: style.caption)
        .onChange(of: style.caption) { _, mode in
            if mode == .text, style.captionText.isEmpty { editing = true }
            if mode == .perPhoto, photoCaption?.wrappedValue.isEmpty == true { editing = true }
        }
    }

    private func captionField(_ prompt: LocalizedStringKey, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .focused($editing)
            .submitLabel(.done)
            .font(.body.weight(.medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .glass(.interactive, in: .capsule)
            .padding(.horizontal, 20)
    }

    /// The day to count from or to, and the words after the number.
    private var counterFields: some View {
        let future = Calendar.current.startOfDay(for: style.countDate) > Calendar.current.startOfDay(for: .now)
        let prompt: LocalizedStringKey = future ? "e.g. our trip" : "e.g. together"
        return HStack(spacing: 10) {
            DatePicker("Day", selection: $style.countDate, displayedComponents: .date)
                .labelsHidden()
            TextField(prompt, text: $style.countLabel)
                .focused($editing)
                .submitLabel(.done)
                .font(.body.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glass(.interactive, in: .capsule)
        }
        .padding(.horizontal, 20)
    }

    private var fontPicker: some View {
        HStack(spacing: 8) {
            ForEach(CaptionFont.allCases) { font in
                let selected = style.font == font
                Button {
                    withAnimation(.snappySpring) { style.font = font }
                } label: {
                    Text("Aa")
                        .font(font.font(size: 17))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .background(Capsule().fill(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear)))
                        .glass(selected ? .none : .interactive, in: .capsule)
                }
                .buttonStyle(.pressable(scale: 0.9))
                .accessibilityLabel("\(font.title) font")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 20)
        .haptic(.selection, trigger: style.font)
    }
}

// MARK: - Timing

struct TimingPanel: View {
    @Binding var widget: PhotoWidgetConfig
    let onChooseSource: (SourceChoice) -> Void

    private var rotates: Bool { widget.photos.count > 1 }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SourcePill(source: widget.source, onChoose: onChooseSource)
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Change photo")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        nextChangeLabel
                    }
                    .padding(.horizontal, 20)
                    ChipPicker(options: RotationInterval.allCases, selection: $widget.rotation, title: \.title, isEnabled: { _ in rotates })
                }

                HStack(spacing: 10) {
                    MenuPill(title: "Order", symbol: widget.order == .shuffle ? "shuffle" : "arrow.right",
                             options: PlaybackOrder.allCases, selection: $widget.order, label: \.title)
                    MenuPill(title: "Tap widget to", symbol: widget.tapAction == .nextPhoto ? "hand.tap" : "arrow.up.forward.app",
                             options: TapAction.allCases, selection: $widget.tapAction, label: \.title)
                }
                .padding(.horizontal, 20)
                .disabled(!rotates)
                .opacity(rotates ? 1 : 0.45)
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var nextChangeLabel: some View {
        if rotates, widget.rotation != .never {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if let next = PhotoSchedule.nextChange(after: context.date, interval: widget.rotation) {
                    Text("Next \(next, format: .relative(presentation: .named))")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.tint)
                        .contentTransition(.numericText())
                }
            }
        } else if !rotates {
            Text("Add more photos to rotate")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }
}
