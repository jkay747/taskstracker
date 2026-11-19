import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store

    @State private var myName = ""
    @State private var listName = ""
    @State private var showQuote = true
    @State private var background = ""
    @State private var backgroundStyle = "balanced"
    @State private var uploadedBackgrounds: [String] = []
    @State private var drafts: [Store.CategoryDraft] = []
    @State private var newCategory = ""
    @State private var removing: Store.CategoryDraft?
    @State private var loaded = false

    private var live: [Store.CategoryDraft] { drafts.filter { !$0.removing } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $myName)
                } header: {
                    Text("Your name")
                } footer: {
                    Text("How you appear to everyone on your lists. Signed in as \(store.myEmail).")
                }

                if store.isManager {
                    Section("List name") {
                        TextField("List name", text: $listName)
                        Toggle("Show a weekly quote", isOn: $showQuote)
                    }
                    categoriesSection
                    #if os(macOS)
                    BackgroundSettings(value: $background, style: $backgroundStyle, uploaded: $uploadedBackgrounds)
                    #endif
                }

                PeopleSettings()

                Section {
                    if !store.isOwner {
                        Button("Leave This List", role: .destructive) {
                            Task {
                                await store.leaveList()
                                dismiss()
                            }
                        }
                    }
                    Button("Sign Out") {
                        Task { await store.signOut() }
                    }
                    if store.canChangeServer {
                        Button("Connect to a Different Supabase Project") {
                            Task { await store.disconnect() }
                        }
                    }
                } footer: {
                    Text("Connected to \(store.serverURL)")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("List Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.discardUploads(uploadedBackgrounds)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setMyName(myName)
                        if store.isManager {
                            store.applySettings(listName: listName, drafts: drafts)
                            store.setShowQuote(showQuote)
                            #if os(macOS)
                            store.setBackground(background, style: backgroundStyle)
                            #endif
                        }
                        store.discardUploads(uploadedBackgrounds)
                        dismiss()
                    }
                    .disabled(live.contains { $0.label.trimmingCharacters(in: .whitespaces).isEmpty })
                }
            }
            .confirmationDialog(
                removing.map { "“\($0.label)” has \(store.taskCount(inCategory: $0.key)) task(s). Where should they go?" } ?? "",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                titleVisibility: .visible
            ) {
                ForEach(live.filter { $0.id != removing?.id }) { other in
                    Button("Move to \(other.label)") {
                        if let target = removing { markRemoved(target, moveTo: other.key) }
                    }
                }
                Button("Cancel", role: .cancel) { removing = nil }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            myName = store.myName
            listName = store.listName
            showQuote = store.list?.showQuote ?? true
            background = store.list?.background ?? ""
            backgroundStyle = store.backgroundStyle
            drafts = store.categoryDrafts()
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
    }

    private var categoriesSection: some View {
        Section {
            ForEach($drafts) { $draft in
                if !draft.removing {
                    CategoryRow(draft: $draft,
                                canMoveUp: liveIndex(of: draft) > 0,
                                canMoveDown: liveIndex(of: draft) < live.count - 1,
                                canRemove: live.count > 1,
                                moveUp: { move(draft, by: -1) },
                                moveDown: { move(draft, by: 1) },
                                remove: { requestRemove(draft) })
                }
            }
            ForEach(drafts.filter(\.removing)) { draft in
                HStack {
                    Text(draft.label).strikethrough().foregroundStyle(.secondary)
                    Spacer()
                    Button("Undo") {
                        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
                            drafts[index].removing = false
                            drafts[index].moveTo = nil
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("New category name", text: $newCategory)
                    .onSubmit(addCategory)
                Button("Add", action: addCategory)
                    .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty || live.count >= Store.maxCategories)
            }
        } header: {
            Text("Categories")
        } footer: {
            Text("Tap a color to change it. A list can have up to \(Store.maxCategories) categories. Changes apply when you tap Save.")
        }
    }

    private func liveIndex(of draft: Store.CategoryDraft) -> Int {
        live.firstIndex { $0.id == draft.id } ?? 0
    }

    private func addCategory() {
        let label = String(newCategory.trimmingCharacters(in: .whitespaces).prefix(40))
        guard !label.isEmpty, live.count < Store.maxCategories else { return }
        let used = Set(live.map(\.color))
        let color = (0..<Palette.count).first { !used.contains($0) } ?? live.count % Palette.count
        let key = Slug.make(label, taken: Set(drafts.map(\.key)))
        drafts.append(Store.CategoryDraft(id: UUID().uuidString.lowercased(), existing: false, key: key, label: label, color: color))
        newCategory = ""
    }

    private func move(_ draft: Store.CategoryDraft, by delta: Int) {
        let order = live
        guard let from = order.firstIndex(where: { $0.id == draft.id }), order.indices.contains(from + delta),
              let a = drafts.firstIndex(where: { $0.id == order[from].id }),
              let b = drafts.firstIndex(where: { $0.id == order[from + delta].id }) else { return }
        drafts.swapAt(a, b)
    }

    private func requestRemove(_ draft: Store.CategoryDraft) {
        if store.taskCount(inCategory: draft.key) == 0 {
            markRemoved(draft, moveTo: nil)
        } else {
            removing = draft
        }
    }

    private func markRemoved(_ draft: Store.CategoryDraft, moveTo: String?) {
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index].removing = true
            drafts[index].moveTo = moveTo
        }
        removing = nil
    }
}

