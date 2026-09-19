import SwiftUI

/// The live widget preview. Drag anywhere to reposition, pinch to zoom, double-tap to zoom in or
/// out. While a finger is down the rest of the photo shows faintly around the widget, edges
/// rubber-band, and the photo clicks into alignment at the center.
struct EditorStage: View {
    let widget: PhotoWidgetConfig
    let photo: WidgetPhoto?
    let size: WidgetSize
    let image: UIImage?
    let isImporting: Bool
    let onCommit: (CropState) -> Void
    let onAddPhotos: () -> Void

    /// Accumulated, un-clamped framing while the user is touching the photo.
    @State private var raw: CropState?
    @State private var lastTranslation: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1
    @State private var dragging = false
    @State private var pinching = false
    @State private var snappedX = false
    @State private var snappedY = false
    @State private var atLimit = false
    @State private var glow: UIImage?

    private var interacting: Bool { raw != nil }

    var body: some View {
        GeometryReader { proxy in
            let face = faceFrame(in: proxy.size)
            let layout = WidgetLayout(bounds: face.size, size: size, frame: widget.style.frame)
            let slot = layout.photoRect.offsetBy(dx: face.minX, dy: face.minY)

            ZStack(alignment: .topLeading) {
                if let photo {
                    let state = displayedState(photo: photo, slot: slot.size)
                    let placement = Self.placement(state, imageAspect: photo.aspect, slot: slot.size)

                    // The rest of the photo, faintly, while adjusting.
                    photoLayer(photo)
                        .frame(width: placement.size.width, height: placement.size.height)
                        .offset(x: slot.minX + placement.origin.x, y: slot.minY + placement.origin.y)
                        .opacity(interacting ? 0.32 : 0)
                        .allowsHitTesting(false)

                    faceView(photo: photo, placement: placement, face: face)

                    CropGuides(snappedX: snappedX, snappedY: snappedY)
                        .frame(width: slot.width, height: slot.height)
                        .clipShape(RoundedRectangle(cornerRadius: layout.photoRadius, style: .continuous))
                        .offset(x: slot.minX, y: slot.minY)
                        .opacity(interacting ? 1 : 0)
                        .allowsHitTesting(false)

                    zoomBadge(state.zoom)
                        .position(x: face.midX, y: face.minY - 22)
                        .opacity(pinching ? 1 : 0)
                } else {
                    emptyFace
                        .frame(width: face.width, height: face.height)
                        .offset(x: face.minX, y: face.minY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(cropGesture(photo: photo, slot: slot), including: photo == nil ? .subviews : .all)
            .simultaneousGesture(
                SpatialTapGesture(count: 2).onEnded { value in
                    if let photo { doubleTap(at: value.location, photo: photo, slot: slot) }
                },
                including: photo == nil ? .subviews : .all
            )
            .animation(.easeOut(duration: 0.22), value: interacting)
            .animation(.snappySpring, value: pinching)
        }
        .task(id: "\(photo?.id.uuidString ?? "")\(widget.style.mat)") {
            guard let photo, widget.style.mat == .glow else { glow = nil; return }
            glow = await ImageCache.shared.glow(photo.id)
        }
        .haptic(.alignment, trigger: snappedX) { !$0 && $1 }
        .haptic(.alignment, trigger: snappedY) { !$0 && $1 }
        .haptic(.impact(weight: .light, intensity: 0.6), trigger: atLimit) { !$0 && $1 }
        .accessibilityElement(children: photo == nil ? .contain : .ignore)
        .accessibilityLabel("Widget preview")
        .accessibilityHint("Drag to reposition the photo, pinch to zoom.")
        .accessibilityAdjustableAction { direction in
            guard let photo else { return }
            var crop = photo.crop(for: size)
            crop.zoom *= direction == .increment ? 1.25 : 0.8
            let aspect = WidgetLayout.canonical(size, frame: widget.style.frame).photoAspect
            withAnimation(.snappySpring) { onCommit(crop.clamped(imageAspect: photo.aspect, targetAspect: aspect)) }
        }
    }

    // MARK: - Pieces

    private func faceView(photo: WidgetPhoto, placement: Placement, face: CGRect) -> some View {
        WidgetFace(style: widget.style, size: size,
                   appearance: WidgetAppearance(style: widget.style, photo: photo, size: size),
                   glow: glow.map(Image.init(uiImage:))) {
            Color.clear.overlay(alignment: .topLeading) {
                photoLayer(photo)
                    .frame(width: placement.size.width, height: placement.size.height)
                    .offset(x: placement.origin.x, y: placement.origin.y)
            }
        }
        .frame(width: face.width, height: face.height)
        .clipShape(WidgetOutline(size: size))
        .shadow(color: .black.opacity(0.25), radius: 28, y: 16)
        .offset(x: face.minX, y: face.minY)
    }

    @ViewBuilder
    private func photoLayer(_ photo: WidgetPhoto) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
        } else {
            Color(photo.averageColor)
        }
    }

    private var emptyFace: some View {
        Button(action: onAddPhotos) {
            EmptyWidgetFace(isImporting: isImporting)
                .clipShape(WidgetOutline(size: size))
                .shadow(color: .black.opacity(0.2), radius: 24, y: 14)
        }
        .buttonStyle(.pressable)
        .disabled(isImporting)
    }

    private func zoomBadge(_ zoom: Double) -> some View {
        Text(String(format: "%.1f×", zoom))
            .font(.footnote.weight(.semibold).monospacedDigit())
            .contentTransition(.numericText(value: zoom))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Geometry

    private func faceFrame(in available: CGSize) -> CGRect {
        let canonical = size.canonicalSize
        let room = CGSize(width: max(available.width - 40, 60), height: max(available.height - 64, 60))
        let scale = min(room.width / canonical.width, room.height / canonical.height, 1.6)
        let faceSize = CGSize(width: canonical.width * scale, height: canonical.height * scale)
        return CGRect(x: (available.width - faceSize.width) / 2, y: (available.height - faceSize.height) / 2 + 8,
                      width: faceSize.width, height: faceSize.height)
    }

    struct Placement {
        var size: CGSize
        var origin: CGPoint
    }

    /// Where the whole photo sits, relative to the photo slot, for a given framing.
    static func placement(_ state: CropState, imageAspect: Double, slot: CGSize) -> Placement {
        let rect = state.rect(imageAspect: imageAspect, targetAspect: slot.width / slot.height)
        let width = slot.width / rect.width
        let height = slot.height / rect.height
        return Placement(size: CGSize(width: width, height: height), origin: CGPoint(x: -rect.minX * width, y: -rect.minY * height))
    }

    private func committedState(_ photo: WidgetPhoto, slot: CGSize) -> CropState {
        photo.crop(for: size).clamped(imageAspect: photo.aspect, targetAspect: slot.width / slot.height)
    }

    private func displayedState(photo: WidgetPhoto, slot: CGSize) -> CropState {
        guard let raw else { return committedState(photo, slot: slot) }
        return banded(raw, photo: photo, slot: slot).state
    }

    /// Applies rubber-banding past the limits, and magnetic snapping to the center lines.
    private func banded(_ raw: CropState, photo: WidgetPhoto, slot: CGSize) -> (state: CropState, snapX: Bool, snapY: Bool, overshoot: Bool) {
        var zoom = raw.zoom
        if zoom < CropState.minZoom { zoom = CropState.minZoom * pow(zoom / CropState.minZoom, 0.3) }
        if zoom > CropState.maxZoom { zoom = CropState.maxZoom * pow(zoom / CropState.maxZoom, 0.3) }

        let crop = CropState.cropSize(imageAspect: photo.aspect, targetAspect: slot.width / slot.height, zoom: zoom)
        let limitX = clampCenter(raw.centerX, half: crop.width / 2)
        let limitY = clampCenter(raw.centerY, half: crop.height / 2)
        var x = rubberBand(raw.centerX, limit: limitX, dimension: crop.width)
        var y = rubberBand(raw.centerY, limit: limitY, dimension: crop.height)

        let overshoot = abs(raw.centerX - limitX) > 0.0001 || abs(raw.centerY - limitY) > 0.0001
            || raw.zoom < CropState.minZoom - 0.001 || raw.zoom > CropState.maxZoom + 0.001

        var snapX = false, snapY = false
        if crop.width < 0.999, abs(x - 0.5) * slot.width / crop.width < 7, abs(raw.centerX - limitX) < 0.0001 {
            x = 0.5; snapX = true
        }
        if crop.height < 0.999, abs(y - 0.5) * slot.height / crop.height < 7, abs(raw.centerY - limitY) < 0.0001 {
            y = 0.5; snapY = true
        }
        return (CropState(centerX: x, centerY: y, zoom: zoom), snapX, snapY, overshoot)
    }

    private func clampCenter(_ value: Double, half: Double) -> Double {
        half >= 0.5 ? 0.5 : min(max(value, half), 1 - half)
    }

    /// The same resistance curve UIScrollView uses.
    private func rubberBand(_ value: Double, limit: Double, dimension: Double) -> Double {
        let overshoot = value - limit
        guard overshoot != 0 else { return value }
        let banded = (1 - 1 / (abs(overshoot) * 0.55 / dimension + 1)) * dimension
        return limit + (overshoot > 0 ? banded : -banded)
    }

    // MARK: - Gestures

    private func cropGesture(photo: WidgetPhoto?, slot: CGRect) -> some Gesture {
        let drag = DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard let photo else { return }
                begin(photo, slot: slot.size)
                let delta = CGSize(width: value.translation.width - lastTranslation.width,
                                   height: value.translation.height - lastTranslation.height)
                lastTranslation = value.translation
                dragging = true
                if let current = raw {
                    raw = pan(current, by: delta, photo: photo, slot: slot.size)
                    refreshFeedback(photo, slot: slot.size)
                }
            }
            .onEnded { _ in
                lastTranslation = .zero
                dragging = false
                if let photo { finish(photo, slot: slot.size) }
            }

        let pinch = MagnifyGesture(minimumScaleDelta: 0.005)
            .onChanged { value in
                guard let photo else { return }
                begin(photo, slot: slot.size)
                let factor = value.magnification / lastMagnification
                lastMagnification = value.magnification
                pinching = true
                let anchor = CGPoint(x: (value.startLocation.x - slot.minX) / slot.width,
                                     y: (value.startLocation.y - slot.minY) / slot.height)
                if let current = raw {
                    raw = zoom(current, by: factor, anchor: anchor, photo: photo, slot: slot.size)
                    refreshFeedback(photo, slot: slot.size)
                }
            }
            .onEnded { _ in
                lastMagnification = 1
                pinching = false
                if let photo { finish(photo, slot: slot.size) }
            }

        return drag.simultaneously(with: pinch)
    }

    private func begin(_ photo: WidgetPhoto, slot: CGSize) {
        guard raw == nil else { return }
        raw = committedState(photo, slot: slot)
    }

    private func pan(_ state: CropState, by delta: CGSize, photo: WidgetPhoto, slot: CGSize) -> CropState {
        let crop = CropState.cropSize(imageAspect: photo.aspect, targetAspect: slot.width / slot.height, zoom: state.zoom)
        var next = state
        next.centerX -= delta.width * crop.width / slot.width
        next.centerY -= delta.height * crop.height / slot.height
        return next
    }

    /// Zooms so the point under the fingers stays put.
    private func zoom(_ state: CropState, by factor: CGFloat, anchor: CGPoint, photo: WidgetPhoto, slot: CGSize) -> CropState {
        let aspect = slot.width / slot.height
        let rect = state.rect(imageAspect: photo.aspect, targetAspect: aspect)
        let anchor = CGPoint(x: min(max(anchor.x, 0), 1), y: min(max(anchor.y, 0), 1))
        let pinned = CGPoint(x: rect.minX + anchor.x * rect.width, y: rect.minY + anchor.y * rect.height)
        let newZoom = state.zoom * factor
        let crop = CropState.cropSize(imageAspect: photo.aspect, targetAspect: aspect, zoom: newZoom)
        return CropState(centerX: pinned.x - anchor.x * crop.width + crop.width / 2,
                         centerY: pinned.y - anchor.y * crop.height + crop.height / 2,
                         zoom: newZoom)
    }

    private func refreshFeedback(_ photo: WidgetPhoto, slot: CGSize) {
        guard let raw else { return }
        let result = banded(raw, photo: photo, slot: slot)
        if snappedX != result.snapX { snappedX = result.snapX }
        if snappedY != result.snapY { snappedY = result.snapY }
        if atLimit != result.overshoot { atLimit = result.overshoot }
    }

    private func finish(_ photo: WidgetPhoto, slot: CGSize) {
        guard !dragging, !pinching, let current = raw else { return }
        let settled = banded(current, photo: photo, slot: slot).state
            .clamped(imageAspect: photo.aspect, targetAspect: slot.width / slot.height)
        let committed = committedState(photo, slot: slot)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            if settled != committed { onCommit(settled) }
            raw = nil
        }
        snappedX = false
        snappedY = false
        atLimit = false
    }

