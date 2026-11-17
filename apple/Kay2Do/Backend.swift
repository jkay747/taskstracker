import Foundation
import Security

/// A small client for the two Supabase services the app needs: Auth (sign in
/// with an emailed code) and the REST API over the tables in supabase/schema.sql.
struct BackendError: LocalizedError {
    let message: String
    var signedOut = false
    /// The HTTP status, or 0 when the server couldn't be reached.
    var status = 0
    var errorDescription: String? { message }
}

struct AuthSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String
}

@MainActor
final class Backend {
    let baseURL: String
    let anonKey: String
    private(set) var session: AuthSession?
    private let http: URLSession
    private var refreshing: Task<Void, Error>?

    init(url: String, anonKey: String) {
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        baseURL = trimmed
        self.anonKey = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        http = URLSession(configuration: config)
        session = SessionStore.load()
    }

    // MARK: Auth

    /// Where the emailed sign-in link sends you back to: this app, via its URL scheme.
    static let redirectURL = "kay2do://login"

    /// Emails a sign-in link (and a 6-digit code, if the project's email template includes one).
    func sendCode(to email: String) async throws {
        try await request("POST", "auth/v1/otp", query: [URLQueryItem(name: "redirect_to", value: Self.redirectURL)],
                          body: ["email": email, "create_user": true], authorized: false)
    }

