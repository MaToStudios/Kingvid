import SwiftUI
import SwiftData

@main
struct KingVidApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(app.browser)
                .environmentObject(app.media)
                .environmentObject(app.library)
                .environmentObject(app.youtube)
                .modelContainer(app.container)
                .preferredColorScheme(.dark)
        }
    }
}
