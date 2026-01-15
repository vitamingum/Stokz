import SwiftUI

@main
struct StokzApp: App {
    @StateObject private var appState = AppState.shared
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task {
                    await appState.initialize()
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    handleScenePhaseChange(from: oldPhase, to: newPhase)
                }
                .preferredColorScheme(nil) // Support both light and dark mode
        }
    }
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // App returned to foreground
            print("🔄 [App] Returning to foreground from \(oldPhase)")
            
            // Only refresh if we were actually in background (not just inactive briefly)
            if oldPhase == .background {
                print("🔄 [App] Was in background - refreshing data")
                Task {
                    await appState.handleReturnToForeground()
                }
            }
            
        case .inactive:
            // App is about to go to background or is transitioning
            print("⏸️ [App] Going inactive")
            
        case .background:
            // App is in background - track time for stale data detection
            print("💤 [App] Entered background")
            appState.handleEnterBackground()
            
        @unknown default:
            break
        }
    }
}
