import Foundation

// Records as they're stored in Supabase (see supabase/schema.sql). The web
// app in web/index.html reads and writes exactly the same rows.

/// Someone on a task: a member of the list (by account id), or just a name or
/// email typed in for someone who hasn't joined yet.
enum Person: Codable, Hashable {
    case user(String)
    case named(String)

    private enum Keys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        if let id = try container.decodeIfPresent(String.self, forKey: .id) {
            self = .user(id.lowercased())
        } else {
            self = .named(try container.decodeIfPresent(String.self, forKey: .name) ?? "")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .user(let id): try container.encode(id, forKey: .id)
        case .named(let name): try container.encode(name, forKey: .name)
        }
    }

    /// Same person, ignoring capitals and spaces in typed names.
    var key: String {
        switch self {
        case .user(let id): return "u:" + id
        case .named(let name): return "n:" + name.trimmingCharacters(in: .whitespaces).lowercased()
        }
    }

    var isLinked: Bool { if case .user = self { return true } else { return false } }

    static func typed(_ text: String) -> Person? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let value = trimmed.contains("@") ? trimmed.lowercased() : trimmed
        return .named(String(value.prefix(120)))
    }
}

struct TaskList: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var weekOf: String?
    var theme: String
    var because: String
    /// Blank = use the built-in pick for the week.
    var quote: String
    var quoteBy: String
    var showQuote: Bool
    /// "", "library:<id>" or "upload:<list id>/<file>"; see BackgroundChoice.
    var background: String
    /// "subtle", "balanced" or "vivid": how strongly the picture shows through.
    var backgroundStyle: String
    /// "manual": checked-off tasks stay, crossed out, until removed by hand.
    /// "auto": they're removed `completedDays` days after they were checked off.
    var completedMode: String
    var completedDays: Int

    var removesCompletedAutomatically: Bool { completedMode == "auto" }

    enum CodingKeys: String, CodingKey {
        case id, name, theme, because, quote, background
        case weekOf = "week_of"
        case quoteBy = "quote_by"
        case showQuote = "show_quote"
        case backgroundStyle = "background_style"
        case completedMode = "completed_mode"
        case completedDays = "completed_days"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id).lowercased()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Kay2-Do"
        weekOf = try c.decodeIfPresent(String.self, forKey: .weekOf)
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? ""
        because = try c.decodeIfPresent(String.self, forKey: .because) ?? ""
        quote = try c.decodeIfPresent(String.self, forKey: .quote) ?? ""
        quoteBy = try c.decodeIfPresent(String.self, forKey: .quoteBy) ?? ""
        showQuote = try c.decodeIfPresent(Bool.self, forKey: .showQuote) ?? true
        background = try c.decodeIfPresent(String.self, forKey: .background) ?? ""
        backgroundStyle = try c.decodeIfPresent(String.self, forKey: .backgroundStyle) ?? "balanced"
        completedMode = try c.decodeIfPresent(String.self, forKey: .completedMode) ?? "manual"
        completedDays = try c.decodeIfPresent(Int.self, forKey: .completedDays) ?? 7
    }
}

/// A built-in background picture (Backgrounds.swift): public domain, served by Wikimedia Commons.
struct BackgroundPhoto: Identifiable, Hashable {
    let id: String
    let title: String
    let credit: String
    let full: String
    let thumb: String
    let page: String
}

/// What a list shows behind it (Mac and web only).
enum BackgroundChoice: Equatable {
    case none
    case library(BackgroundPhoto)
    case upload(path: String)

    init(_ value: String) {
        if value.hasPrefix("library:"), let photo = Backgrounds.all.first(where: { $0.id == String(value.dropFirst(8)) }) {
            self = .library(photo)
        } else if value.hasPrefix("upload:"), value.count > 7 {
            self = .upload(path: String(value.dropFirst(7)))
        } else {
            self = .none
        }
    }

    var value: String {
        switch self {
        case .none: return ""
        case .library(let photo): return "library:" + photo.id
        case .upload(let path): return "upload:" + path
        }
    }
}

/// A quote for the week: one of the built-in ones (Quotes.swift) or one typed in.
struct Quote: Equatable {
    let text: String
    let by: String
    var source: String = ""

    var attribution: String { source.isEmpty ? by : by + ", " + source }

    /// The built-in pick for the week containing `date`; `offset` steps through the others.
    /// Weeks count from Monday 5 January 2026 by the local calendar, the same as the web app,
    /// so everyone on a list sees the same quote.
    static func weekly(for date: Date = Date(), offset: Int = 0) -> Quote? {
        let all = Quotes.all
        guard !all.isEmpty else { return nil }
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let day = utc.date(from: parts),
              let start = utc.date(from: DateComponents(year: 2026, month: 1, day: 5)),
              let days = utc.dateComponents([.day], from: start, to: day).day else { return all.first }
        let week = Int((Double(days) / 7).rounded(.down))
        let n = all.count
        return all[(((week + offset) % n) + n) % n]
    }
}

