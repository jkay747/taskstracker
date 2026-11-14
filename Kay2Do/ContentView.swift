import SwiftUI
import CoreData

enum SidebarItem: Hashable {
    case all
    case priorities
    /// A category, by its uid.
    case category(String)
}

struct ContentView: View {
    @EnvironmentObject private var store: Persistence
    @FetchRequest(fetchRequest: TaskCategory.all) private var categories: FetchedResults<TaskCategory>
    @FetchRequest(fetchRequest: TaskItem.all) private var tasks: FetchedResults<TaskItem>
    @FetchRequest(fetchRequest: Board.all) private var boards: FetchedResults<Board>

    @State private var selection: SidebarItem? = .all
    @State private var showSettings = false
    @State private var shareRequest: TaskCategory?

    private var listName: String {
        let name = boards.first?.listName ?? ""
        return name.isEmpty ? "Kay2-Do" : name
    }

    private var mine: [TaskCategory] { categories.filter { store.isMine($0) } }
    private var fromOthers: [TaskCategory] {
        categories.filter { !store.isMine($0) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    SidebarRow(title: "All Tasks", systemImage: "tray.full", colorIndex: nil, shared: false,
                               count: tasks.filter { !$0.isDone }.count,
                               late: tasks.filter { $0.isLate }.count)
                        .tag(SidebarItem.all)
                    SidebarRow(title: "Top Priorities", systemImage: "star", colorIndex: nil, shared: false,
                               count: tasks.filter { !$0.isDone && $0.isStarred }.count,
                               late: 0)
                        .tag(SidebarItem.priorities)
                }
                if !mine.isEmpty {
                    Section("Categories") {
                        ForEach(mine) { category in
                            categoryRow(category)
                        }
                    }
                }
                if !fromOthers.isEmpty {
                    Section("Shared with me") {
                        ForEach(fromOthers) { category in
                            categoryRow(category)
                        }
                    }
                }
            }
            .navigationTitle(listName)
            .toolbar {
                ToolbarItem {
                    Button {
                        showSettings = true
                    } label: {
                        Label("List Settings", systemImage: "slider.horizontal.3")
                    }
                }
            }
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            #endif
        } detail: {
            NavigationStack {
                TaskListView(filter: selection ?? .all)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(\.managedObjectContext, store.context)
                .environmentObject(store)
        }
        .categorySharing($shareRequest)
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onAppear {
            store.tidy()
            store.refreshShares()
        }
    }

    private func categoryRow(_ category: TaskCategory) -> some View {
        SidebarRow(title: category.name, systemImage: nil, colorIndex: category.color,
                   shared: store.isShared(category),
                   count: tasks.filter { !$0.isDone && $0.category == category }.count,
                   late: tasks.filter { $0.isLate && $0.category == category }.count)
            .tag(SidebarItem.category(category.uid ?? ""))
            .contextMenu {
                Button(store.isShared(category) ? "Manage Sharing…" : "Share Category…") {
                    shareRequest = category
                }
            }
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String?
    let colorIndex: Int?
    let shared: Bool
    let count: Int
    let late: Int

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
            } else {
                CategorySwatch(colorIndex: colorIndex)
                    .frame(width: 18)
            }
            Text(title)
                .lineLimit(1)
            if shared {
                Image(systemName: "person.2.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Shared")
            }
            Spacer(minLength: 4)
            if late > 0 {
                Text("\(late) overdue")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.red)
            }
            Text("\(count)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
