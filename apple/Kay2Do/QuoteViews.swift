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

/// Type a quote for the week, step through the built-in ones, or go back to the weekly pick.
struct QuoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store
    @State private var text = ""
    @State private var by = ""
    @State private var offset = 1
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
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
        .onAppear {
            guard !loaded, let list = store.list else { return }
            loaded = true
            text = list.quote
            by = list.quoteBy
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 380)
        #endif
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