private struct CategoryRow: View {
    @Binding var draft: Store.CategoryDraft
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canRemove: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                draft.color = (draft.color + 1) % Palette.count
            } label: {
                CategorySwatch(colorIndex: draft.color, size: 22)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Change color for \(draft.label)")

            TextField("Category name", text: $draft.label)

            Button(action: moveUp) { Image(systemName: "arrow.up") }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
                .accessibilityLabel("Move up")
            Button(action: moveDown) { Image(systemName: "arrow.down") }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
                .accessibilityLabel("Move down")
            Button(role: .destructive, action: remove) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(!canRemove)
                .accessibilityLabel("Remove \(draft.label)")
        }
    }
}

/// Who's on the list, and inviting people by email (owner only).
private struct PeopleSettings: View {
    @EnvironmentObject private var store: Store
    @State private var email = ""
    @State private var role = "contributor"
    @State private var busy = false
    @State private var status: String?

    private var sorted: [Member] {
        store.people.sorted { a, b in
            if (a.role == "owner") != (b.role == "owner") { return a.role == "owner" }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        Section {
            ForEach(sorted) { member in
                MemberRow(member: member)
            }
            if store.isOwner {
                TextField("Email to invite", text: $email)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                    .onSubmit(invite)
                Picker("Role", selection: $role) {
                    Text("Contributor").tag("contributor")
                    Text("Editor").tag("editor")
                }
                Button("Invite", action: invite)
                    .disabled(busy || !email.contains("@"))
                ShareLink(item: store.inviteMessage()) {
                    Label("Send Invite Message…", systemImage: "square.and.arrow.up")
                }
                if let status {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("People")
        } footer: {
            Text(store.isOwner
                 ? "Contributors add tasks and check off their own. Editors can change anything except who's on the list. Inviting doesn't send an email by itself: send them the invite message so they know to sign in with that address, in this app or on the web."
                 : "Only the list owner can invite people or change roles.")
        }
    }

    private func invite() {
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard address.contains("@"), !busy else { return }
        busy = true
        status = nil
        Task {
            defer { busy = false }
            do {
                let result = try await store.invite(email: address, role: role)
                status = result == "added" ? "\(address) already had an account and is on the list now." : "\(address) is invited. Send them the invite message."
                email = ""
            } catch {
                status = error.localizedDescription
            }
        }
    }
}

private struct MemberRow: View {
    let member: Member
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(member.userID == store.myID ? member.name + " (you)" : member.name)
                if member.pending {
                    Text("Invited, hasn't signed in yet").font(.caption).foregroundStyle(.secondary)
                } else if let email = member.email, member.userID != store.myID, email != member.name {
                    Text(email).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.isOwner && member.role != "owner" {
                Picker("Role", selection: Binding(
                    get: { member.role },
                    set: { store.setRole(member, to: $0) }
                )) {
                    Text("Contributor").tag("contributor")
                    Text("Editor").tag("editor")
                }
                .labelsHidden()
                .fixedSize()
                Button(role: .destructive) {
                    store.remove(member)
                } label: {
                    Image(systemName: "person.badge.minus")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(member.name)")
            } else {
                Text(member.roleLabel).foregroundStyle(.secondary)
            }
        }
    }
}
