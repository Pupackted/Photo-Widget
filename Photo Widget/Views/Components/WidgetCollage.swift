import SwiftUI

/// Three sample widgets floating in space — the hero for onboarding and the empty library.
struct WidgetCollage: View {
    var appeared = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Item {
        let scene: SceneKind
        let size: WidgetSize
        let style: WidgetStyle
        let position: CGPoint
        let rotation: Double
        let scale: CGFloat
    }

    private let items: [Item] = [
        Item(scene: .ocean, size: .small,
             style: WidgetStyle(frame: .polaroid, mat: .white, caption: .text, captionText: "Summer ’25", font: .script),
             position: CGPoint(x: 0.28, y: 0.75), rotation: -7, scale: 0.86),
        Item(scene: .night, size: .small,
             style: WidgetStyle(frame: .border, mat: .charcoal),
             position: CGPoint(x: 0.74, y: 0.76), rotation: 6, scale: 0.8),
        Item(scene: .sunset, size: .medium,
             style: WidgetStyle(caption: .text, captionText: "Golden hour", font: .serif),
             position: CGPoint(x: 0.5, y: 0.27), rotation: -2, scale: 0.84),
    ]

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 364
            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        let bob = reduceMotion ? 0 : sin(t * 0.9 + Double(index) * 2.1) * 5
                        let sway = reduceMotion ? 0 : sin(t * 0.6 + Double(index)) * 1.2
                        let canonical = item.size.canonicalSize
                        face(item)
                            .frame(width: canonical.width * unit * item.scale, height: canonical.height * unit * item.scale)
                            .clipShape(WidgetOutline(size: item.size))
                            .shadow(color: .black.opacity(0.28), radius: 22 * unit, y: 14 * unit)
                            .rotationEffect(.degrees(item.rotation + sway))
                            .scaleEffect(appeared ? 1 : 0.6)
                            .opacity(appeared ? 1 : 0)
                            .animation(.spring(response: 0.8, dampingFraction: 0.72).delay(0.12 * Double(index)), value: appeared)
                            .position(x: item.position.x * proxy.size.width, y: item.position.y * proxy.size.height + bob)
                    }
                }
            }
        }
        .aspectRatio(1.12, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func face(_ item: Item) -> some View {
        var appearance = WidgetAppearance(style: item.style, photo: nil, size: item.size)
        let mats = WidgetAppearance.matColors(item.style.mat, average: item.scene.averageColor)
        appearance.matColor = Color(mats.mat)
        appearance.inkColor = Color(mats.ink)
        return WidgetFace(style: item.style, size: item.size, appearance: appearance) {
            SceneArt(kind: item.scene)
        }
    }
}
