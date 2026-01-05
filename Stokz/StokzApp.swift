import SwiftUI

@main
struct StokzApp: App {
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task {
                    await appState.initialize()
                }
                .preferredColorScheme(nil) // Support both light and dark mode
        }
    }
}
