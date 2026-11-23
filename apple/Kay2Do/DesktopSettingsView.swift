#if os(macOS)
import SwiftUI

/// Desktop Settings (Desktop menu → Desktop Settings…): which displays show the
/// list, how it's laid out, and how the desktop picture is framed.
struct DesktopSettingsView: View {
    static let windowID = "desktop-settings"

    @EnvironmentObject private var store: Store
    @ObservedObject private var wall = WallpaperController.shared
    @ObservedObject private var images = BackgroundImages.shared
    @State private var displays = DisplayInfo.all()

    private var photo: NSImage? {
        let choice = store.background
        return choice == .none ? nil : images.image(for: choice.value, store: store)
    }

    /// The first display the list is on, for the shape of the framing preview.
    private var previewAspect: CGFloat {
        let frame = (displays.first { wall.shows(on: $0.id) } ?? displays.first)?.frame ?? CGRect(x: 0, y: 0, width: 16, height: 10)
        return frame.height > 0 ? frame.width / frame.height : 16 / 10
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show List on Desktop", isOn: $wall.isOn)
            }

            Section {
                DisplayArrangementPicker(wall: wall, photo: photo)
            } header: {
                Text("Displays")
            } footer: {
                Text("Click a display to put the list on it or take it off. All Displays includes any you connect later.")
            }

            Section("Layout") {
                Picker("Position", selection: $wall.position) {
                    ForEach(WallpaperController.Position.allCases) { Text($0.label).tag($0) }
                }
                Picker("Text Size", selection: $wall.textSize) {
                    ForEach(WallpaperController.TextSize.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Only My Tasks", isOn: $wall.mineOnly)
                Toggle("Check Off from the Desktop", isOn: $wall.clickable)
            }

            Section {
                Toggle("Use the List's Picture as the Desktop Picture", isOn: $wall.usePhoto)
                if wall.usePhoto {
                    if store.background == .none {
                        Text(store.isManager
                             ? "This list has no background picture. Choose one under List Settings → Background picture."
                             : "This list has no background picture yet. Its owner or an editor can choose one.")
                            .foregroundStyle(.secondary)
                    } else if let photo {
                        FramingEditor(image: photo, value: store.background.value, aspect: previewAspect)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading the picture…").foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Desktop Picture")
            } footer: {
                Text("The framing is kept on this Mac and used on every display the list is on.")
            }

            Section {
                Toggle("Open Kay2-Do at Login", isOn: Binding(
                    get: { wall.opensAtLogin },
                    set: { wall.setOpensAtLogin($0) }
                ))
                if let error = wall.loginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, idealWidth: 600, minHeight: 640, idealHeight: 760)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = DisplayInfo.all()
        }
    }
}
#endif
