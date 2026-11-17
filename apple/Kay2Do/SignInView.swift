import SwiftUI

/// Picks the screen for where you are: connecting, signing in, no list yet, or the list.
struct RootView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        Group {
            switch store.phase {
            case .needsConfig: ConnectView()
            case .signedOut: SignInView()
            case .loading: ProgressView("Loading your list…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .noList: NoListView()
            case .ready: ContentView()
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private struct GateFrame<Content: View>: View {
    let lead: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Kay2-Do")
                    .font(.system(size: 40, weight: .semibold, design: .serif).italic())
                Text(lead)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
            .padding(28)
            .frame(maxWidth: 480, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

struct ConnectView: View {
    @EnvironmentObject private var store: Store
    @State private var url = ""
    @State private var key = ""

    var body: some View {
        GateFrame(lead: "Connect the app to your Supabase project. Both values are under Project Settings → API in Supabase, and they're the same ones the web list uses.") {
            TextField("Project URL (https://….supabase.co)", text: $url)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            TextField("anon public key", text: $key, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button("Connect") {
                store.connect(url: url, anonKey: key)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!url.hasPrefix("https://") || key.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

struct SignInView: View {
    @EnvironmentObject private var store: Store
    @State private var email = ""
    @State private var code = ""
    @State private var sentTo: String?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        GateFrame(lead: sentTo.map { "We sent a 6-digit code to \($0). Enter it below." }
                  ?? "Sign in with your email. We'll send you a 6-digit code. Use the same email as on the web list.") {
            if let notice = store.notice {
                Text(notice).font(.callout)
            }
            if sentTo == nil {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                    .onSubmit(send)
                Button("Send code", action: send)
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || !email.contains("@"))
            } else {
                TextField("Code from the email", text: $code)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    #endif
                    .onSubmit(verify)
                HStack(spacing: 16) {
                    Button("Sign in", action: verify)
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || code.filter(\.isNumber).count < 6)
                    Button("Use a different email") {
                        sentTo = nil; code = ""; error = nil
                    }
                    .buttonStyle(.borderless)
                }
            }
            if busy { ProgressView() }
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            if store.canChangeServer {
                Button("Connect to a different Supabase project") {
                    Task { await store.disconnect() }
                }
                .buttonStyle(.borderless)
                .font(.footnote)
                .padding(.top, 20)
            }
        }
    }

    private func send() {
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard address.contains("@"), !busy else { return }
        busy = true; error = nil
        store.clearNotice()
        Task {
            defer { busy = false }
            do {
                try await store.sendCode(to: address)
                sentTo = address
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func verify() {
        guard let address = sentTo, !busy else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                try await store.verify(email: address, code: code)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct NoListView: View {
    @EnvironmentObject private var store: Store
    @State private var name = "Kay2-Do"
    @State private var busy = false

    var body: some View {
        GateFrame(lead: "You're signed in as \(store.myEmail) but aren't on a list yet. Make your own, or ask whoever shares a list with you to invite this email address.") {
            TextField("List name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 16) {
                Button("Create My List") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do { try await store.createList(named: name) } catch { store.handle(error, doing: "create the list") }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
                Button("Check for Invites") {
                    Task { await store.checkForInvites() }
                }
                .buttonStyle(.borderless)
            }
            Button("Sign Out") {
                Task { await store.signOut() }
            }
            .buttonStyle(.borderless)
            .padding(.top, 12)
        }
    }
}
