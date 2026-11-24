import SwiftUI
import UserNotifications

// Snoozing a task: it's greyed out for a number of days (5 unless you pick another),
// then you get a reminder and it goes back to normal. The web app does the same
// (web/index.html, "snooze"); both read and write tasks.snoozed_until / snoozed_by.

/// System notifications for the end of your snoozes, so the reminder comes even when
/// the app is closed. While the app is open, the "Snooze is over" alert shows instead.
enum SnoozeAlerts {
    private static let prefix = "kay2do-snooze-"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Schedules one notification per snoozed task and removes any that no longer apply
    /// (woken early, checked off, snoozed again for longer, or snoozed on another device).
    static func sync(_ snoozed: [TaskItem]) {
        var wanted: [String: (title: String, date: Date)] = [:]
        for task in snoozed {
            guard let end = task.snoozeEnd, end > Date() else { continue }
            wanted[prefix + task.id + "-" + String(Int(end.timeIntervalSince1970))] = (task.title, end)
        }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let pending = Set(requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
            let stale = pending.subtracting(wanted.keys)
            if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: Array(stale)) }
            for (id, item) in wanted where !pending.contains(id) {
                let content = UNMutableNotificationContent()
                content.title = "Snooze is over"
                content.body = item.title
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger), withCompletionHandler: nil)
            }
        }
    }
}

enum SnoozeText {
    static func until(_ date: Date) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        let day = sameYear
            ? date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        return day + ", " + date.formatted(date: .omitted, time: .shortened)
    }

    static func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
}

/// "Snooze" items for a task's context menu: the default first, then other lengths.
struct SnoozeMenuItems: View {
    let task: TaskItem
    let askOther: () -> Void
    @EnvironmentObject private var store: Store

    var body: some View {
        if task.isSnoozed {
            Button("Wake Up Now") { store.wake(task) }
        }
        Menu(task.isSnoozed ? "Snooze Again" : "Snooze") {
            Button("For \(SnoozeText.days(TaskItem.defaultSnoozeDays))") { store.snooze(task) }
            Divider()
            ForEach([1, 2, 3, 7, 14, 30], id: \.self) { n in
                Button("For \(SnoozeText.days(n))") { store.snooze(task, days: n) }
            }
            Divider()
            Button("Other…", action: askOther)
        }
    }
}

/// Picks any number of days, 5 to start with.
struct SnoozeSheet: View {
    let task: TaskItem
    let onClose: () -> Void
    @EnvironmentObject private var store: Store
    @State private var days: Int

    init(task: TaskItem, onClose: @escaping () -> Void) {
        self.task = task
        self.onClose = onClose
        _days = State(initialValue: task.isSnoozed ? task.snoozeDaysLeft : TaskItem.defaultSnoozeDays)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(task.title).foregroundStyle(.secondary)
                    Stepper(value: $days, in: 1...365) {
                        Text("Snooze for \(SnoozeText.days(days))")
                    }
                } footer: {
                    Text("Wakes up \(SnoozeText.until(TaskItem.snoozeEnd(days: days))). It stays on the list, greyed out, and you'll get a reminder.")
                }
                if task.isSnoozed {
                    Section {
                        Button("Wake Up Now") { store.wake(task); onClose() }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Snooze")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Snooze") { store.snooze(task, days: days); onClose() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 260)
        #else
        .presentationDetents([.medium])
        #endif
    }
}

/// The "Snooze is over" alert, shown over the app when one of your snoozes ends.
struct SnoozeOverAlert: ViewModifier {
    @EnvironmentObject private var store: Store

    func body(content: Content) -> some View {
        content.alert(store.wokenTasks.count == 1 ? "Snooze is over" : "\(store.wokenTasks.count) snoozes are over",
                      isPresented: Binding(get: { !store.wokenTasks.isEmpty }, set: { if !$0 { store.wokenTasks = [] } })) {
            Button("OK", role: .cancel) { store.wokenTasks = [] }
            Button("Snooze Again for \(SnoozeText.days(TaskItem.defaultSnoozeDays))") { store.snoozeWokenAgain() }
        } message: {
            Text("Back on your list:\n" + store.wokenTasks.map { "• " + $0.title }.joined(separator: "\n"))
        }
    }
}