struct TaskCategory: Codable, Identifiable, Hashable {
    var id: String
    var listID: String
    var key: String
    var label: String
    var color: Int
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, key, label, color
        case listID = "list_id"
        case sortOrder = "sort_order"
    }

    init(id: String, listID: String, key: String, label: String, color: Int, sortOrder: Int) {
        self.id = id; self.listID = listID; self.key = key; self.label = label; self.color = color; self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id).lowercased()
        listID = try c.decode(String.self, forKey: .listID).lowercased()
        key = try c.decode(String.self, forKey: .key)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        color = try c.decodeIfPresent(Int.self, forKey: .color) ?? 0
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    var name: String { label }
}

struct TaskItem: Codable, Identifiable, Equatable {
    var id: String
    var listID: String
    var categoryKey: String?
    var title: String
    var notes: String
    var done: Bool
    var priority: Bool
    /// "yyyy-MM-dd"
    var due: String?
    var owner: Person?
    var shared: [Person]
    var createdBy: String?
    var createdAt: String?
    var doneAt: String?
    var doneBy: String?
    /// While set and in the future, the task is snoozed: greyed out until then. When it
    /// passes, the person who snoozed it (snoozedBy) gets a reminder and both are cleared.
    var snoozedUntil: String?
    var snoozedBy: String?
    /// True when the database has the snooze columns (supabase/update-2026-11-snooze.sql)
    /// or the task was snoozed here; only then are the snooze fields sent, so a list that
    /// hasn't run the update keeps saving normally. Not stored.
    var sendsSnooze = false

    enum CodingKeys: String, CodingKey {
        case id, title, notes, done, priority, due, owner, shared
        case listID = "list_id"
        case categoryKey = "category_key"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case doneAt = "done_at"
        case doneBy = "done_by"
        case snoozedUntil = "snoozed_until"
        case snoozedBy = "snoozed_by"
    }

    init(id: String, listID: String, categoryKey: String?, title: String, createdBy: String) {
        self.id = id
        self.listID = listID
        self.categoryKey = categoryKey
        self.title = title
        notes = ""
        done = false
        priority = false
        due = nil
        owner = nil
        shared = []
        self.createdBy = createdBy
        createdAt = Timestamp.string(Date())
        doneAt = nil
        doneBy = nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id).lowercased()
        listID = try c.decode(String.self, forKey: .listID).lowercased()
        categoryKey = try c.decodeIfPresent(String.self, forKey: .categoryKey)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        priority = try c.decodeIfPresent(Bool.self, forKey: .priority) ?? false
        due = try c.decodeIfPresent(String.self, forKey: .due)
        owner = try? c.decodeIfPresent(Person.self, forKey: .owner)
        shared = (try? c.decodeIfPresent([Person].self, forKey: .shared)) ?? []
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy)?.lowercased()
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        doneAt = try c.decodeIfPresent(String.self, forKey: .doneAt)
        doneBy = try c.decodeIfPresent(String.self, forKey: .doneBy)?.lowercased()
        sendsSnooze = c.contains(.snoozedUntil)
        snoozedUntil = try c.decodeIfPresent(String.self, forKey: .snoozedUntil)
        snoozedBy = try c.decodeIfPresent(String.self, forKey: .snoozedBy)?.lowercased()
    }

    /// What the app writes. Empty values are sent as null so a cleared due
    /// date or owner is cleared on the server too.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(listID, forKey: .listID)
        try c.encode(categoryKey, forKey: .categoryKey)
        try c.encode(String(title.prefix(300)), forKey: .title)
        try c.encode(String(notes.prefix(4000)), forKey: .notes)
        try c.encode(done, forKey: .done)
        try c.encode(priority, forKey: .priority)
        try c.encode(due, forKey: .due)
        try c.encode(owner, forKey: .owner)
        try c.encode(shared, forKey: .shared)
        if let createdBy { try c.encode(createdBy, forKey: .createdBy) }
        try c.encode(doneAt, forKey: .doneAt)
        try c.encode(doneBy, forKey: .doneBy)
        if sendsSnooze || snoozedUntil != nil {
            try c.encode(snoozedUntil, forKey: .snoozedUntil)
            try c.encode(snoozedUntil == nil ? nil : snoozedBy, forKey: .snoozedBy)
        }
    }

    var dueDate: Date? { DayString.date(due) }
    var created: Date { Timestamp.parse(createdAt) ?? .distantPast }
    var completed: Date? { Timestamp.parse(doneAt) }

    /// On a list that removes completed tasks automatically, true once this one has been
    /// done for the list's number of days. The database's hourly job deletes it; the app
    /// hides it as soon as it's due.
    func isExpired(on list: TaskList?, now: Date = Date()) -> Bool {
        guard done, let list, list.removesCompletedAutomatically, let completed else { return false }
        return completed < now.addingTimeInterval(-Double(max(1, list.completedDays)) * 86_400)
    }
    var people: [Person] { (owner.map { [$0] } ?? []) + shared }

    // MARK: Snooze

    static let defaultSnoozeDays = 5

    /// Snoozes end at 9 AM, `days` days from today.
    static func snoozeEnd(days: Int, from now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: min(max(days, 1), 365), to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    var snoozeEnd: Date? { Timestamp.parse(snoozedUntil) }

    /// Snoozed and not yet due to wake. A checked-off task is never shown as snoozed.
    var isSnoozed: Bool {
        guard !done, let end = snoozeEnd else { return false }
        return end > Date()
    }

    /// Whole days from today to the day it wakes, at least 1.
    var snoozeDaysLeft: Int {
        guard let end = snoozeEnd else { return TaskItem.defaultSnoozeDays }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: end)).day ?? 1
        return max(1, days)
    }

    mutating func snooze(days: Int, by userID: String) {
        snoozedUntil = Timestamp.string(TaskItem.snoozeEnd(days: days))
        snoozedBy = userID
        sendsSnooze = true
    }

    mutating func wake() {
        snoozedUntil = nil
        snoozedBy = nil
    }

    var isLate: Bool {
        guard !done, !isSnoozed, let due = dueDate else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }

    func involves(_ person: Person) -> Bool {
        people.contains { $0.key == person.key }
    }

    mutating func setDone(_ value: Bool, by userID: String) {
        done = value
        doneAt = value ? Timestamp.string(Date()) : nil
        doneBy = value ? userID : nil
        if value { wake() }
    }

    /// Starred first; then soonest due date; then oldest. Done or not doesn't move a
    /// task: a checked-off one stays where it was, crossed out.
    static func order(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.priority != b.priority { return a.priority }
        if a.due != b.due {
            guard let x = a.due else { return false }
            guard let y = b.due else { return true }
            return x < y
        }
        return a.created < b.created
    }
}

