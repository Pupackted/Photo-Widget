import Foundation

/// Links that point outside the app. Fill these in once they exist; rows for empty ones stay hidden.
enum AppInfo {
    /// The number in the app's App Store URL (App Store Connect → App Information → Apple ID).
    /// With it, "Rate" opens the review page; without it, the system rating prompt is used.
    static let appStoreID: String? = nil
    /// Where "Contact Support" sends email.
    static let supportEmail: String? = nil
    /// A hosted copy of the privacy policy. The in-app policy is shown when this is empty.
    static let privacyPolicyURL: URL? = nil

    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    static var reviewURL: URL? {
        appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)?action=write-review") }
    }

    static var supportURL: URL? {
        supportEmail.flatMap { URL(string: "mailto:\($0)?subject=Photo%20Widget%20\(version.replacingOccurrences(of: " ", with: "%20"))") }
    }
}
