import CoreData
import UserNotifications

/// A local notification about a custody swap, for the parent who has to answer or who asked.
struct SwapNotice: Equatable {
    /// Unique per swap and state, so each change is announced once.
    let key: String
    let title: String
    let body: String
}

enum SwapNotifications {
    /// Only recent changes are announced, so installing on a new iPhone does not replay the history.
    static let freshness: TimeInterval = 24 * 3600

    /// New requests for the parent who must answer, and answers for the parent who asked.
    static func notices(swaps: [CustodySwap], me: Member?, now: Date, alreadySent: Set<String>) -> [SwapNotice] {
        guard let me else { return [] }
        return swaps.compactMap { swap in
            guard let id = swap.identifier?.uuidString else { return nil }
            let child = swap.plan?.child?.name ?? ""
            let days = dates(of: swap)
            switch swap.status {
            case .pending:
                guard swap.responder == me, let created = swap.createdAt, now.timeIntervalSince(created) < freshness else { return nil }
                let notice = SwapNotice(
                    key: "swap-\(id)-pending",
                    title: String(localized: "Pedido de troca · \(child)"),
                    body: "\(swap.requester?.name ?? "") · \(days)"
                )
                return alreadySent.contains(notice.key) ? nil : notice
            case .accepted, .declined:
                guard swap.requester == me, let responded = swap.respondedAt, now.timeIntervalSince(responded) < freshness else { return nil }
                let notice = SwapNotice(
                    key: "swap-\(id)-\(swap.status.rawValue)",
                    title: swap.status == .accepted
                        ? String(localized: "Troca aceite · \(child)")
                        : String(localized: "Troca recusada · \(child)"),
                    body: days
                )
                return alreadySent.contains(notice.key) ? nil : notice
            }
        }
    }

    static func dates(of swap: CustodySwap) -> String {
        guard let first = swap.firstDay, let last = swap.lastDay else { return "" }
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        return swap.dayCount <= 1 ? first.formatted(style) : "\(first.formatted(style)) – \(last.formatted(style))"
    }
}

/// Watches swaps arriving from iCloud and posts the notices for this iPhone's person.
final class SwapNotifier {
    static let shared = SwapNotifier(persistence: .shared, defaults: .standard)

    private static let sentKey = "sentSwapNotices"

    private let persistence: PersistenceController
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?

    init(persistence: PersistenceController, defaults: UserDefaults) {
        self.persistence = persistence
        self.defaults = defaults
    }

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: persistence.viewContext,
            queue: .main
        ) { [weak self] note in
            let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSRefreshedObjectsKey]
            let touched = keys.contains { ((note.userInfo?[$0] as? Set<NSManagedObject>) ?? []).contains { $0 is CustodySwap } }
            if touched { self?.post() }
        }
        post()
    }

    @discardableResult
    func post(now: Date = .now, center: UNUserNotificationCenter? = .current()) -> [SwapNotice] {
        let swaps = (try? persistence.viewContext.fetch(CustodySwap.all())) ?? []
        var sent = Set(defaults.stringArray(forKey: Self.sentKey) ?? [])
        let notices = SwapNotifications.notices(swaps: swaps, me: me, now: now, alreadySent: sent)
        for notice in notices {
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.sound = .default
            center?.add(UNNotificationRequest(identifier: notice.key, content: content, trigger: nil))
            sent.insert(notice.key)
        }
        if !notices.isEmpty {
            defaults.set(Array(sent), forKey: Self.sentKey)
        }
        return notices
    }

    private var me: Member? {
        guard let id = defaults.string(forKey: "meMemberID"), let uuid = UUID(uuidString: id) else { return nil }
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "identifier == %@", uuid as CVarArg)
        request.fetchLimit = 1
        return try? persistence.viewContext.fetch(request).first
    }
}
