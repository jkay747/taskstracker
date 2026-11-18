#if os(macOS)
import SwiftUI

/// What's drawn on the desktop: the list name and weekly theme, top
/// priorities, then each category's open tasks. Completed tasks drop off.
struct WallpaperView: View {
    let fillsScreen: Bool

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var wall: WallpaperController

    private var scale: CGFloat { wall.textSize.scale }
    private var rowLimit: Int { fillsScreen ? 12 : 6 }

    var body: some View {
        Group {
            if store.phase == .ready {
                if fillsScreen { fullScreen } else { sidePanel }
            } else {
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kay2-Do").font(display(26))
                        Text("Open Kay2-Do and sign in to show your list here.")
                            .font(body(14)).foregroundStyle(.secondary)
                    }
                }
                .onTapGesture { wall.openApp() }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(fillsScreen ? 32 : 0)
    }

    // MARK: Layouts

    private var sidePanel: some View {
        card {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18 * scale) {
                    header
                    prioritiesBlock
                    ForEach(visibleCategories) { category in
                        categoryBlock(category)
                    }
                    if visibleCategories.isEmpty && starred.isEmpty {
                        Text(wall.mineOnly ? "Nothing open for you. Nice." : "Nothing open. Nice.")
                            .font(body(14)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var fullScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            card { header }
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260 * scale, maximum: 420 * scale), spacing: 20, alignment: .top)],
                          alignment: .leading, spacing: 20) {
                    if !starred.isEmpty { card { prioritiesBlock } }
                    ForEach(visibleCategories) { category in
                        card { categoryBlock(category) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Blocks

    private var header: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            Text(store.listName)
                .font(display(fillsScreen ? 40 : 28))
                .lineLimit(2)
                .onTapGesture { wall.openApp() }
            if let theme = store.list?.theme, !theme.isEmpty {
                let why = store.list?.because ?? ""
                Text("This week will be \(theme)" + (why.isEmpty ? "" : ", because \(why)"))
                    .font(.system(size: 15 * scale, design: .serif).italic())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let week = DayString.date(store.list?.weekOf) {
                Text("Week of " + week.formatted(date: .abbreviated, time: .omitted))
                    .font(label(10)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var prioritiesBlock: some View {
        if !starred.isEmpty {
            VStack(alignment: .leading, spacing: 8 * scale) {
                Text("TOP PRIORITIES").font(label(10)).foregroundStyle(.secondary)
                ForEach(Array(starred.prefix(3).enumerated()), id: \.element.id) { index, task in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.system(size: 20 * scale, design: .serif).italic())
                            .foregroundStyle(.secondary)
                        WallTaskRow(task: task, showCategory: true)
                    }
                }
            }
        }
    }

    private func categoryBlock(_ category: TaskCategory) -> some View {
        let open = openTasks(in: category)
        return VStack(alignment: .leading, spacing: 7 * scale) {
            HStack(spacing: 7) {
                CategorySwatch(colorIndex: category.color, size: 9 * scale)
                Text(category.name.uppercased()).font(label(11))
                Spacer()
                Text("\(open.count)").font(label(11)).foregroundStyle(.secondary).monospacedDigit()
            }
            ForEach(open.prefix(rowLimit)) { task in
                WallTaskRow(task: task, showCategory: false)
            }
            if open.count > rowLimit {
                Text("+\(open.count - rowLimit) more")
                    .font(body(11)).foregroundStyle(.secondary)
                    .onTapGesture { wall.openApp() }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(20 * scale)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.primary.opacity(0.08)))
    }

    // MARK: Data

    private func included(_ task: TaskItem) -> Bool {
        !task.done && (!wall.mineOnly || task.involves(store.me))
    }

    private var starred: [TaskItem] {
        store.tasks.filter { included($0) && $0.priority }.sorted(by: TaskItem.order)
    }

    private func openTasks(in category: TaskCategory) -> [TaskItem] {
        store.tasks.filter { included($0) && $0.categoryKey == category.key }.sorted(by: TaskItem.order)
    }

    private var visibleCategories: [TaskCategory] {
        store.categories.filter { !openTasks(in: $0).isEmpty }
    }

    // MARK: Type

    private func display(_ size: CGFloat) -> Font { .system(size: size * scale, weight: .semibold, design: .serif).italic() }
    private func body(_ size: CGFloat) -> Font { .system(size: size * scale) }
    private func label(_ size: CGFloat) -> Font { .system(size: size * scale, weight: .bold).width(.expanded) }
}

private struct WallTaskRow: View {
    let task: TaskItem
    let showCategory: Bool

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var wall: WallpaperController

    private var scale: CGFloat { wall.textSize.scale }
    private var editable: Bool { wall.clickable && store.canEdit(task) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                store.toggleDone(task)
            } label: {
                Image(systemName: "square")
                    .font(.system(size: 13 * scale))
            }
            .buttonStyle(.plain)
            .disabled(!editable)
            .help(editable ? "Mark done" : "")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 14 * scale))
                    .lineLimit(2)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 11 * scale, weight: task.isLate ? .semibold : .regular))
                        .foregroundStyle(task.isLate ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { wall.openApp() }

            if task.priority && !showCategory {
                Image(systemName: "star.fill")
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var meta: String {
        var parts: [String] = []
        if showCategory, let category = store.categories.first(where: { $0.key == task.categoryKey }) {
            parts.append(category.name)
        }
        if let owner = task.owner, owner != store.me { parts.append(store.name(of: owner)) }
        if let due = task.dueDate { parts.append(DueText.label(for: due)) }
        return parts.joined(separator: " · ")
    }
}
#endif
