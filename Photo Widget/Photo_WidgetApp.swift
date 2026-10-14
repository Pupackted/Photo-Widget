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
    @Environment(AppModel.self) private var model
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        LibraryView()
            .fullScreenCover(isPresented: Binding(get: { !hasOnboarded }, set: { hasOnboarded = !$0 })) {
                OnboardingView { finishOnboarding() }
            }
            .alert(model.importIssue?.failed == 1 ? Text("A photo couldn’t be added") : Text("Some photos couldn’t be added"),
                   isPresented: Binding(get: { model.importIssue != nil }, set: { if !$0 { model.importIssue = nil } }),
                   presenting: model.importIssue) { _ in
                Button("OK") {}
            } message: { issue in
                Text("\(issue.failed) of \(issue.total) photos couldn’t be loaded. If they’re stored in iCloud, check your connection and try adding them again.")
            }
    }

    /// First-timers go straight on to picking photos for their first widget.
    private func finishOnboarding() {
        hasOnboarded = true
        guard model.widgets.isEmpty else { return }
        Task {
            // Wait for the welcome screen to finish sliding away.
            try? await Task.sleep(for: .milliseconds(600))
            model.pendingRoute = .newWidget
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
