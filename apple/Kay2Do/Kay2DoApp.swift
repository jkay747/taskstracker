import SwiftUI

@main
struct Kay2DoApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onOpenURL { store.open($0) }
                #if os(macOS)
                .onAppear { WallpaperController.shared.attach(store) }
                #endif
        }
        .onChange(of: scenePhase) { _, phase in
            store.setActive(phase == .active)
        }
        .commands {
            // Frees Command-N for "New Task" (the toolbar button owns the shortcut).
            CommandGroup(replacing: .newItem) { }
            #if os(macOS)
            CommandMenu("Desktop") {
                WallpaperMenu()
            }
            #endif
        }
    }
}
