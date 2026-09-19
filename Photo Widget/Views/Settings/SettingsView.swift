import SwiftUI
import WidgetKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("hasOnboarded") private var hasOnboarded = true
    @State private var showsGuide = false
    @State private var shuffles = 0

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        WidgetFace(style: WidgetStyle(), size: .small,
                                   appearance: WidgetAppearance(style: WidgetStyle(), photo: nil, size: .small)) {
                            SceneArt(kind: .sunset)
                        }
                        .frame(width: 58, height: 58)
                        .clipShape(WidgetOutline(size: .small))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Photo Widget")
                                .font(.title3.weight(.semibold))
                            Text("\(model.widgets.count) widget\(model.widgets.count == 1 ? "" : "s") · \(model.widgets.reduce(0) { $0 + $1.photos.count }) photos")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    Button {
                        showsGuide = true
                    } label: {
                        Label("How to Add a Widget", systemImage: "apps.iphone.badge.plus")
                    }
                    Button {
                        shuffles += 1
                        for widget in model.widgets where widget.photos.count > 1 { WidgetStorage.advance(widget.id) }
                        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.widgetKind)
                    } label: {
                        Label("Shuffle All Widgets Now", systemImage: "shuffle")
                            .symbolEffect(.bounce, value: shuffles)
                    }
                    .haptic(.success, trigger: shuffles)
                } header: {
                    Text("Home Screen")
                } footer: {
                    Text("You can also add “Shuffle Photos” to Control Center, or ask Siri to “Shuffle Photo Widget”.")
                }

                Section("Feel") {
                    Toggle(isOn: $hapticsEnabled) {
                        Label("Haptics", systemImage: "hand.tap")
                    }
                    Button {
                        dismiss()
                        hasOnboarded = false
                    } label: {
                        Label("Show Welcome Again", systemImage: "sparkles")
                    }
                }

                Section {
                    LabeledContent("Version", value: version)
                } header: {
                    Text("About")
                } footer: {
                    Label("Your photos stay on this device. Nothing is uploaded, ever.", systemImage: "lock.fill")
                        .padding(.top, 4)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .sheet(isPresented: $showsGuide) { AddWidgetGuide() }
        }
    }
}
