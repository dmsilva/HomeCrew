import Foundation

/// What the widgets show, written by the app into the shared App Group folder.
/// Widgets cannot open the iCloud store safely, so the app hands them this small summary instead.
struct WidgetSnapshot: Codable, Equatable {
    static let appGroup = "group.com.dmsilva.homecrew"
    static let fileName = "widget-snapshot.json"

    struct Item: Codable, Equatable, Identifiable {
        var id: String
        /// Activities have a time; chores do not.
        var start: Date?
        var title: String
        var symbol: String
        var person: String
        var colorIndex: Int
        var isDone: Bool
        var isCancelled: Bool
    }

    struct Dose: Codable, Equatable, Identifiable {
        var id: String
        var medicine: String
        var amount: String
        var person: String
        var colorIndex: Int
        /// nil until the first dose has been given.
        var nextAt: Date?
    }

    var generatedAt: Date
    var day: Date
    var items: [Item]
    var doses: [Dose]

    static let empty = WidgetSnapshot(generatedAt: .distantPast, day: .distantPast, items: [], doses: [])

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    static func load(from url: URL? = fileURL) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save(to url: URL? = Self.fileURL) throws {
        guard let url else { return }
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    /// Items still ahead of `date`, timed ones first, then chores not yet done.
    func upcoming(after date: Date, calendar: Calendar = .current) -> [Item] {
        guard calendar.isDate(day, inSameDayAs: date) else { return [] }
        let timed = items.filter { item in
            guard let start = item.start else { return false }
            return !item.isCancelled && start.addingTimeInterval(30 * 60) >= date
        }
        let chores = items.filter { $0.start == nil && !$0.isDone }
        return timed + chores
    }

    /// The dose due soonest; a medicine not yet started counts as due now.
    func nextDose(after date: Date) -> Dose? {
        doses.min { ($0.nextAt ?? date) < ($1.nextAt ?? date) }
    }
}
