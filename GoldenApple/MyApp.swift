import SwiftUI

@main struct MyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if let error = model.startupError {
                    ContentUnavailableView("GoldenApple could not start", systemImage: "exclamationmark.triangle", description: Text(error))
                        .frame(width: 480, height: 320)
                } else if !model.isReady {
                    ProgressView()
                        .frame(width: 480, height: 320)
                } else if model.hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingView(launcher: model.launcher, onFinish: model.completeOnboarding)
                }
            }
            .task { await model.prepare() }
        }
        .windowResizability(.contentSize)
    }
}
