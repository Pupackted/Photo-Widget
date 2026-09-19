import AppIntents
import SwiftUI
import WidgetKit

/// Control Center button that moves every photo widget on to its next photo.
struct ShufflePhotosControl: ControlWidget {
    static let kind = "Adrian.Photo-Widget.Shuffle"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ShufflePhotoWidgetsIntent()) {
                Label("Shuffle Photos", systemImage: "photo.stack")
            }
        }
        .displayName("Shuffle Photos")
        .description("Show the next photo on all of your photo widgets.")
    }
}
