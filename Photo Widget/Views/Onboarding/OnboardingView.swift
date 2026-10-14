import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var appeared = false

    private let features: [(symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey)] = [
        ("photo.stack", "Photos that rotate", "Pick up to 50 photos, sync an album, or relive this day in past years — one at a time or as a collage."),
        ("sparkles", "Smart framing", "Faces and subjects stay in frame at every widget size. Fine-tune with a pinch."),
        ("paintpalette", "Frames, filters & captions", "Give every widget the feel of a printed keepsake, or count the days to something special."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                WidgetCollage(appeared: appeared)
                    .frame(maxWidth: 320)

                Text("Your favorite moments, right on your Home Screen.")
                    .font(.system(size: 29, weight: .semibold, design: .serif))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .entrance(appeared, index: 3)

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: feature.symbol)
                                .font(.title2)
                                .foregroundStyle(.tint)
                                .frame(width: 36)
                                .symbolEffect(.bounce, value: appeared)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(feature.title)
                                    .font(.headline)
                                Text(feature.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .entrance(appeared, index: 4 + index)
                    }
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: 520)
            }
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .bottomBar {
            VStack(spacing: 10) {
                Button(action: onFinish) {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .prominentButtonStyle()
                .controlSize(.large)

                Label("Your photos never leave your device.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 8)
            .frame(maxWidth: 520)
            .entrance(appeared, index: 8)
        }
        .background { OnboardingBackdrop() }
        .onAppear { appeared = true }
    }
}

private struct OnboardingBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(.systemBackground)
            RadialGradient(colors: [Color(red: 1, green: 0.6, blue: 0.45).opacity(0.35), .clear],
                           center: UnitPoint(x: 0.2, y: 0.15), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(red: 0.6, green: 0.5, blue: 1).opacity(0.3), .clear],
                           center: UnitPoint(x: 0.9, y: 0.35), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [Color(red: 0.4, green: 0.75, blue: 1).opacity(0.22), .clear],
                           center: UnitPoint(x: 0.5, y: 0.95), startRadius: 0, endRadius: 460)
        }
        .opacity(colorScheme == .dark ? 0.9 : 1)
        .ignoresSafeArea()
    }
}
