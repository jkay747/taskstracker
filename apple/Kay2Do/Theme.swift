import SwiftUI

/// The same eight category colors as the web list, in light and dark.
enum Palette {
    static let count = 8
    private static let light: [UInt32] = [0x1F8A70, 0x2443D6, 0x8A2F6B, 0xB06D00, 0x0E7490, 0xB4361F, 0x5B6B1A, 0x6D4BC4]
    private static let dark: [UInt32] = [0x4CC3A2, 0x7D93FF, 0xD77AB6, 0xE3A440, 0x4CC0DE, 0xF0856E, 0xB5C95A, 0xA98CF5]

    static func color(_ index: Int, scheme: ColorScheme) -> Color {
        let i = ((index % count) + count) % count
        return Color(hex: scheme == .dark ? dark[i] : light[i])
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct CategorySwatch: View {
    let colorIndex: Int?
    var size: CGFloat = 10
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(colorIndex.map { Palette.color($0, scheme: scheme) } ?? Color.secondary)
            .frame(width: size, height: size)
    }
}

enum DueText {
    static func label(for due: Date) -> String {
        let cal = Calendar.current
        let now = Date()
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day ?? 0
        switch days {
        case 0: return "Due today"
        case 1: return "Due tomorrow"
        case -1: return "Due yesterday"
        default:
            let sameYear = cal.component(.year, from: due) == cal.component(.year, from: now)
            let text = sameYear
                ? due.formatted(.dateTime.month(.abbreviated).day())
                : due.formatted(.dateTime.month(.abbreviated).day().year())
            return (days < 0 ? "Was due " : "Due ") + text
        }
    }
}