/// Someone on a list, or a pending invite (from the list_people function).
struct Member: Decodable, Hashable, Identifiable {
    var userID: String?
    var email: String?
    var displayName: String?
    var role: String
    var pending: Bool

    enum CodingKeys: String, CodingKey {
        case email, role, pending
        case userID = "user_id"
        case displayName = "display_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decodeIfPresent(String.self, forKey: .userID)?.lowercased()
        email = try c.decodeIfPresent(String.self, forKey: .email)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "contributor"
        pending = try c.decodeIfPresent(Bool.self, forKey: .pending) ?? false
    }

    var id: String { userID ?? ("invite:" + (email ?? "")) }
    var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return email ?? "Someone"
    }
    var roleLabel: String { Role.label(role) }
}

enum Role {
    static let assignable = ["contributor", "editor"]
    static func label(_ role: String) -> String {
        switch role {
        case "owner": return "Owner"
        case "editor": return "Editor"
        default: return "Contributor"
        }
    }
}

enum Timestamp {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Reads Postgres timestamps like 2026-11-17T17:38:23.022027+00:00.
    static func parse(_ text: String?) -> Date? {
        guard var s = text, !s.isEmpty else { return nil }
        if let dot = s.firstIndex(of: ".") {
            var end = s.index(after: dot)
            while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
            s.removeSubrange(dot..<end)
        }
        // "+00" → "+00:00"
        if let sign = s.dropLast(2).last, sign == "+" || sign == "-", s.contains("T") || s.contains(" ") {
            s += ":00"
        }
        s = s.replacingOccurrences(of: " ", with: "T")
        return formatter.date(from: s)
    }

    static func string(_ date: Date) -> String { formatter.string(from: date) }
}

/// Calendar days as "yyyy-MM-dd", in the device's own time zone.
enum DayString {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        formatter.timeZone = .current
        return formatter.date(from: String(text.prefix(10)))
    }

    static func string(_ date: Date) -> String {
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

enum Slug {
    static func make(_ label: String, taken: Set<String>) -> String {
        let mapped = label.lowercased().unicodeScalars.map { scalar -> String in
            let isLetter = scalar.value >= 97 && scalar.value <= 122
            let isDigit = scalar.value >= 48 && scalar.value <= 57
            return (isLetter || isDigit) ? String(scalar) : "-"
        }.joined()
        var base = mapped.split(separator: "-").joined(separator: "-")
        base = String(base.prefix(30))
        if base.isEmpty { base = "cat" }
        var key = base
        var n = 2
        while taken.contains(key) {
            key = "\(base)-\(n)"
            n += 1
        }
        return key
    }
}
