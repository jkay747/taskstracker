#if os(macOS)
import AppKit
import SwiftUI

/// One connected display, with an ID that stays the same across restarts and
/// replugging (macOS's display UUID), so a choice of displays sticks.
struct DisplayInfo: Identifiable, Hashable {
    let id: String
    let name: String
    /// In macOS screen coordinates (origin at the bottom left of the main display).
    let frame: CGRect
    let isMain: Bool

    static func all() -> [DisplayInfo] {
        let main = NSScreen.screens.first
        return NSScreen.screens.map { screen in
            DisplayInfo(id: id(of: screen), name: screen.localizedName, frame: screen.frame, isMain: screen == main)
        }
    }

    static func id(of screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return screen.localizedName
        }
        if let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return String(number)
    }
}

/// A picture of the connected displays, laid out the way they're arranged in
/// System Settings → Displays. Click a display to put the list on it or take it off.
struct DisplayArrangementPicker: View {
    @ObservedObject var wall: WallpaperController
    /// Shows the desktop picture, framed, inside each chosen display.
    var photo: NSImage?

    @ObservedObject private var framing = PhotoFraming.shared
    @EnvironmentObject private var store: Store
    @State private var displays = DisplayInfo.all()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let layout = Layout(displays: displays, in: geo.size)
                ZStack(alignment: .topLeading) {
                    ForEach(displays) { display in
                        let rect = layout.rect(for: display)
                        monitor(display, size: rect.size)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .frame(height: 170)

            HStack(spacing: 8) {
                Button("All Displays") { wall.showOnAllDisplays() }
                    .disabled(wall.displayMode == .all)
                if displays.count > 1, let main = displays.first(where: \.isMain) {
                    Button("Only \(main.name)") { wall.showOnlyOn([main.id]) }
                        .disabled(wall.displayMode == .chosen && wall.chosenDisplays == [main.id])
                }
                Spacer()
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = DisplayInfo.all()
        }
    }

    private var summary: String {
        if wall.displayMode == .all {
            return displays.count == 1 ? "On your display, and any you connect" : "On all \(displays.count) displays, and any you connect"
        }
        let on = displays.filter { wall.shows(on: $0.id) }.count
        return "On \(on) of \(displays.count) display\(displays.count == 1 ? "" : "s")"
    }

    private func monitor(_ display: DisplayInfo, size: CGSize) -> some View {
        let on = wall.shows(on: display.id)
        let onlyOne = displays.filter { wall.shows(on: $0.id) }.count == 1
        return Button {
            wall.toggleDisplay(display.id, among: displays.map(\.id))
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(on ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                if on, wall.usePhoto, let photo {
                    FramedImage(image: photo, framing: framing.framing(for: store.background.value))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .opacity(0.9)
                }
                VStack(spacing: 4) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(on ? Color.accentColor : Color.secondary)
                    Text(display.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if display.isMain {
                        Text("Main").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .opacity(size.width > 70 ? 1 : 0.0)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(on ? Color.accentColor : Color.secondary.opacity(0.45), lineWidth: on ? 3 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(on && onlyOne && wall.displayMode == .chosen)
        .help(on ? (onlyOne ? "The list needs at least one display" : "Take the list off \(display.name)") : "Show the list on \(display.name)")
        .accessibilityLabel(display.name + (display.isMain ? ", main display" : ""))
        .accessibilityValue(on ? "Shows the list" : "Doesn't show the list")
    }

    /// Fits the displays' arrangement into the space available, keeping their proportions.
    private struct Layout {
        let union: CGRect
        let scale: CGFloat
        let origin: CGPoint

        init(displays: [DisplayInfo], in size: CGSize) {
            let union = displays.map(\.frame).reduce(CGRect.null) { $0.union($1) }
            self.union = union.isNull ? CGRect(x: 0, y: 0, width: 1, height: 1) : union
            let gap: CGFloat = 6
            scale = min((size.width - gap) / self.union.width, (size.height - gap) / self.union.height)
            origin = CGPoint(x: (size.width - self.union.width * scale) / 2, y: (size.height - self.union.height * scale) / 2)
        }

        /// Screen coordinates go up from the bottom; the picture's go down from the top.
        func rect(for display: DisplayInfo) -> CGRect {
            let inset: CGFloat = 3
            let x = origin.x + (display.frame.minX - union.minX) * scale
            let y = origin.y + (union.maxY - display.frame.maxY) * scale
            return CGRect(x: x, y: y, width: display.frame.width * scale, height: display.frame.height * scale).insetBy(dx: inset, dy: inset)
        }
    }
}
#endif
