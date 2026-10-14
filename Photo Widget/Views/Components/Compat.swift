import SwiftUI

// The app is designed for Liquid Glass (iOS 26) and falls back to the closest system look on
// iOS 17 and 18, so everything here keeps a single call site for both.

enum GlassStyle {
    /// Plain glass, for surfaces that don't respond to touch.
    case regular
    /// Glass that reacts to touch, for buttons and controls.
    case interactive
    /// See-through glass over rich content.
    case clear
    /// No glass, e.g. a selected chip that's filled with the tint instead.
    case none

    @available(iOS 26.0, *)
    fileprivate var glass: Glass {
        switch self {
        case .regular: .regular
        case .interactive: .regular.interactive()
        case .clear: .clear
        case .none: .identity
        }
    }
}

extension View {
    @ViewBuilder
    func glass<S: Shape>(_ style: GlassStyle = .regular, in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(style.glass, in: shape)
        } else {
            background(style == .none ? AnyShapeStyle(.clear) : AnyShapeStyle(style == .clear ? .ultraThinMaterial : .regularMaterial), in: shape)
                .overlay(shape.stroke(.white.opacity(style == .none ? 0 : 0.18), lineWidth: 0.5))
        }
    }

    /// The app's main call-to-action button.
    @ViewBuilder
    func prominentButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
    }

    /// Content pinned to the bottom edge that scrolling content passes under.
    @ViewBuilder
    func bottomBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let bar = content()
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom) { bar }
        } else {
            safeAreaInset(edge: .bottom) {
                // Without the iOS 26 scroll-edge blur, a bar background keeps content readable underneath.
                bar
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }

    /// Zooms a pushed screen out of the view it was opened from (iOS 18+).
    @ViewBuilder
    func zoomTransition(sourceID: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID, cornerRadius: CGFloat) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self
        }
    }

    /// A periodic nudge on a symbol that wants attention (iOS 18+).
    @ViewBuilder
    func attentionWiggle() -> some View {
        if #available(iOS 18.0, *) {
            symbolEffect(.wiggle, options: .repeat(.periodic(delay: 3)))
        } else {
            self
        }
    }
}

/// Closes a sheet: a checkmark on iOS 26, the word "Done" before that.
struct DoneButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button("Done", systemImage: "checkmark", action: action)
        } else {
            Button(action: action) {
                Text("Done").fontWeight(.semibold)
            }
        }
    }
}
