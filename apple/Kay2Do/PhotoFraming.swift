#if os(macOS)
import AppKit
import SwiftUI
import Vision

/// How a desktop picture sits on a screen: the point of the picture to keep in the
/// middle (0…1 across and down) and how far to zoom in past "just fills the screen".
struct Framing: Codable, Equatable {
    var x: Double = 0.5
    var y: Double = 0.5
    var zoom: Double = 1
    /// True once someone has panned or zoomed by hand; false while it's the automatic guess.
    var manual = false

    static let centered = Framing()
    static let zoomRange: ClosedRange<Double> = 1...4
}

/// Framing for each picture, kept on this Mac. Until someone adjusts a picture by
/// hand, it's framed automatically: Apple's Vision framework finds faces, or else
/// the main subject, and the picture is centered on them.
@MainActor
final class PhotoFraming: ObservableObject {
    static let shared = PhotoFraming()

    @Published private(set) var framings: [String: Framing] = [:]
    /// Pictures being looked at by Vision right now.
    @Published private(set) var analyzing = Set<String>()
    /// What Vision found, for the settings window: "faces" or "the main subject".
    @Published private(set) var found: [String: String] = [:]
    private let key = "wallpaper.framings"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: Framing].self, from: data) {
            framings = saved
        }
    }

    func framing(for value: String) -> Framing { framings[value] ?? .centered }

    func set(_ framing: Framing, for value: String) {
        guard !value.isEmpty, framings[value] != framing else { return }
        framings[value] = framing
        save()
    }

    /// Frames a picture automatically, unless it's been framed by hand already.
    func autoFrameIfNeeded(_ image: NSImage, for value: String) {
        guard !value.isEmpty, framings[value]?.manual != true, framings[value] == nil, !analyzing.contains(value) else { return }
        autoFrame(image, for: value)
    }

    /// Asks Vision again and replaces the framing, even a hand-made one.
    func autoFrame(_ image: NSImage, for value: String) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        analyzing.insert(value)
        Task.detached(priority: .utility) {
            let guess = Self.guess(cg)
            await MainActor.run {
                self.analyzing.remove(value)
                self.found[value] = guess.found
                self.framings[value] = guess.framing
                self.save()
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(framings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: Vision

    /// Faces first (the eyes are what people look for), then the objects Vision
    /// thinks stand out, then where it thinks a viewer's eye goes; centered if none.
    nonisolated static func guess(_ image: CGImage) -> (framing: Framing, found: String) {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let faces = VNDetectFaceRectanglesRequest()
        let objects = VNGenerateObjectnessBasedSaliencyImageRequest()
        let attention = VNGenerateAttentionBasedSaliencyImageRequest()
        try? handler.perform([faces, objects, attention])

        let faceBoxes = (faces.results ?? []).map(\.boundingBox)
        if !faceBoxes.isEmpty {
            // Weight bigger faces more, and aim a little above their middle so heads aren't cut off.
            var result = framing(around: faceBoxes)
            result.y = max(0, result.y - 0.04)
            return (result, faceBoxes.count == 1 ? "a face" : "\(faceBoxes.count) faces")
        }
        let objectBoxes = (objects.results?.first?.salientObjects ?? []).filter { $0.confidence > 0.2 }.map(\.boundingBox)
        if !objectBoxes.isEmpty { return (framing(around: objectBoxes), "the main subject") }
        let attentionBoxes = (attention.results?.first?.salientObjects ?? []).map(\.boundingBox)
        if !attentionBoxes.isEmpty { return (framing(around: attentionBoxes), "where the eye goes") }
        return (.centered, "")
    }

    /// The area-weighted middle of the boxes. Vision's boxes are 0…1 with the origin at
    /// the bottom left; a Framing's y runs down from the top.
    nonisolated private static func framing(around boxes: [CGRect]) -> Framing {
        var sx = 0.0, sy = 0.0, total = 0.0
        for box in boxes {
            let weight = max(Double(box.width * box.height), 0.0001)
            sx += Double(box.midX) * weight
            sy += Double(1 - box.midY) * weight
            total += weight
        }
        return Framing(x: min(max(sx / total, 0), 1), y: min(max(sy / total, 0), 1), zoom: 1, manual: false)
    }
}

/// A picture filling the space it's given, with `framing`'s point kept as close to
/// the middle as the picture's edges allow, zoomed in by `framing.zoom`.
struct FramedImage: View {
    let image: NSImage
    let framing: Framing

    var body: some View {
        GeometryReader { geo in
            let layout = FramedLayout(image: image.size, in: geo.size, framing: framing)
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: layout.size.width, height: layout.size.height)
                .offset(x: layout.origin.x, y: layout.origin.y)
        }
        .clipped()
    }
}

/// Where a framed picture lands in a frame of a given size.
struct FramedLayout {
    let size: CGSize
    let origin: CGPoint

    init(image: CGSize, in frame: CGSize, framing: Framing) {
        guard image.width > 0, image.height > 0, frame.width > 0, frame.height > 0 else {
            size = frame; origin = .zero; return
        }
        let scale = max(frame.width / image.width, frame.height / image.height) * CGFloat(framing.zoom)
        size = CGSize(width: image.width * scale, height: image.height * scale)
        let x = frame.width / 2 - CGFloat(framing.x) * size.width
        let y = frame.height / 2 - CGFloat(framing.y) * size.height
        origin = CGPoint(x: min(0, max(frame.width - size.width, x)), y: min(0, max(frame.height - size.height, y)))
    }

    /// The framing that reproduces this picture's current position: the point now in
    /// the middle, so a drag that ran into an edge doesn't build up hidden slack.
    static func reachable(_ framing: Framing, image: CGSize, in frame: CGSize) -> Framing {
        let layout = FramedLayout(image: image, in: frame, framing: framing)
        guard layout.size.width > 0, layout.size.height > 0 else { return framing }
        var out = framing
        out.x = Double((frame.width / 2 - layout.origin.x) / layout.size.width)
        out.y = Double((frame.height / 2 - layout.origin.y) / layout.size.height)
        return out
    }
}

/// Pan and zoom a desktop picture by hand: drag it, pinch on a trackpad, scroll, or use the slider.
struct FramingEditor: View {
    let image: NSImage
    let value: String
    /// Width ÷ height of the display being previewed.
    let aspect: CGFloat

    @ObservedObject private var framing = PhotoFraming.shared
    @State private var dragStart: Framing?
    @State private var pinchStart: Framing?

    private var current: Framing { framing.framing(for: value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                FramedImage(image: image, framing: current)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.4)))
                    .overlay(alignment: .topLeading) {
                        if framing.analyzing.contains(value) {
                            Label("Finding the subject…", systemImage: "sparkles")
                                .font(.caption).padding(6)
                                .background(.regularMaterial, in: Capsule()).padding(8)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(drag(in: geo.size))
                    .simultaneousGesture(pinch(in: geo.size))
                    .onScrollWheelZoom { delta in zoom(by: delta, in: geo.size) }
                    .help("Drag to move the picture. Pinch or scroll to zoom.")
            }
            .aspectRatio(aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: Binding(get: { current.zoom }, set: { setZoom($0) }), in: Framing.zoomRange)
                    .frame(maxWidth: 220)
                Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                Spacer()
                Button {
                    framing.autoFrame(image, for: value)
                } label: {
                    Label("Auto-Frame", systemImage: "sparkles")
                }
                .help("Let Kay2-Do find the faces or main subject and center them")
                .disabled(framing.analyzing.contains(value))
                Button("Center") { framing.set(Framing(manual: true), for: value) }
            }
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { framing.autoFrameIfNeeded(image, for: value) }
    }

    private var caption: String {
        if current.manual { return "Framed by hand. Auto-Frame centers the subject again." }
        if let what = framing.found[value], !what.isEmpty { return "Centered on \(what), found automatically. Drag, pinch or scroll to adjust." }
        return "Drag to move the picture; pinch, scroll or use the slider to zoom."
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { g in
                let start = dragStart ?? FramedLayout.reachable(current, image: image.size, in: size)
                if dragStart == nil { dragStart = start }
                let layout = FramedLayout(image: image.size, in: size, framing: start)
                var next = start
                next.x = start.x - Double(g.translation.width / max(layout.size.width, 1))
                next.y = start.y - Double(g.translation.height / max(layout.size.height, 1))
                next.manual = true
                framing.set(FramedLayout.reachable(next, image: image.size, in: size), for: value)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func pinch(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { g in
                let start = pinchStart ?? current
                if pinchStart == nil { pinchStart = start }
                setZoom(start.zoom * Double(g.magnification), in: size)
            }
            .onEnded { _ in pinchStart = nil }
    }

    private func zoom(by delta: CGFloat, in size: CGSize) {
        setZoom(current.zoom * (1 + Double(delta) * 0.01), in: size)
    }

    private func setZoom(_ zoom: Double, in size: CGSize? = nil) {
        var next = current
        next.zoom = min(max(zoom, Framing.zoomRange.lowerBound), Framing.zoomRange.upperBound)
        next.manual = true
        if let size { next = FramedLayout.reachable(next, image: image.size, in: size) }
        framing.set(next, for: value)
    }
}

private extension View {
    /// Scroll-wheel or two-finger scroll over the view zooms the picture.
    func onScrollWheelZoom(_ action: @escaping (CGFloat) -> Void) -> some View {
        overlay(ScrollWheelCatcher(action: action))
    }
}

/// Picks up scroll-wheel events (an NSView is the only way in SwiftUI on macOS 14),
/// passing clicks and drags through to the picture underneath.
private struct ScrollWheelCatcher: NSViewRepresentable {
    let action: (CGFloat) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.action = action }

    final class CatcherView: NSView {
        var action: ((CGFloat) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            action?(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 6))
        }
        // Only scroll events land here: everything else goes to the views underneath.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .scrollWheel else { return nil }
            return super.hitTest(point)
        }
    }
}
#endif
