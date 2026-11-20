import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// How task text looks on this device: font, size and color. Kept per device
/// (not on the shared list), so a Mac and an iPhone can each have their own.
enum TextAppearance {
    static let fontKey = "text.fontName"      // PostScript name; "" = system font
    static let sizeKey = "text.fontSize"      // points; 0 = platform default
    static let colorKey = "text.fontColor"    // "RRGGBB" or "RRGGBBAA"; "" = default

    #if os(iOS)
    static let defaultSize: Double = 17
    #else
    static let defaultSize: Double = 13
    #endif
    static let sizeRange: ClosedRange<Double> = 10...32

    static func size(_ stored: Double) -> Double { stored > 0 ? stored : defaultSize }

    /// The task-title font. Scales with Dynamic Type on iPhone.
    static func font(name: String, size stored: Double, scale: Double = 1) -> Font {
        let points = CGFloat(size(stored) * scale)
        guard !name.isEmpty, platformFontExists(name) else { return .system(size: points) }
        return .custom(name, size: points, relativeTo: .body)
    }

    /// The font for the line under a task (owner, due date…): same family, a bit smaller.
    static func metaFont(name: String, size stored: Double) -> Font {
        let points = CGFloat((size(stored) * 0.78).rounded())
        guard !name.isEmpty, platformFontExists(name) else { return .system(size: points) }
        return .custom(name, size: points, relativeTo: .caption)
    }

    static func color(_ stored: String) -> Color? {
        guard let hex = parseHex(stored) else { return nil }
        return Color(.sRGB,
                     red: Double((hex >> 24) & 0xFF) / 255,
                     green: Double((hex >> 16) & 0xFF) / 255,
                     blue: Double((hex >> 8) & 0xFF) / 255,
                     opacity: Double(hex & 0xFF) / 255)
    }

    static func hex(from color: Color) -> String {
        #if os(iOS)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return "" }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent, a = c.alphaComponent
        #endif
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X%02X", byte(r), byte(g), byte(b), byte(a))
    }

    /// A readable name for the picked font, e.g. "Avenir Next Demi Bold".
    static func displayName(_ name: String) -> String {
        guard !name.isEmpty else { return "System" }
        #if os(iOS)
        guard let font = UIFont(name: name, size: 12) else { return name }
        let face = font.fontDescriptor.object(forKey: .face) as? String
        return [font.familyName, face].compactMap { $0 }.filter { $0 != "Regular" }.joined(separator: " ")
        #else
        return NSFont(name: name, size: 12)?.displayName ?? name
        #endif
    }

    private static func platformFontExists(_ name: String) -> Bool {
        #if os(iOS)
        return UIFont(name: name, size: 12) != nil
        #else
        return NSFont(name: name, size: 12) != nil
        #endif
    }

    private static func parseHex(_ s: String) -> UInt32? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6 || t.count == 8, let v = UInt32(t, radix: 16) else { return nil }
        return t.count == 6 ? (v << 8) | 0xFF : v
    }
}

/// Settings section: Font (the system font picker), Font Size, Font Color, with a preview.
struct TextAppearanceSection: View {
    @Binding var fontName: String
    @Binding var fontSize: Double
    @Binding var fontColor: String
    @State private var pickingFont = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Section {
            LabeledContent("Font") {
                Button(TextAppearance.displayName(fontName)) { openPicker() }
                    #if os(macOS)
                    .buttonStyle(.bordered)
                    #endif
            }
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Font Size") {
                    Text("\(Int(TextAppearance.size(fontSize))) pt").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { TextAppearance.size(fontSize) }, set: { fontSize = $0.rounded() }),
                       in: TextAppearance.sizeRange, step: 1) {
                    Text("Font Size")
                } minimumValueLabel: {
                    Text("A").font(.caption)
                } maximumValueLabel: {
                    Text("A").font(.title3)
                }
                .labelsHidden()
            }
            ColorPicker("Font Color", selection: Binding(
                get: { TextAppearance.color(fontColor) ?? (scheme == .dark ? .white : .black) },
                set: { fontColor = TextAppearance.hex(from: $0) }
            ), supportsOpacity: false)

            Text("Pay the deposit for the Moab trip")
                .font(TextAppearance.font(name: fontName, size: fontSize))
                .foregroundStyle(TextAppearance.color(fontColor) ?? .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Preview")

            if !fontName.isEmpty || fontSize > 0 || !fontColor.isEmpty {
                Button("Reset to Default") {
                    fontName = ""; fontSize = 0; fontColor = ""
                }
            }
        } header: {
            Text("Text")
        } footer: {
            Text("How tasks look on this device. Other devices and the web keep their own look.")
        }
        #if os(iOS)
        .sheet(isPresented: $pickingFont) {
            SystemFontPicker { name in
                if let name { fontName = name }
                pickingFont = false
            }
            .ignoresSafeArea()
        }
        #endif
    }

    private func openPicker() {
        #if os(iOS)
        pickingFont = true
        #else
        MacFontPanel.shared.show(current: fontName, size: TextAppearance.size(fontSize)) { name, size in
            fontName = name
            fontSize = min(max(size.rounded(), TextAppearance.sizeRange.lowerBound), TextAppearance.sizeRange.upperBound)
        }
        #endif
    }
}

#if os(iOS)
/// UIKit's system font picker, every installed family and face.
private struct SystemFontPicker: UIViewControllerRepresentable {
    let done: (String?) -> Void

    func makeUIViewController(context: Context) -> UIFontPickerViewController {
        let config = UIFontPickerViewController.Configuration()
        config.includeFaces = true
        let picker = UIFontPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIFontPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, UIFontPickerViewControllerDelegate {
        let done: (String?) -> Void
        init(done: @escaping (String?) -> Void) { self.done = done }

        func fontPickerViewControllerDidPickFont(_ controller: UIFontPickerViewController) {
            guard let descriptor = controller.selectedFontDescriptor else { done(nil); return }
            done(UIFont(descriptor: descriptor, size: 17).fontName)
        }

        func fontPickerViewControllerDidCancel(_ controller: UIFontPickerViewController) { done(nil) }
    }
}
#else
/// The macOS Fonts panel (Format → Show Fonts). Picking a font or size there updates the setting.
@MainActor
final class MacFontPanel: NSObject, NSFontChanging {
    static let shared = MacFontPanel()
    private var current = NSFont.systemFont(ofSize: 13)
    private var onChange: ((String, Double) -> Void)?

    func show(current name: String, size: Double, onChange: @escaping (String, Double) -> Void) {
        self.onChange = onChange
        current = NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(current, isMultiple: false)
        manager.orderFrontFontPanel(self)
    }

    func changeFont(_ sender: NSFontManager?) {
        guard let sender else { return }
        current = sender.convert(current)
        // The system font's internal name (".AppleSystemUIFont") isn't usable by name; keep "System".
        let name = current.fontName.hasPrefix(".") ? "" : current.fontName
        onChange?(name, Double(current.pointSize))
    }

    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask {
        [.collection, .face, .size]
    }
}
#endif