    private func doubleTap(at location: CGPoint, photo: WidgetPhoto, slot: CGRect) {
        let committed = committedState(photo, slot: slot.size)
        let aspect = slot.width / slot.height
        let target: CropState
        if committed.zoom > 1.05 {
            target = CropState(centerX: committed.centerX, centerY: committed.centerY, zoom: 1)
        } else {
            let anchor = CGPoint(x: (location.x - slot.minX) / slot.width, y: (location.y - slot.minY) / slot.height)
            target = zoom(committed, by: 2.2, anchor: anchor, photo: photo, slot: slot.size)
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            onCommit(target.clamped(imageAspect: photo.aspect, targetAspect: aspect))
        }
    }
}

/// Rule-of-thirds grid, with the center lines lighting up when the photo snaps to them.
private struct CropGuides: View {
    let snappedX: Bool
    let snappedY: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                Path { path in
                    for i in 1...2 {
                        path.move(to: CGPoint(x: w * CGFloat(i) / 3, y: 0))
                        path.addLine(to: CGPoint(x: w * CGFloat(i) / 3, y: h))
                        path.move(to: CGPoint(x: 0, y: h * CGFloat(i) / 3))
                        path.addLine(to: CGPoint(x: w, y: h * CGFloat(i) / 3))
                    }
                }
                .stroke(.white.opacity(0.35), lineWidth: 0.6)

                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 1.5, height: h)
                    .position(x: w / 2, y: h / 2)
                    .opacity(snappedX ? 1 : 0)
                    .scaleEffect(y: snappedX ? 1 : 0.4)
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: w, height: 1.5)
                    .position(x: w / 2, y: h / 2)
                    .opacity(snappedY ? 1 : 0)
                    .scaleEffect(x: snappedY ? 1 : 0.4)
            }
            .animation(.snappySpring, value: snappedX)
            .animation(.snappySpring, value: snappedY)
        }
    }
}
