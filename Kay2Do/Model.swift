import CoreData
import SwiftUI

// The data model is defined in code (no .xcdatamodeld file). Every attribute is
// optional or has a default and every relationship has an inverse, which is
// what Core Data needs to sync through iCloud (CloudKit).

@objc(TaskCategory)
final class TaskCategory: NSManagedObject, Identifiable {
    @NSManaged var uid: String?
    @NSManaged var key: String?
    @NSManaged var label: String?
    @NSManaged var colorIndex: Int64
    @NSManaged var sortOrder: Int64
    @NSManaged var createdAt: Date?
    @NSManaged var tasks: NSSet?

    static var all: NSFetchRequest<TaskCategory> {
        let request = NSFetchRequest<TaskCategory>(entityName: "TaskCategory")
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]
        return request
    }

    var name: String { isGone ? "" : (label ?? "") }
    var color: Int { isGone ? 0 : Int(colorIndex) }
    var taskList: [TaskItem] { isGone ? [] : ((tasks?.allObjects as? [TaskItem]) ?? []) }
}

@objc(TaskItem)
final class TaskItem: NSManagedObject, Identifiable {
    @NSManaged var uid: String?
    @NSManaged var title: String?
    @NSManaged var notes: String?
    @NSManaged var done: Bool
    @NSManaged var priority: Bool
    @NSManaged var due: Date?
    /// Owner's name as it appears to everyone on the shared category.
    @NSManaged var owner: String?
    /// Other people involved, comma-separated names.
    @NSManaged var sharedWith: String?
    @NSManaged var createdAt: Date?
    @NSManaged var createdBy: String?
    @NSManaged var doneAt: Date?
    @NSManaged var doneBy: String?
    @NSManaged var category: TaskCategory?

    static var all: NSFetchRequest<TaskItem> {
        let request = NSFetchRequest<TaskItem>(entityName: "TaskItem")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return request
    }

    var titleText: String { isGone ? "" : (title ?? "") }
    var notesText: String { isGone ? "" : (notes ?? "") }
    var ownerName: String { isGone ? "" : (owner ?? "").trimmingCharacters(in: .whitespaces) }
    var isDone: Bool { isGone ? false : done }
    var isStarred: Bool { isGone ? false : priority }
    var dueDate: Date? { isGone ? nil : due }
    var created: Date { isGone ? .distantPast : (createdAt ?? .distantPast) }

    var sharedNames: [String] {
        if isGone { return [] }
        return People.split(sharedWith ?? "")
    }

    var isLate: Bool {
        guard !isDone, let due = dueDate else { return false }
        let cal = Calendar.current
        return cal.startOfDay(for: due) < cal.startOfDay(for: Date())
    }

    func involves(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return ([ownerName] + sharedNames).contains { People.same($0, name) }
    }

    func setDone(_ value: Bool, by name: String) {
        done = value
        doneAt = value ? Date() : nil
        doneBy = value ? name : nil
    }

    /// Open before done; starred first; then soonest due date; then oldest.
    static func order(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        if a.isDone { return (a.doneAt ?? .distantPast) > (b.doneAt ?? .distantPast) }
        if a.isStarred != b.isStarred { return a.isStarred }
        if let x = a.dueDate, let y = b.dueDate, x != y { return x < y }
        if a.dueDate != nil && b.dueDate == nil { return true }
        if a.dueDate == nil && b.dueDate != nil { return false }
        return a.created < b.created
    }
}

/// List-wide settings: the list's name and the weekly theme line. Private to you.
@objc(Board)
final class Board: NSManagedObject, Identifiable {
    @NSManaged var uid: String?
    @NSManaged var listName: String?
    @NSManaged var weekOf: Date?
    @NSManaged var theme: String?
    @NSManaged var because: String?
    @NSManaged var createdAt: Date?

    static var all: NSFetchRequest<Board> {
        let request = NSFetchRequest<Board>(entityName: "Board")
        request.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: true),
            NSSortDescriptor(key: "uid", ascending: true)
        ]
        return request
    }
}

extension NSManagedObject {
    /// True once the object has been deleted, so views still on screen read blanks.
    var isGone: Bool { isDeleted || managedObjectContext == nil }
}

enum People {
    static func split(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(b.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }

    static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if seen.insert(trimmed.lowercased()).inserted { out.append(trimmed) }
        }
        return out
    }
}

/// A text binding onto an optional string attribute of a managed object.
func textBinding<T: NSManagedObject>(_ object: T, _ keyPath: ReferenceWritableKeyPath<T, String?>, limit: Int = 4000) -> Binding<String> {
    Binding(
        get: { object.isGone ? "" : (object[keyPath: keyPath] ?? "") },
        set: { if !object.isGone { object[keyPath: keyPath] = String($0.prefix(limit)) } }
    )
}

enum DataModel {
    static let shared: NSManagedObjectModel = build()

    private static func attribute(_ name: String, _ type: NSAttributeType, default value: Any? = nil) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        attribute.defaultValue = value
        return attribute
    }

    private static func build() -> NSManagedObjectModel {
        let category = NSEntityDescription()
        category.name = "TaskCategory"
        category.managedObjectClassName = "TaskCategory"

        let task = NSEntityDescription()
        task.name = "TaskItem"
        task.managedObjectClassName = "TaskItem"

        let board = NSEntityDescription()
        board.name = "Board"
        board.managedObjectClassName = "Board"

        let tasks = NSRelationshipDescription()
        tasks.name = "tasks"
        tasks.destinationEntity = task
        tasks.minCount = 0
        tasks.maxCount = 0
        tasks.isOptional = true
        tasks.deleteRule = .cascadeDeleteRule

        let owningCategory = NSRelationshipDescription()
        owningCategory.name = "category"
        owningCategory.destinationEntity = category
        owningCategory.minCount = 0
        owningCategory.maxCount = 1
        owningCategory.isOptional = true
        owningCategory.deleteRule = .nullifyDeleteRule

        tasks.inverseRelationship = owningCategory
        owningCategory.inverseRelationship = tasks

        category.properties = [
            attribute("uid", .stringAttributeType),
            attribute("key", .stringAttributeType),
            attribute("label", .stringAttributeType),
            attribute("colorIndex", .integer64AttributeType, default: 0),
            attribute("sortOrder", .integer64AttributeType, default: 0),
            attribute("createdAt", .dateAttributeType),
            tasks
        ]

        task.properties = [
            attribute("uid", .stringAttributeType),
            attribute("title", .stringAttributeType),
            attribute("notes", .stringAttributeType),
            attribute("done", .booleanAttributeType, default: false),
            attribute("priority", .booleanAttributeType, default: false),
            attribute("due", .dateAttributeType),
            attribute("owner", .stringAttributeType),
            attribute("sharedWith", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("createdBy", .stringAttributeType),
            attribute("doneAt", .dateAttributeType),
            attribute("doneBy", .stringAttributeType),
            owningCategory
        ]

        board.properties = [
            attribute("uid", .stringAttributeType),
            attribute("listName", .stringAttributeType),
            attribute("weekOf", .dateAttributeType),
            attribute("theme", .stringAttributeType),
            attribute("because", .stringAttributeType),
            attribute("createdAt", .dateAttributeType)
        ]

        let model = NSManagedObjectModel()
        model.entities = [category, task, board]
        return model
    }
}
