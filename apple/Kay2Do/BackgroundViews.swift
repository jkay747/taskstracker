#if os(macOS)
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Loads and keeps background pictures: built-in ones from Wikimedia Commons,
/// uploaded ones from the list's private storage folder.
@MainActor
final class BackgroundImages: ObservableObject {
    static let shared = BackgroundImages()

    @Published private(set) var images: [String: NSImage] = [:]
    private var loading = Set<String>()
    private var failed = Set<String>()

    /// The picture for a list's background value, or nil while it loads.
    func image(for value: String, store: Store, thumbnail: Bool = false) -> NSImage? {
        let key = (thumbnail ? "thumb|" : "full|") + value
        if let image = images[key] { return image }
        if thumbnail, let full = images["full|" + value] { return full }
        guard !loading.contains(key), !failed.contains(key) else { return nil }
        loading.insert(key)
        Task { await load(key: key, value: value, store: store, thumbnail: thumbnail) }
        return nil
    }

    private func load(key: String, value: String, store: Store, thumbnail: Bool) async {
        defer { loading.remove(key) }
        var data: Data?
        switch BackgroundChoice(value) {
        case .none:
            return
        case .library(let photo):
            guard let url = URL(string: thumbnail ? photo.thumb : photo.full) else { return }
            var request = URLRequest(url: url)
            // Wikimedia asks apps to say who they are.
            request.setValue("Kay2-Do/1.0 (https://github.com/jkay747/taskstracker)", forHTTPHeaderField: "User-Agent")
            data = try? await URLSession.shared.data(for: request).0
        case .upload(let path):
            data = try? await store.downloadBackground(path: path)
        }
        if let data, let image = NSImage(data: data) {
            images[key] = image
        } else {
            failed.insert(key)
        }
    }
}

/// A picture that fills whatever space it's given, cropping the edges.
struct FillImage: View {
    let image: NSImage

    var body: some View {
        Color.clear
            .overlay {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
    }
}

/// The list's picture behind the task list, under a tint that keeps text readable.
struct ListBackdrop: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var images = BackgroundImages.shared

    private var tint: Double {
        switch store.backgroundStyle {
        case "subtle": return 0.86
        case "vivid": return 0.52
        default: return 0.72
        }
    }

    var body: some View {
        let choice = store.background
        if choice != .none, let image = images.image(for: choice.value, store: store) {
            FillImage(image: image)
                .overlay(Color(nsColor: .windowBackgroundColor).opacity(tint))
                .overlay(alignment: .bottomTrailing) {
                    if case .library(let photo) = choice {
                        Link(photo.title + " — " + photo.credit, destination: URL(string: photo.page)!)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
                .ignoresSafeArea()
        }
    }
}

/// The background picture section of List Settings: none, a built-in picture, or an uploaded photo.
struct BackgroundSettings: View {
    @Binding var value: String
    @Binding var style: String
    /// Uploads made while the sheet is open, so unused ones can be removed.
    @Binding var uploaded: [String]

    @EnvironmentObject private var store: Store
    @ObservedObject private var images = BackgroundImages.shared
    @State private var importing = false
    @State private var busy = false
    @State private var status: String?

    private var uploadValues: [String] {
        var seen = Set<String>()
        return ([store.list?.background ?? "", value] + uploaded)
            .filter { $0.hasPrefix("upload:") && seen.insert($0).inserted }
    }

    var body: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                tile("", label: "None", image: nil)
                ForEach(uploadValues, id: \.self) { upload in
                    tile(upload, label: "Your photo", image: images.image(for: upload, store: store))
                }
                ForEach(Backgrounds.all) { photo in
                    tile("library:" + photo.id, label: photo.title,
                         image: images.image(for: "library:" + photo.id, store: store, thumbnail: true))
                        .help(photo.title + " — " + photo.credit)
                }
            }
            .padding(.vertical, 4)
            Picker("Photo", selection: $style) {
                Text("Subtle").tag("subtle")
                Text("Balanced").tag("balanced")
                Text("Vivid").tag("vivid")
            }
            .pickerStyle(.segmented)
            HStack(spacing: 10) {
                Button("Upload a Photo…") { importing = true }
                    .disabled(busy)
                if busy { ProgressView().controlSize(.small) }
                if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Background picture")
        } footer: {
            Text("Shows behind the list in the Mac app and on the web, for everyone on this list. The built-in pictures are public-domain paintings and NASA and National Park Service photos from Wikimedia Commons.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            upload(url)
        }
    }

    private func tile(_ tileValue: String, label: String, image: NSImage?) -> some View {
        let selected = value == tileValue
        return Button {
            value = tileValue
        } label: {
            Color.secondary.opacity(0.12)
                .frame(height: 72)
                .overlay {
                    if let image {
                        FillImage(image: image)
                    } else {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func upload(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        let jpeg = PhotoShrinker.jpeg(from: url)
        if access { url.stopAccessingSecurityScopedResource() }
        guard let jpeg else {
            status = "Couldn't open that picture."
            return
        }
        busy = true
        status = "Uploading…"
        Task {
            defer { busy = false }
            do {
                let newValue = try await store.uploadBackground(jpeg: jpeg)
                uploaded.append(newValue)
                value = newValue
                status = "Uploaded. Click Save to use it."
            } catch {
                status = error.localizedDescription
            }
        }
    }
}

/// Shrinks a photo to at most 3840 pixels on its long side (turned the right
/// way up) and encodes it as JPEG, the same as the web app does.
enum PhotoShrinker {
    static func jpeg(from url: URL, maxPixels: Int = 3840) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.86])
    }
}

/// The list's picture filling the whole screen, for "Use the List's Picture as the Desktop Picture".
struct DesktopPhotoView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var images = BackgroundImages.shared

    var body: some View {
        let choice = store.background
        if choice != .none, let image = images.image(for: choice.value, store: store) {
            FillImage(image: image).ignoresSafeArea()
        } else {
            Color.clear
        }
    }
}
#endif
