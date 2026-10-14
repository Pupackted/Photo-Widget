import SwiftUI

/// A Liquid Glass capsule of options with a selection pill that glides between them.
struct GlassSegmented<Value: Hashable, Label: View>: View {
    enum PillStyle { case accent, plain }

    let options: [Value]
    @Binding var selection: Value
    var pill: PillStyle = .plain
    var fillsWidth = false
    @ViewBuilder var label: (Value, Bool) -> Label

    @Namespace private var namespace
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(.snappySpring) { selection = option }
                } label: {
                    label(option, selected)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: fillsWidth ? .infinity : nil)
                        .foregroundStyle(selected && pill == .accent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .background {
                            if selected {
                                selectionPill
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable(scale: 0.92))
            }
        }
        .padding(4)
        .glass(.regular, in: .capsule)
        .haptic(.selection, trigger: selection)
    }

    @ViewBuilder
    private var selectionPill: some View {
        switch pill {
        case .accent:
            Capsule().fill(.tint)
                .shadow(color: .accentColor.opacity(0.35), radius: 8, y: 3)
        case .plain:
            Capsule()
                .fill(.white.opacity(colorScheme == .dark ? 0.2 : 0.95))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.1), radius: 6, y: 2)
        }
    }
}

/// A horizontally scrolling row of glass chips, one of which is selected.
struct ChipPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var symbol: ((Value) -> String)?
    var isEnabled: (Value) -> Bool = { _ in true }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let selected = option == selection
                    Button {
                        withAnimation(.snappySpring) { selection = option }
                    } label: {
                        HStack(spacing: 6) {
                            if let symbol {
                                Image(systemName: symbol(option))
                                    .font(.footnote.weight(.semibold))
                            }
                            Text(title(option))
                        }
                            .font(.subheadline.weight(selected ? .semibold : .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                            .background {
                                Capsule().fill(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                            }
                            .glass(selected ? .none : .interactive, in: .capsule)
                    }
                    .buttonStyle(.pressable(scale: 0.92))
                    .disabled(!isEnabled(option))
                    .opacity(isEnabled(option) ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .haptic(.selection, trigger: selection)
    }
}

/// Tells the user their Home Screen is catching up with their edits, then that it has.
struct SyncPill: View {
    let progress: AppModel.SyncProgress?
    @State private var showsDone = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 7) {
            if let progress {
                ProgressView()
                    .controlSize(.mini)
                Text("Updating widget")
                if progress.total > 1 {
                    Text("\(progress.done)/\(progress.total)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(progress.done)))
                }
            } else if showsDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
                Text("Widget updated")
            }
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .glass(.regular, in: .capsule)
        .opacity(progress != nil || showsDone ? 1 : 0)
        .scaleEffect(progress != nil || showsDone ? 1 : 0.85)
        .animation(.snappySpring, value: progress)
        .animation(.snappySpring, value: showsDone)
        .onChange(of: progress == nil) { _, finished in
            hideTask?.cancel()
            guard finished else {
                showsDone = false
                return
            }
            showsDone = true
            hideTask = Task {
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
                showsDone = false
            }
        }
        .accessibilityElement(children: .combine)
    }
}
