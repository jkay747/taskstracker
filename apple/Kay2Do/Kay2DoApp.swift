import SwiftUI

@main
struct Kay2DoApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { _, phase in
            store.setActive(phase == .active)
        }
        .commands {
            // Frees Command-N for "New Task" (the toolbar button owns the shortcut).
            CommandGroup(replacing: .newItem) { }
        }
    }
}
