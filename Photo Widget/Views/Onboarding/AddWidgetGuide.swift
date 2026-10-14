import SwiftUI

/// Walks through adding a widget, with a looping animation of it happening.
struct AddWidgetGuide: View {
    @Environment(\.dismiss) private var dismiss

    /// One line for tips. The Home Screen's Edit menu arrived in iOS 18; before that it's a + button.
    static var shortInstructions: LocalizedStringKey {
        if #available(iOS 18.0, *) {
            "Touch and hold the Home Screen, tap Edit, then Add Widget."
        } else {
            "Touch and hold the Home Screen, then tap + in the top corner."
        }
    }

    private var steps: [(symbol: String, text: LocalizedStringKey)] {
        let add: LocalizedStringKey = if #available(iOS 18.0, *) {
            "Tap Edit in the corner, then Add Widget."
        } else {
            "Tap the + button in the top corner."
        }
        return [
            ("hand.tap", "Touch and hold an empty part of your Home Screen until the apps jiggle."),
            ("plus.circle", add),
            ("magnifyingglass", "Search for Photo Widget and pick a size you like."),
            ("slider.horizontal.3", "To choose which widget it shows, touch and hold it, then tap Edit Widget."),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    HomeScreenDemo()
                        .frame(height: 300)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 14) {
                                Text("\(index + 1)")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(.tint))
                                Text(step.text)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 28)

                    Label("Widgets also work in StandBy and on iPad.", systemImage: "lightbulb")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 28)
                }
                .padding(.bottom, 30)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Add to Home Screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    DoneButton { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.regularMaterial)
    }
}

/// A tiny Home Screen: a finger presses, apps jiggle, a photo widget drops into place. Loops.
private struct HomeScreenDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cycle = 6.0
    private let columns = 4
    private let rows = 5
    private let iconColors: [Color] = [
        Color(red: 0.36, green: 0.78, blue: 0.47), Color(red: 1, green: 0.58, blue: 0.3), Color(red: 0.35, green: 0.6, blue: 1),
        Color(red: 1, green: 0.8, blue: 0.3), Color(red: 0.95, green: 0.38, blue: 0.45), Color(red: 0.62, green: 0.48, blue: 0.95),
        Color(red: 0.3, green: 0.8, blue: 0.85), Color(red: 0.55, green: 0.55, blue: 0.6),
    ]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = reduceMotion ? cycle * 0.85 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
            let progress = time / cycle
            let jiggling = progress > 0.22 && progress < 0.8
            let widgetTime = time - cycle * 0.42
            let widgetScale = widgetTime < 0 ? 0 : spring(widgetTime)
            let fade = progress > 0.94 ? max(0, 1 - (progress - 0.94) / 0.06) : 1

            phone {
                GeometryReader { proxy in
                    let inset: CGFloat = 16
                    let icon = (proxy.size.width - inset * 2 - 3 * 12) / 4
                    let rowHeight = icon + 18
                    ForEach(0..<(columns * rows), id: \.self) { index in
                        let column = index % columns, row = index / columns
                        if !(column < 2 && row < 2) {
                            let wobble = jiggling ? sin(context.date.timeIntervalSinceReferenceDate * 24 + Double(index) * 1.7) * 2.4 : 0
                            RoundedRectangle(cornerRadius: icon * 0.24, style: .continuous)
                                .fill(iconColors[index % iconColors.count].gradient)
                                .frame(width: icon, height: icon)
                                .rotationEffect(.degrees(wobble))
                                .position(x: inset + icon / 2 + CGFloat(column) * (icon + 12),
                                          y: 20 + icon / 2 + CGFloat(row) * rowHeight)
                        }
                    }

                    let widgetSide = icon * 2 + 12
                    WidgetFace(style: WidgetStyle(), size: .small,
                               appearance: WidgetAppearance(style: WidgetStyle(), photo: nil, size: .small)) {
                        SceneArt(kind: .sunset)
                    }
                    .frame(width: widgetSide, height: widgetSide)
                    .clipShape(WidgetOutline(size: .small))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
                    .rotationEffect(.degrees(jiggling ? sin(context.date.timeIntervalSinceReferenceDate * 24) * 1.2 : 0))
                    .scaleEffect(widgetScale)
                    .opacity(min(widgetScale * 2, 1) * fade)
                    .position(x: inset + widgetSide / 2, y: 20 + widgetSide / 2)

                    // The finger.
                    let press = progress > 0.06 && progress < 0.24
                    Circle()
                        .fill(.white.opacity(0.55))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .frame(width: 44, height: 44)
                        .scaleEffect(press ? 1 : 0.4)
                        .opacity(press ? 1 : 0)
                        .position(x: proxy.size.width * 0.68, y: proxy.size.height * 0.84)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: press)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func phone<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            SceneArt(kind: .night)
                .overlay(Color.black.opacity(0.1))
            content()
        }
        .frame(width: 230)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 46, topTrailingRadius: 46, style: .continuous))
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: 46, topTrailingRadius: 46, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.85), lineWidth: 7)
        }
        .mask(LinearGradient(colors: [.black, .black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
    }

    /// A springy settle from 0 to 1.
    private func spring(_ t: Double) -> Double {
        1 - exp(-7 * t) * cos(11 * t)
    }
}
