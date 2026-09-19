import SwiftUI

// MARK: - Haptics

private struct HapticModifier<Trigger: Equatable>: ViewModifier {
    let feedback: SensoryFeedback
    let trigger: Trigger
    let condition: (Trigger, Trigger) -> Bool
    @AppStorage("hapticsEnabled") private var enabled = true

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: trigger) { old, new in
            enabled && condition(old, new) ? feedback : nil
        }
    }
}

extension View {
    /// Sensory feedback that respects the in-app haptics setting.
    func haptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T, when condition: @escaping (T, T) -> Bool = { _, _ in true }) -> some View {
        modifier(HapticModifier(feedback: feedback, trigger: trigger, condition: condition))
    }
}

// MARK: - Buttons

/// Squishes on touch-down and springs back — for cards and custom controls.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
    static func pressable(scale: CGFloat) -> PressableStyle { PressableStyle(scale: scale) }
}

// MARK: - Motion

extension Animation {
    static let snappySpring = Animation.spring(response: 0.34, dampingFraction: 0.82)
    static let morph = Animation.spring(response: 0.5, dampingFraction: 0.84)
}

/// Fades, lifts and un-blurs content into place, staggered by `index`.
private struct EntranceModifier: ViewModifier {
    let visible: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 18)
            .blur(radius: visible || reduceMotion ? 0 : 6)
            .animation(.spring(response: 0.7, dampingFraction: 0.84).delay(Double(index) * 0.07), value: visible)
    }
}

extension View {
    func entrance(_ visible: Bool, index: Int = 0) -> some View {
        modifier(EntranceModifier(visible: visible, index: index))
    }
}
