import SwiftUI

@main
struct Kay2DoApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #else
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    @StateObject private var store = Persistence.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, store.context)
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.tidy()
                store.refreshShares()
            } else {
                store.save()
            }
        }
        .commands {
            // Frees Command-N for "New Task" (the toolbar button owns the shortcut).
            CommandGroup(replacing: .newItem) { }
        }
    }
}
