import Foundation
import SwiftUI

/// Everything the screens show, loaded from Supabase. Changes show on screen
/// at once and are sent to the server in order behind the scenes; the list is
/// refreshed every few seconds while the app is open, so edits made on the
/// web or on another device appear here too.
@MainActor
final class Store: ObservableObject {
    enum Phase: Equatable { case needsConfig, signedOut, loading, noList, ready }

    static let maxCategories = 12
    static let pollSeconds: UInt64 = 12

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var lists: [TaskList] = []
    @Published private(set) var listID: String?
    @Published private(set) var list: TaskList?
    @Published private(set) var role = ""
    @Published private(set) var categories: [TaskCategory] = []
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var people: [Member] = []
    @Published private(set) var myName = ""
    @Published var errorMessage: String?
    @Published private(set) var notice: String?

    private(set) var backend: Backend?
    private var writeChain: Task<Void, Never>?
    private var pendingWrites = 0
    private var writeGeneration = 0
    private var poller: Task<Void, Never>?
    private var weekSave: Task<Void, Never>?

    var myID: String { backend?.session?.userID ?? "" }
    var myEmail: String { backend?.session?.email ?? "" }
    var me: Person { .user(myID) }
    var isOwner: Bool { role == "owner" }
    var isManager: Bool { role == "owner" || role == "editor" }
    var listName: String { list?.name.isEmpty == false ? list!.name : "Kay2-Do" }
    var serverURL: String { backend?.baseURL ?? "" }

    init() {
        configure()
    }

    // MARK: Connecting and signing in

    private func configure() {
        let defaults = UserDefaults.standard
        let url = SupabaseConfig.url.isEmpty ? (defaults.string(forKey: "supabaseURL") ?? "") : SupabaseConfig.url
        let key = SupabaseConfig.anonKey.isEmpty ? (defaults.string(forKey: "supabaseAnonKey") ?? "") : SupabaseConfig.anonKey
        guard url.hasPrefix("https://") || url.hasPrefix("http://"), !key.isEmpty else {
            backend = nil
            phase = .needsConfig
            return
        }
        let backend = Backend(url: url, anonKey: key)
        self.backend = backend
        if backend.session == nil {
            phase = .signedOut
        } else {
            phase = .loading
            Task { await afterSignIn() }
        }
    }

    func connect(url: String, anonKey: String) {
        let defaults = UserDefaults.standard
        defaults.set(url.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "supabaseURL")
        defaults.set(anonKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "supabaseAnonKey")
        configure()
    }

    /// Only offered when the connection was pasted in rather than built in.
    var canChangeServer: Bool { SupabaseConfig.url.isEmpty }

    func disconnect() async {
        await signOut()
        UserDefaults.standard.removeObject(forKey: "supabaseURL")
        UserDefaults.standard.removeObject(forKey: "supabaseAnonKey")
        configure()
    }

    func sendCode(to email: String) async throws {
        guard let backend else { return }
        try await backend.sendCode(to: email.trimmingCharacters(in: .whitespaces).lowercased())
    }

    func verify(email: String, code: String) async throws {
        guard let backend else { return }
        try await backend.verify(email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                                 code: code.filter { !$0.isWhitespace })
        phase = .loading
        await afterSignIn()
    }

    /// Handles the emailed sign-in link when it opens the app.
    func open(_ url: URL) {
        guard let backend else { return }
        Task {
            do {
                if try await backend.completeSignIn(from: url) {
                    notice = nil
                    phase = .loading
                    await afterSignIn()
                }
            } catch {
                notice = error.localizedDescription
                if backend.session == nil { phase = .signedOut }
            }
        }
    }

    func signOut() async {
        stopPolling()
        await backend?.signOut()
        clear()
        if backend != nil { phase = .signedOut }
    }

    private func clear() {
        lists = []; listID = nil; list = nil; role = ""
        categories = []; tasks = []; people = []; myName = ""
    }

    func afterSignIn() async {
        guard let backend else { return }
        do {
            _ = try? await backend.rpcValue("accept_invites", [:])
            struct Profile: Decodable { let display_name: String? }
            let profiles: [Profile] = try await backend.select("profiles", [("id", "eq." + myID)], select: "display_name")
            let name = profiles.first?.display_name ?? ""
            myName = name.isEmpty ? String(myEmail.split(separator: "@").first ?? "") : name
            try await loadLists()
        } catch {
            handle(error, doing: "load your lists")
            if phase == .loading { phase = backend.session == nil ? .signedOut : .noList }
        }
    }

    // MARK: Loading

