import SwiftUI
import SwiftData

@main
struct ShooApp: App {
    @State private var sentry = Sentry()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sentry)
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
        .modelContainer(for: Sighting.self)
    }
}
