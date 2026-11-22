import SwiftUI

/// The week's quote, as shown in the This Week section.
struct QuoteRow: View {
    let quote: Quote
    var size: CGFloat = 17

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(quote.text)
                .font(.system(size: size, design: .serif).italic())
                .fixedSize(horizontal: false, vertical: true)
            if !quote.attribution.isEmpty {
                Text("— " + quote.attribution)
                    .font(.system(size: size * 0.72))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle().fill(Palette.color(3, scheme: .light)).frame(width: 3)
        }
        .textSelection(.enabled)
    }
}

/// Find a quote on Wikiquote, type one, step through the built-in ones, or go back to the weekly pick.
struct QuoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: Store
    @State private var text = ""
    @State private var by = ""
    @State private var offset = 1
    @State private var loaded = false

    @State private var term = ""
    @State private var results: [FoundQuote] = []
    @State private var picked: FoundQuote?
    @State private var searching = false
    @State private var searchStatus: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                findSection
                Section {
                    TextField("Leave blank for this week's pick", text: $text, axis: .vertical)
                        .lineLimit(2...6)
                    TextField("Who said it", text: $by)
                } footer: {
                    if text.isEmpty, let pick = Quote.weekly() {
                        Text("This week's pick: “\(pick.text)” — \(pick.attribution)")
                    }
                }
                Section {
                    Button("Another Pick") { another() }
                    Button("Use This Week's Pick") {
                        store.setQuote("", by: "")
                        dismiss()
                    }
                } footer: {
                    Text("Built-in picks change every Monday and are the same for everyone on the list. A quote you type stays until you change it.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("This Week's Quote")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setQuote(text, by: by)
                        dismiss()
                    }
                }
            }
        }
        .onDisappear { searchTask?.cancel() }
        .onAppear {
            guard !loaded, let list = store.list else { return }
            loaded = true
            text = list.quote
            by = list.quoteBy
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    private var findSection: some View {
        Section {
            HStack {
                TextField("A person or a topic: Rumi, courage…", text: $term)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    #endif
                    .onSubmit(runSearch)
                if searching {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Search", action: runSearch)
                        .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            ForEach(results) { quote in
                Button {
                    picked = quote
                    text = quote.text
                    by = quote.by
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("“\(quote.text)”")
                                .font(.system(.body, design: .serif).italic())
                                .foregroundStyle(Color.primary)
                                .multilineTextAlignment(.leading)
                            Text("— " + quote.by)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if picked == quote {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(picked == quote ? .isSelected : [])
            }
        } header: {
            Text("Find a Quote Online")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let searchStatus { Text(searchStatus) }
                if let picked, let url = picked.pageURL {
                    Button("See it on Wikiquote") { openURL(url) }
                        .buttonStyle(.borderless)
                        .font(.footnote)
                }
            }
        }
    }

    private func runSearch() {
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchTask?.cancel()
        searching = true
        searchStatus = "Searching Wikiquote for “\(query)”…"
        searchTask = Task { @MainActor in
            defer { if !Task.isCancelled { searching = false } }
            do {
                let found = try await QuoteSearch.search(query)
                guard !Task.isCancelled else { return }
                results = found
                picked = nil
                searchStatus = found.isEmpty
                    ? "No quotes found for “\(query)”. Try a person's full name or a single topic word."
                    : "\(found.count) quote\(found.count == 1 ? "" : "s") from Wikiquote. Pick one to fill it in, then Save."
            } catch {
                guard !Task.isCancelled else { return }
                searchStatus = error.localizedDescription
            }
        }
    }

    private func another() {
        let current = text.isEmpty ? Quote.weekly()?.text : text
        var pick = Quote.weekly(offset: offset)
        offset += 1
        if pick?.text == current {
            pick = Quote.weekly(offset: offset)
            offset += 1
        }
        if let pick {
            text = pick.text
            by = pick.attribution
        }
    }
}