    func loadLists(prefer preferred: String? = nil) async throws {
        guard let backend else { return }
        let found: [TaskList] = try await backend.select("lists", [], order: "created_at")
        lists = found
        guard !found.isEmpty else {
            listID = nil; list = nil
            phase = .noList
            return
        }
        let saved = preferred ?? UserDefaults.standard.string(forKey: "listID")
        let pick = found.first { $0.id == saved } ?? found[0]
        try await open(pick.id)
    }

    func switchList(to id: String) {
        Task {
            do { try await open(id) } catch { handle(error, doing: "open that list") }
        }
    }

    private func open(_ id: String) async throws {
        if id != listID {
            categories = []; tasks = []; people = []
        }
        listID = id
        UserDefaults.standard.set(id, forKey: "listID")
        try await reload()
        if phase != .ready && listID != nil { phase = .ready }
        startPolling()
    }

    /// Fetches the open list again. A refresh that overlaps one of your own
    /// changes is dropped so it can't undo what's on screen.
    func reload() async throws {
        guard let backend, let id = listID else { return }
        let generation = writeGeneration
        struct RoleRow: Decodable { let role: String }
        async let listRows: [TaskList] = backend.select("lists", [("id", "eq." + id)])
        async let categoryRows: [TaskCategory] = backend.select("categories", [("list_id", "eq." + id)], order: "sort_order,created_at")
        async let taskRows: [TaskItem] = backend.select("tasks", [("list_id", "eq." + id)])
        async let peopleRows: [Member] = backend.rpc("list_people", ["p_list": id])
        async let roleRows: [RoleRow] = backend.select("list_members", [("list_id", "eq." + id), ("user_id", "eq." + myID)], select: "role")
        let (l, c, t, p, r) = try await (listRows, categoryRows, taskRows, peopleRows, roleRows)
        guard id == listID else { return }
        guard let row = l.first, let myRole = r.first?.role else {
            notice = "You're no longer on that list."
            UserDefaults.standard.removeObject(forKey: "listID")
            listID = nil
            try await loadLists()
            return
        }
        guard generation == writeGeneration, pendingWrites == 0 else { return }
        var fresh = row
        if weekSave != nil, let current = list, current.id == row.id {
            fresh.weekOf = current.weekOf; fresh.theme = current.theme; fresh.because = current.because
        }
        if list != fresh { list = fresh }
        if role != myRole { role = myRole }
        if categories != c { categories = c }
        if tasks != t { tasks = t }
        if people != p { people = p }
        if let index = lists.firstIndex(where: { $0.id == row.id }), lists[index].name != row.name {
            lists[index].name = row.name
        }
    }

    func refreshNow() {
        Task {
            do { try await reload() } catch { handle(error, doing: "refresh the list") }
        }
    }

