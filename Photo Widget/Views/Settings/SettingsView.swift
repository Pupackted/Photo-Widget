import StoreKit
import SwiftUI
import WidgetKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("hasOnboarded") private var hasOnboarded = true
    @State private var showsGuide = false
    @State private var shuffles = 0

    private var summary: String {
        let widgets = model.widgets.count == 1 ? String(localized: "1 widget") : String(localized: "\(model.widgets.count) widgets")
        let count = model.widgets.reduce(0) { $0 + $1.photos.count }
        let photos = count == 1 ? String(localized: "1 photo") : String(localized: "\(count) photos")
        return "\(widgets) · \(photos)"
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
                            Text(verbatim: "Framed")
                                .font(.title3.weight(.semibold))
                            Text(summary)
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
                    if #available(iOS 18.0, *) {
                        Text("You can also add “Shuffle Photos” to Control Center, or ask Siri to “Shuffle Framed”.")
                    } else {
                        Text("You can also ask Siri to “Shuffle Framed”.")
                    }
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

                Section("Support") {
                    Button {
                        if let url = AppInfo.reviewURL { openURL(url) } else { requestReview() }
                    } label: {
                        Label("Rate Framed", systemImage: "star")
                    }
                    if let url = AppInfo.supportURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Contact Support", systemImage: "envelope")
                        }
                    }
                    if let url = AppInfo.privacyPolicyURL {
                        Link(destination: url) {
                            Label("Privacy Policy", systemImage: "hand.raised")
                        }
                    } else {
                        NavigationLink {
                            PrivacyPolicyView()
                        } label: {
                            Label("Privacy Policy", systemImage: "hand.raised")
                        }
                    }
                }

                Section {
                    LabeledContent("Version", value: AppInfo.version)
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
                    DoneButton { dismiss() }
                }
            }
            .sheet(isPresented: $showsGuide) { AddWidgetGuide() }
        }
    }
}
