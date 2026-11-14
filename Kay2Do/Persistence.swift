import CoreData
import CloudKit
import Combine

/// The task store. Two local databases mirror two iCloud databases:
/// - private: everything you created (including categories you share out)
/// - shared: categories other people have shared with you
final class Persistence: ObservableObject {
    static let shared = Persistence()
    static let containerID = "iCloud.com.kay2ventures.Kay2Do"
    static let maxCategories = 12
    static let starterCategories: [(key: String, label: String, color: Int)] = [
        ("home", "Home", 0),
        ("work", "Work", 1),
        ("estate", "Estate Planning", 2),
        ("longterm", "Long Term", 3)
    ]

    let container: NSPersistentCloudKitContainer
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    /// The iCloud share for each shared category, keyed by the category's object ID.
    @Published private(set) var shares: [NSManagedObjectID: CKShare] = [:]
    @Published var errorMessage: String?

    private var pendingSave: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    var context: NSManagedObjectContext { container.viewContext }
    var cloudContainer: CKContainer { CKContainer(identifier: Self.containerID) }

    private init() {
        container = NSPersistentCloudKitContainer(name: "Kay2Do", managedObjectModel: DataModel.shared)

        let folder = NSPersistentContainer.defaultDirectoryURL()
        let privateURL = folder.appendingPathComponent("Kay2Do-private.sqlite")
        let sharedURL = folder.appendingPathComponent("Kay2Do-shared.sqlite")
        container.persistentStoreDescriptions = [
            Self.storeDescription(url: privateURL, scope: .private),
            Self.storeDescription(url: sharedURL, scope: .shared)
        ]

        var loadErrors: [String] = []
        container.loadPersistentStores { _, error in
            if let error = error { loadErrors.append(error.localizedDescription) }
        }
        let coordinator = container.persistentStoreCoordinator
        privateStore = coordinator.persistentStore(for: privateURL)
        sharedStore = coordinator.persistentStore(for: sharedURL)
        if !loadErrors.isEmpty {
            errorMessage = "The task store didn't open correctly: " + loadErrors.joined(separator: " ")
        }

        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.transactionAuthor = "app"

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: coordinator, queue: .main) { [weak self] _ in
            self?.refreshShares()
        })
        observers.append(center.addObserver(forName: .NSManagedObjectContextObjectsDidChange, object: context, queue: .main) { [weak self] _ in
            self?.scheduleSave()
        })
        refreshShares()
    }

    private static func storeDescription(url: URL, scope: CKDatabase.Scope) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
        options.databaseScope = scope
        description.cloudKitContainerOptions = options
        return description
    }

    // MARK: Saving

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func save() {
        pendingSave?.cancel()
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            report(error, doing: "save that change")
        }
    }

    func report(_ error: Error, doing action: String) {
        let message = "Couldn't \(action). \(error.localizedDescription)"
        if Thread.isMainThread {
            errorMessage = message
        } else {
            DispatchQueue.main.async { self.errorMessage = message }
        }
    }

    // MARK: Creating and moving

    private func insert<T: NSManagedObject>(_ entity: String, into store: NSPersistentStore?) -> T {
        let object = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
        if let store = store { context.assign(object, to: store) }
        guard let typed = object as? T else { fatalError("Entity \(entity) has the wrong class") }
        return typed
    }

    @discardableResult
    func addCategory(label: String, key: String, color: Int, order: Int) -> TaskCategory {
        let category: TaskCategory = insert("TaskCategory", into: privateStore)
        category.uid = UUID().uuidString
        category.key = key
        category.label = String(label.prefix(40))
        category.colorIndex = Int64(color)
        category.sortOrder = Int64(order)
        category.createdAt = Date()
        return category
    }

    func addStarterCategories() {
        for (index, item) in Self.starterCategories.enumerated() {
            addCategory(label: item.label, key: item.key, color: item.color, order: index)
        }
        save()
    }

    /// A new task lives wherever its category lives, so a task added to a
    /// category someone shared with you reaches everyone on that category.
    @discardableResult
    func addTask(title: String, in category: TaskCategory?, createdBy name: String) -> TaskItem {
        if let category = category, category.objectID.isTemporaryID { save() }
        let store = category?.objectID.persistentStore ?? privateStore
        let task: TaskItem = insert("TaskItem", into: store)
        task.uid = UUID().uuidString
        task.title = String(title.prefix(300))
        task.createdAt = Date()
        task.createdBy = name
        task.category = category
        return task
    }

    /// Moves a task to another category. Between two of your own unshared
    /// categories this is a simple relink. Anything that crosses a sharing
    /// boundary has to be re-created at the destination, because shared
    /// categories are stored separately in iCloud. Returns true when the
    /// original task was replaced by a copy.
    @discardableResult
    func move(_ task: TaskItem, to destination: TaskCategory) -> Bool {
        if task.category == destination { return false }
        let sourceIsPlain = task.category.map { isMine($0) && !isShared($0) } ?? isMine(task)
        let destinationIsPlain = isMine(destination) && !isShared(destination)
        if sourceIsPlain && destinationIsPlain {
            task.category = destination
            return false
        }
        let copy = addTask(title: task.titleText, in: destination, createdBy: task.createdBy ?? "")
        copy.notes = task.notes
        copy.done = task.done
        copy.priority = task.priority
        copy.due = task.due
        copy.owner = task.owner
        copy.sharedWith = task.sharedWith
        copy.createdAt = task.createdAt
        copy.doneAt = task.doneAt
        copy.doneBy = task.doneBy
        context.delete(task)
        return true
    }

    /// The settings record, created the first time something is saved to it.
    func board() -> Board {
        if let existing = (try? context.fetch(Board.all))?.first { return existing }
        let board: Board = insert("Board", into: privateStore)
        board.uid = UUID().uuidString
        board.createdAt = Date()
        return board
    }

    /// Two of your devices can each create the starter categories or settings
    /// before iCloud catches up. This merges those duplicates. Every device
    /// keeps the same survivor (oldest, ties broken by uid), so they never
    /// delete each other's copy. Shared categories are never touched.
    func tidy() {
        let categories = ((try? context.fetch(TaskCategory.all)) ?? [])
            .filter { isMine($0) && !isShared($0) }
            .sorted { ($0.createdAt ?? .distantPast, $0.uid ?? "") < ($1.createdAt ?? .distantPast, $1.uid ?? "") }
        var kept: [String: TaskCategory] = [:]
        for category in categories {
            let key = category.key ?? ""
            if let first = kept[key] {
                for task in category.taskList { task.category = first }
                context.delete(category)
            } else {
                kept[key] = category
            }
        }
        let boards = (try? context.fetch(Board.all)) ?? []
        for extra in boards.dropFirst() { context.delete(extra) }
    }

    // MARK: Sharing

    func isMine(_ object: NSManagedObject) -> Bool {
        guard let shared = sharedStore else { return true }
        return object.objectID.persistentStore != shared
    }

    func isShared(_ category: TaskCategory) -> Bool {
        shares[category.objectID] != nil
    }

    /// False for someone invited to a category as view-only.
    func canEdit(_ object: NSManagedObject) -> Bool {
        if object.isGone { return false }
        if object.objectID.isTemporaryID || isMine(object) { return true }
        return container.canUpdateRecord(forManagedObjectWith: object.objectID)
    }

    func refreshShares() {
        let ids = ((try? context.fetch(TaskCategory.all)) ?? [])
            .map { $0.objectID }
            .filter { !$0.isTemporaryID }
        guard !ids.isEmpty else {
            if !shares.isEmpty { shares = [:] }
            return
        }
        if let found = try? container.fetchShares(matching: ids) {
            shares = found
        }
    }

    /// Names of the other people on a category's share (invited or joined).
    func participants(of category: TaskCategory?) -> [String] {
        guard let category = category, let share = shares[category.objectID] else { return [] }
        let me = share.currentUserParticipant?.userIdentity.userRecordID
        return People.unique(share.participants.compactMap { participant in
            if let me = me, participant.userIdentity.userRecordID == me { return nil }
            return Self.name(of: participant)
        })
    }

    static func name(of participant: CKShare.Participant) -> String {
        let identity = participant.userIdentity
        if let components = identity.nameComponents {
            let text = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !text.trimmingCharacters(in: .whitespaces).isEmpty { return text }
        }
        return identity.lookupInfo?.emailAddress ?? identity.lookupInfo?.phoneNumber ?? ""
    }

    /// Returns the category's iCloud share, creating it the first time.
    @MainActor
    func share(for category: TaskCategory) async throws -> CKShare {
        save()
        if let existing = shares[category.objectID] { return existing }
        let title = category.name
        let (_, share, _) = try await container.share([category], to: nil)
        share[CKShare.SystemFieldKey.title] = title
        if let store = privateStore {
            _ = try await container.persistUpdatedShare(share, in: store)
        }
        refreshShares()
        return share
    }

    func persist(_ share: CKShare) {
        guard let store = share.recordID.zoneID.ownerName == CKCurrentUserDefaultName ? privateStore : sharedStore else { return }
        container.persistUpdatedShare(share, in: store) { [weak self] _, error in
            if let error = error { self?.report(error, doing: "update sharing") }
            DispatchQueue.main.async { self?.refreshShares() }
        }
    }

    /// Called when sharing stops. If it was someone else's category, its
    /// tasks are removed from this device.
    func stoppedSharing(_ share: CKShare) {
        let zoneID = share.recordID.zoneID
        if zoneID.ownerName != CKCurrentUserDefaultName, let store = sharedStore {
            container.purgeObjectsAndRecordsInZone(with: zoneID, in: store) { [weak self] _, error in
                if let error = error { self?.report(error, doing: "leave the shared category") }
                DispatchQueue.main.async { self?.refreshShares() }
            }
        } else {
            DispatchQueue.main.async { self.refreshShares() }
        }
    }

    /// Called when you open an invitation link.
    func accept(_ metadata: CKShare.Metadata) {
        guard let store = sharedStore else { return }
        container.acceptShareInvitations(from: [metadata], into: store) { [weak self] _, error in
            if let error = error { self?.report(error, doing: "accept the invitation") }
            DispatchQueue.main.async { self?.refreshShares() }
        }
    }

    static func slug(for label: String, taken: Set<String>) -> String {
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