    func startPolling() {
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Store.pollSeconds * 1_000_000_000)
                guard let self else { return }
                guard !Task.isCancelled, self.phase == .ready else { continue }
                do {
                    try await self.reload()
                } catch let error as BackendError where error.signedOut {
                    self.handle(error, doing: "refresh the list")
                } catch {
                    // A missed refresh is fine; the next one will catch up.
                }
            }
        }
    }

    func stopPolling() {
        poller?.cancel()
        poller = nil
    }

    /// Foreground: refresh at once and keep refreshing. Background: stop.
    /// Set while the list is shown on the Mac desktop, so it keeps updating in the background.
    var keepsRefreshing = false

    func setActive(_ active: Bool) {
        if active {
            guard phase == .ready else { return }
            refreshNow()
            startPolling()
        } else if !keepsRefreshing {
            stopPolling()
        }
    }

    // MARK: Writing

    private func write(_ action: String, _ operation: @escaping (Backend) async throws -> Void) {
        guard let backend else { return }
        pendingWrites += 1
        writeGeneration += 1
        let previous = writeChain
        writeChain = Task { [weak self] in
            await previous?.value
            do {
                try await operation(backend)
                self?.pendingWrites -= 1
            } catch {
                guard let self else { return }
                self.pendingWrites -= 1
                self.handle(error, doing: action)
                try? await self.reload()
            }
        }
    }

    func handle(_ error: Error, doing action: String) {
        if let error = error as? BackendError, error.signedOut {
            stopPolling()
            clear()
            phase = .signedOut
            notice = error.message
            return
        }
        errorMessage = "Couldn't \(action). \(error.localizedDescription)"
    }

    func clearNotice() { notice = nil }

    // MARK: Lists

    func createList(named name: String) async throws {
        guard let backend else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let id = try await backend.rpcValue("create_list", ["p_name": trimmed.isEmpty ? "Kay2-Do" : String(trimmed.prefix(60))])
        try await loadLists(prefer: (id as? String)?.lowercased())
    }

    func checkForInvites() async {
        phase = .loading
        await afterSignIn()
    }

    func setWeek(weekOf: Date?? = nil, theme: String? = nil, because: String? = nil) {
        guard var current = list, isManager else { return }
        if let weekOf { current.weekOf = weekOf.map(DayString.string) }
        if let theme { current.theme = String(theme.prefix(140)) }
        if let because { current.because = String(because.prefix(140)) }
        guard current != list else { return }
        list = current
        weekSave?.cancel()
        weekSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, !Task.isCancelled, let latest = self.list else { return }
            self.weekSave = nil
            let fields: [String: Any] = ["week_of": latest.weekOf ?? NSNull(), "theme": latest.theme, "because": latest.because]
            self.write("save the weekly theme") { try await $0.update("lists", fields: fields, where: [("id", "eq." + latest.id)]) }
        }
    }

    // MARK: Weekly quote

    /// What to show this week, or nil when the list has quotes turned off.
    var weeklyQuote: Quote? {
        guard let list, list.showQuote else { return nil }
        if !list.quote.isEmpty { return Quote(text: list.quote, by: list.quoteBy) }
        return Quote.weekly()
    }

    /// Saves a typed or picked quote; a blank quote goes back to the weekly pick.
    func setQuote(_ text: String, by: String) {
        guard isManager, var current = list else { return }
        let quote = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
        let author = quote.isEmpty ? "" : String(by.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        current.quote = quote
        current.quoteBy = author
        list = current
        let id = current.id
        write("save the quote") { try await $0.update("lists", fields: ["quote": quote, "quote_by": author], where: [("id", "eq." + id)]) }
    }

    func setShowQuote(_ show: Bool) {
        guard isManager, var current = list, current.showQuote != show else { return }
        current.showQuote = show
        list = current
        let id = current.id
        write("save the quote setting") { try await $0.update("lists", fields: ["show_quote": show], where: [("id", "eq." + id)]) }
    }

    // MARK: Tasks

    func permissions(for task: TaskItem) -> (edit: Bool, delete: Bool) {
        guard !role.isEmpty else { return (false, false) }
        if isManager { return (true, true) }
        let mine = task.createdBy == myID
        return (mine || task.involves(me), mine)
    }

    func canEdit(_ task: TaskItem) -> Bool { permissions(for: task).edit }
    func canDelete(_ task: TaskItem) -> Bool { permissions(for: task).delete }

    func newTask(title: String = "", in categoryKey: String?) -> TaskItem {
        TaskItem(id: UUID().uuidString.lowercased(), listID: listID ?? "", categoryKey: categoryKey ?? categories.first?.key,
                 title: title, createdBy: myID)
    }

    func add(_ task: TaskItem) {
        var task = task
        task.title = String(task.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !task.title.isEmpty, listID != nil else { return }
        tasks.append(task)
        write("add that task") { try await $0.insert("tasks", task) }
    }

    func save(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return add(task) }
        var task = task
        task.title = String(task.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !task.title.isEmpty, tasks[index] != task else { return }
        tasks[index] = task
        write("save that task") { try await $0.update("tasks", task, where: [("id", "eq." + task.id)]) }
    }

    func delete(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        write("delete that task") { try await $0.delete("tasks", where: [("id", "eq." + task.id)]) }
    }

    func toggleDone(_ task: TaskItem) {
        var copy = task
        copy.setDone(!task.done, by: myID)
        save(copy)
    }

    func toggleStar(_ task: TaskItem) {
        var copy = task
        copy.priority.toggle()
        save(copy)
    }

    // MARK: People

    func name(of person: Person) -> String {
        switch person {
        case .named(let name): return name
        case .user(let id):
            let member = people.first { $0.userID == id }
            if id == myID { return myName.isEmpty ? "You" : myName }
            return member?.name ?? "Someone"
        }
    }

    /// Members you can pick as an owner or add to a task, you first.
    var memberPeople: [Person] {
        var out: [Person] = [me]
        for member in people where !member.pending {
            if let id = member.userID, id != myID { out.append(.user(id)) }
        }
        return out
    }

    /// Names and emails typed onto tasks that aren't linked to an account yet.
    var unlinkedPeople: [Person] {
        var seen = Set<String>()
        var out: [Person] = []
        for member in people where member.pending {
            if let email = member.email, seen.insert("n:" + email).inserted { out.append(.named(email)) }
        }
        for task in tasks {
            for person in task.people where !person.isLinked {
                if seen.insert(person.key).inserted { out.append(person) }
            }
        }
        return out
    }

    func setMyName(_ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(80))
        guard !trimmed.isEmpty, trimmed != myName else { return }
        myName = trimmed
        let id = myID
        write("save your name") { try await $0.update("profiles", fields: ["display_name": trimmed], where: [("id", "eq." + id)]) }
    }

    /// Returns "added" (they already had an account) or "invited".
    func invite(email: String, role: String) async throws -> String {
        guard let backend, let id = listID else { return "" }
        let result = try await backend.rpcValue("invite_member", ["p_list": id, "p_email": email.trimmingCharacters(in: .whitespaces).lowercased(), "p_role": role])
        try? await reload()
        return (result as? String) ?? "invited"
    }

    func setRole(_ member: Member, to role: String) {
        guard let id = listID, isOwner, member.role != "owner" else { return }
        if let index = people.firstIndex(of: member) { people[index].role = role }
        if member.pending, let email = member.email {
            write("change that role") { try await $0.update("invites", fields: ["role": role], where: [("list_id", "eq." + id), ("email", "eq." + email)]) }
        } else if let user = member.userID {
            write("change that role") { try await $0.update("list_members", fields: ["role": role], where: [("list_id", "eq." + id), ("user_id", "eq." + user)]) }
        }
    }

    func remove(_ member: Member) {
        guard let id = listID, isOwner, member.role != "owner" else { return }
        people.removeAll { $0 == member }
        if member.pending, let email = member.email {
            write("remove that invite") { try await $0.delete("invites", where: [("list_id", "eq." + id), ("email", "eq." + email)]) }
        } else if let user = member.userID {
            write("remove that person") { try await $0.delete("list_members", where: [("list_id", "eq." + id), ("user_id", "eq." + user)]) }
        }
    }

    func leaveList() async {
        guard let backend, let id = listID, !isOwner else { return }
        do {
            try await backend.delete("list_members", where: [("list_id", "eq." + id), ("user_id", "eq." + myID)])
            UserDefaults.standard.removeObject(forKey: "listID")
            listID = nil
            try await loadLists()
        } catch {
            handle(error, doing: "leave the list")
        }
    }

    func inviteMessage() -> String {
        "\(myName) shared the list “\(listName)” with you on Kay2-Do.\n\n"
            + "Open the Kay2-Do app or the web list and sign in with this email address; you'll get a sign-in link by email. "
            + "Then use Owner → Mine to see what's yours and check things off as you finish them."
    }

    // MARK: List settings

    struct CategoryDraft: Identifiable, Equatable {
        var id: String
        var existing: Bool
        var key: String
        var label: String
        var color: Int
        var removing = false
        var moveTo: String?
    }

    func categoryDrafts() -> [CategoryDraft] {
        categories.map { CategoryDraft(id: $0.id, existing: true, key: $0.key, label: $0.label, color: $0.color) }
    }

    func taskCount(inCategory key: String) -> Int {
        tasks.filter { $0.categoryKey == key }.count
    }

    /// Saves the settings sheet: list name and categories (managers only).
    func applySettings(listName newName: String, drafts: [CategoryDraft]) {
        guard isManager, let id = listID, var current = list else { return }
        let name = String(newName.trimmingCharacters(in: .whitespaces).prefix(60))
        if !name.isEmpty, name != current.name {
            current.name = name
            list = current
            if let index = lists.firstIndex(where: { $0.id == id }) { lists[index].name = name }
            write("rename the list") { try await $0.update("lists", fields: ["name": name], where: [("id", "eq." + id)]) }
        }

        let keep = drafts.filter { !$0.removing }
        var next: [TaskCategory] = []
        for (order, draft) in keep.enumerated() {
            let label = String(draft.label.trimmingCharacters(in: .whitespaces).prefix(40))
            let category = TaskCategory(id: draft.id, listID: id, key: draft.key,
                                        label: label.isEmpty ? "Untitled" : label, color: draft.color, sortOrder: order)
            next.append(category)
            let old = categories.first { $0.id == draft.id }
            let fields: [String: Any] = ["list_id": id, "key": category.key, "label": category.label,
                                         "color": category.color, "sort_order": order]
            if !draft.existing {
                var insert = fields
                insert["id"] = draft.id
                write("add a category") { _ = try await $0.request("POST", "rest/v1/categories", body: insert, prefer: "return=minimal") }
            } else if old != category {
                write("save a category") { try await $0.update("categories", fields: fields, where: [("id", "eq." + draft.id)]) }
            }
        }
        for draft in drafts where draft.removing {
            if let target = draft.moveTo ?? keep.first?.key {
                for index in tasks.indices where tasks[index].categoryKey == draft.key { tasks[index].categoryKey = target }
                write("move tasks") {
                    try await $0.update("tasks", fields: ["category_key": target], where: [("list_id", "eq." + id), ("category_key", "eq." + draft.key)])
                }
            }
            if draft.existing {
                write("remove a category") { try await $0.delete("categories", where: [("id", "eq." + draft.id)]) }
            }
        }
        categories = next
    }
}
