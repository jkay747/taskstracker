#if os(macOS)
import AppKit
import ServiceManagement
import SwiftUI

/// "Show on Desktop": draws the list on the Mac desktop, above the desktop
/// picture and behind every app window, on every Space. It updates as tasks
/// change on the web or on other devices, and (when Clickable is on) you can
/// check tasks off right there.
@MainActor
final class WallpaperController: ObservableObject {
    static let shared = WallpaperController()

    enum Position: String, CaseIterable, Identifiable {
        case right, left, full
        var id: String { rawValue }
        var label: String {
            switch self {
            case .right: return "Right Side"
            case .left: return "Left Side"
            case .full: return "Full Screen"
            }
        }
    }

    enum TextSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var scale: CGFloat {
            switch self {
            case .small: return 0.88
            case .medium: return 1.0
            case .large: return 1.22
            }
        }
    }

    @Published var isOn: Bool { didSet { save(); rebuild() } }
    @Published var position: Position { didSet { save(); rebuild() } }
    @Published var textSize: TextSize { didSet { save(); rebuild() } }
    /// Clickable: sits above the desktop icons so its checkboxes work.
    /// Otherwise it sits below the icons and ignores the mouse entirely.
    @Published var clickable: Bool { didSet { save(); rebuild() } }
    @Published var allScreens: Bool { didSet { save(); rebuild() } }
    @Published var mineOnly: Bool { didSet { save() } }
    /// Fills the screen with the list's background picture, behind the desktop icons.
    @Published var usePhoto: Bool { didSet { save(); rebuild() } }
    @Published private(set) var loginError: String?

    private var store: Store?
    private var panels: [DesktopPanel] = []
    private var screenObserver: NSObjectProtocol?

    private init() {
        let d = UserDefaults.standard
        isOn = d.bool(forKey: "wallpaper.on")
        position = Position(rawValue: d.string(forKey: "wallpaper.position") ?? "") ?? .right
        textSize = TextSize(rawValue: d.string(forKey: "wallpaper.textSize") ?? "") ?? .medium
        clickable = d.object(forKey: "wallpaper.clickable") as? Bool ?? true
        allScreens = d.bool(forKey: "wallpaper.allScreens")
        mineOnly = d.bool(forKey: "wallpaper.mineOnly")
        usePhoto = d.bool(forKey: "wallpaper.usePhoto")
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
    }

    /// Called once the app's data store exists; restores the desktop list if it was on.
    func attach(_ store: Store) {
        guard self.store !== store else { return }
        self.store = store
        rebuild()
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(isOn, forKey: "wallpaper.on")
        d.set(position.rawValue, forKey: "wallpaper.position")
        d.set(textSize.rawValue, forKey: "wallpaper.textSize")
        d.set(clickable, forKey: "wallpaper.clickable")
        d.set(allScreens, forKey: "wallpaper.allScreens")
        d.set(mineOnly, forKey: "wallpaper.mineOnly")
        d.set(usePhoto, forKey: "wallpaper.usePhoto")
    }

    private func rebuild() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        guard let store else { return }
        // Keep refreshing while the app is in the background, so the desktop stays current.
        store.keepsRefreshing = isOn
        guard isOn else { return }
        if store.phase == .ready { store.startPolling() }

        let screens = allScreens ? NSScreen.screens : [NSScreen.main ?? NSScreen.screens.first].compactMap { $0 }
        if usePhoto {
            // The picture goes in its own window at the desktop-picture level, under the
            // icons and under the list, and never takes clicks.
            for screen in screens {
                let panel = DesktopPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.animationBehavior = .none
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
                panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
                panel.ignoresMouseEvents = true
                let host = DesktopHostingView(rootView: AnyView(DesktopPhotoView().environmentObject(store)))
                host.sizingOptions = []
                panel.contentView = host
                panel.setFrame(screen.frame, display: true)
                panel.orderFront(nil)
                panels.append(panel)
            }
        }
        for screen in screens {
            let frame = frame(on: screen)
            let panel = DesktopPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = false
            panel.isReleasedWhenClosed = false
            panel.animationBehavior = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            let base = CGWindowLevelForKey(clickable ? .desktopIconWindow : .desktopWindow)
            panel.level = NSWindow.Level(rawValue: Int(base) + 1)
            panel.ignoresMouseEvents = !clickable

            let root = WallpaperView(fillsScreen: position == .full)
                .environmentObject(store)
                .environmentObject(self)
            let host = DesktopHostingView(rootView: AnyView(root))
            host.sizingOptions = []
            panel.contentView = host
            panel.setFrame(frame, display: true)
            panel.orderFront(nil)
            panels.append(panel)
        }
    }

    private func frame(on screen: NSScreen) -> NSRect {
        let area = screen.visibleFrame
        let margin: CGFloat = 24
        switch position {
        case .full:
            return area
        case .right, .left:
            let width = min(420 * textSize.scale, area.width * 0.45)
            let x = position == .right ? area.maxX - width - margin : area.minX + margin
            return NSRect(x: x, y: area.minY + margin, width: width, height: area.height - margin * 2)
        }
    }

    // MARK: Open at Login

    var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        objectWillChange.send()
    }

    // MARK: Opening the app from the desktop

    func openApp() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { !($0 is DesktopPanel) && $0.canBecomeMain && $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // No window open: ask macOS to reopen the app, which brings back its main window.
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// A borderless panel that never takes keyboard focus or activates the app,
/// so clicking a checkbox on the desktop leaves your other apps in front.
final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on the desktop list press a button, even though
/// Kay2-Do isn't the active app.
final class DesktopHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The "Desktop" menu: in the menu bar and in the list's toolbar menu.
struct WallpaperMenu: View {
    @ObservedObject private var wall = WallpaperController.shared

    var body: some View {
        Toggle("Show List on Desktop", isOn: $wall.isOn)
            .keyboardShortcut("d", modifiers: [.command, .shift])
        Picker("Position", selection: $wall.position) {
            ForEach(WallpaperController.Position.allCases) { Text($0.label).tag($0) }
        }
        Picker("Text Size", selection: $wall.textSize) {
            ForEach(WallpaperController.TextSize.allCases) { Text($0.label).tag($0) }
        }
        Toggle("Only My Tasks", isOn: $wall.mineOnly)
        Toggle("Check Off from the Desktop", isOn: $wall.clickable)
        Toggle("Show on All Displays", isOn: $wall.allScreens)
        Toggle("Use the List's Picture as the Desktop Picture", isOn: $wall.usePhoto)
        Divider()
        Toggle("Open Kay2-Do at Login", isOn: Binding(
            get: { wall.opensAtLogin },
            set: { wall.setOpensAtLogin($0) }
        ))
    }
}
#endif
