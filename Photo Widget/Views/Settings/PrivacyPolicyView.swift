import SwiftUI

/// The privacy policy, readable without a connection. Mirrors AppStore/privacy-policy.md.
struct PrivacyPolicyView: View {
    private let sections: [(title: LocalizedStringKey, body: LocalizedStringKey)] = [
        ("Your photos stay on your device",
         "Photos you choose are copied into the app’s private storage on your device so your widgets can show them. They are never uploaded, shared or sent anywhere."),
        ("Only the photos you choose",
         "Framed normally uses the system photo picker, so it only sees the photos you select."),
        ("Albums and On This Day",
         "If you sync a widget with an album or turn on On This Day, Framed asks for access to your photo library. It reads the library only on your device, only to choose photos for those widgets. You can change this at any time in Settings → Privacy & Security → Photos."),
        ("No accounts, no tracking",
         "There’s no sign-in, no analytics, no advertising and no third-party code. The app makes no network connections."),
        ("Backups",
         "If you back up your device to iCloud or a computer, your widgets are included in that backup like any other app data."),
        ("Deleting your data",
         "Deleting a widget deletes its photos from the app. Deleting the app removes everything it stored."),
        ("Questions",
         "If you have questions about this policy, contact us through the App Store page for Framed."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label("Nothing you add ever leaves your device.", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.tint)
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.headline)
                        Text(section.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Last updated October 2026")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