    /// Finishes sign-in from the emailed link: kay2do://login#access_token=…&refresh_token=…
    /// Returns false if the URL isn't a sign-in link.
    func completeSignIn(from url: URL) async throws -> Bool {
        guard url.scheme == "kay2do" else { return false }
        var params: [String: String] = [:]
        for part in [url.fragment, URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery] {
            for pair in (part ?? "").split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
                if kv.count == 2 { params[kv[0]] = kv[1].replacingOccurrences(of: "+", with: " ") }
            }
        }
        if let problem = params["error_description"] ?? params["error"] {
            throw BackendError(message: problem.contains("expired") || problem.contains("invalid")
                               ? "That sign-in link has expired or was already used. Ask for a new one."
                               : problem)
        }
        guard let access = params["access_token"], let refresh = params["refresh_token"] else { return false }
        // Look up who the link signed in.
        guard let userURL = URL(string: baseURL + "/auth/v1/user") else { return false }
        var req = URLRequest(url: userURL)
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer " + access, forHTTPHeaderField: "Authorization")
        let (data, response) = try await http.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BackendError(message: "That sign-in link didn't work. Ask for a new one.")
        }
        struct User: Decodable { let id: String; let email: String? }
        let user = try JSONDecoder().decode(User.self, from: data)
        let lifetime = Double(params["expires_in"] ?? "") ?? 3600
        let expiry = Double(params["expires_at"] ?? "").map { Date(timeIntervalSince1970: $0) } ?? Date().addingTimeInterval(lifetime)
        let next = AuthSession(accessToken: access, refreshToken: refresh, expiresAt: expiry,
                               userID: user.id.lowercased(), email: (user.email ?? "").lowercased())
        session = next
        SessionStore.save(next)
        return true
    }

    func verify(email: String, code: String) async throws {
        let data = try await request("POST", "auth/v1/verify",
                                     body: ["email": email, "token": code, "type": "email"], authorized: false)
        try keepSession(from: data)
    }

    func signOut() async {
        if session != nil {
            _ = try? await request("POST", "auth/v1/logout", body: [String: String](), authorized: true)
        }
        forgetSession()
    }

    private func forgetSession() {
        session = nil
        SessionStore.save(nil)
    }

    private func keepSession(from data: Data) throws {
        struct Reply: Decodable {
            struct User: Decodable { let id: String; let email: String? }
            let access_token: String
            let refresh_token: String
            let expires_in: Double?
            let expires_at: Double?
            let user: User
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        let expiry = reply.expires_at.map { Date(timeIntervalSince1970: $0) }
            ?? Date().addingTimeInterval(reply.expires_in ?? 3600)
        let next = AuthSession(accessToken: reply.access_token, refreshToken: reply.refresh_token,
                               expiresAt: expiry, userID: reply.user.id.lowercased(),
                               email: (reply.user.email ?? session?.email ?? "").lowercased())
        session = next
        SessionStore.save(next)
    }

    private func accessToken() async throws -> String {
        guard let current = session else { throw BackendError(message: "Sign in first.", signedOut: true) }
        if current.expiresAt.timeIntervalSinceNow > 90 { return current.accessToken }
        if let refreshing {
            try await refreshing.value
        } else {
            let token = current.refreshToken
            let task = Task { @MainActor in
                do {
                    let data = try await self.request("POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                                                      body: ["refresh_token": token], authorized: false)
                    try self.keepSession(from: data)
                } catch let error as BackendError where (400..<500).contains(error.status) {
                    // The refresh token was refused: the sign-in is over.
                    self.forgetSession()
                    throw BackendError(message: "Your sign-in expired. Sign in again.", signedOut: true)
                }
            }
            refreshing = task
            defer { refreshing = nil }
            try await task.value
        }
        guard let fresh = session else { throw BackendError(message: "Sign in first.", signedOut: true) }
        return fresh.accessToken
    }

    // MARK: Requests

    @discardableResult
    func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Any? = nil,
                 bodyData: Data? = nil, authorized: Bool = true, prefer: String? = nil) async throws -> Data {
        guard var components = URLComponents(string: baseURL + "/" + path) else {
            throw BackendError(message: "The Supabase URL isn't valid.")
        }
        if !query.isEmpty { components.queryItems = query }
        // PostgREST reads "+" in a query as a space, so encode it.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw BackendError(message: "The Supabase URL isn't valid.") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        // New-style publishable keys (sb_publishable_…) aren't JWTs and must not
        // be sent as a Bearer token; older anon keys (eyJ…) can be.
        if authorized {
            request.setValue("Bearer " + (try await accessToken()), forHTTPHeaderField: "Authorization")
        } else if anonKey.hasPrefix("eyJ") {
            request.setValue("Bearer " + anonKey, forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let bodyData {
            request.httpBody = bodyData
        } else if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await http.data(for: request)
        } catch {
            throw BackendError(message: "Couldn't reach the server. Check your connection. (\(error.localizedDescription))")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 && authorized { forgetSession() }
            throw BackendError(message: Self.message(from: data, status: status), signedOut: status == 401 && authorized, status: status)
        }
        return data
    }

    static func message(from data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "msg", "error_description", "error"] {
                if let text = object[key] as? String, !text.isEmpty {
                    if text.contains("row-level security") { return "You don't have permission to make that change." }
                    return text
                }
            }
        }
        return "The server answered with error \(status)."
    }

    // MARK: Tables

    func select<T: Decodable>(_ table: String, _ filters: [(String, String)], select columns: String = "*",
                              order: String? = nil) async throws -> [T] {
        var query = [URLQueryItem(name: "select", value: columns)]
        query += filters.map { URLQueryItem(name: $0.0, value: $0.1) }
        if let order { query.append(URLQueryItem(name: "order", value: order)) }
        let data = try await request("GET", "rest/v1/" + table, query: query)
        return try Self.decoder.decode([T].self, from: data)
    }

    func insert<T: Encodable>(_ table: String, _ value: T) async throws {
        try await request("POST", "rest/v1/" + table, bodyData: try Self.encoder.encode(value), prefer: "return=minimal")
    }

    func update<T: Encodable>(_ table: String, _ value: T, where filters: [(String, String)]) async throws {
        try await request("PATCH", "rest/v1/" + table, query: filters.map { URLQueryItem(name: $0.0, value: $0.1) },
                          bodyData: try Self.encoder.encode(value), prefer: "return=minimal")
    }

    func update(_ table: String, fields: [String: Any], where filters: [(String, String)]) async throws {
        try await request("PATCH", "rest/v1/" + table, query: filters.map { URLQueryItem(name: $0.0, value: $0.1) },
                          body: fields, prefer: "return=minimal")
    }

    func delete(_ table: String, where filters: [(String, String)]) async throws {
        try await request("DELETE", "rest/v1/" + table, query: filters.map { URLQueryItem(name: $0.0, value: $0.1) },
                          prefer: "return=minimal")
    }

    /// Calls a database function and decodes a table result.
    func rpc<T: Decodable>(_ function: String, _ params: [String: Any]) async throws -> T {
        let data = try await request("POST", "rest/v1/rpc/" + function, body: params)
        return try Self.decoder.decode(T.self, from: data)
    }

    /// Calls a database function that returns a single value (text, uuid, number).
    @discardableResult
    func rpcValue(_ function: String, _ params: [String: Any]) async throws -> Any? {
        let data = try await request("POST", "rest/v1/rpc/" + function, body: params)
        if data.isEmpty { return nil }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static let decoder = JSONDecoder()
    static let encoder = JSONEncoder()
}

/// Keeps the sign-in between launches: in the Keychain, or in app settings if
/// the Keychain refuses (an unsigned development build, for example).
enum SessionStore {
    private static let service = "com.kay2ventures.Kay2Do.session"
    private static let account = "supabase"
    private static let fallbackKey = "supabaseSessionFallback"

    static func load() -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            return try? JSONDecoder().decode(AuthSession.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: fallbackKey) {
            return try? JSONDecoder().decode(AuthSession.self, from: data)
        }
        return nil
    }

    static func save(_ session: AuthSession?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(add as CFDictionary, nil) != errSecSuccess {
            UserDefaults.standard.set(data, forKey: fallbackKey)
        }
    }
}
