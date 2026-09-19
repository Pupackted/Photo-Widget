//
//  Photo_WidgetApp.swift
//  Photo Widget
//
//  Created by Adrian Yusufa Rachman on 05/06/26.
//

import AppIntents
import SwiftUI

@main
struct Photo_WidgetApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { model.handle($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.save() }
        }
    }
}

private struct RootView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        LibraryView()
            .fullScreenCover(isPresented: Binding(get: { !hasOnboarded }, set: { hasOnboarded = !$0 })) {
                OnboardingView { hasOnboarded = true }
            }
    }
}

nonisolated struct PhotoWidgetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShufflePhotoWidgetsIntent(),
            phrases: [
                "Shuffle \(.applicationName)",
                "Show a new photo in \(.applicationName)",
            ],
            shortTitle: "Shuffle Photos",
            systemImageName: "shuffle"
        )
    }
}
