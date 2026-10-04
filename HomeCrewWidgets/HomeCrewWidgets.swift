import SwiftUI
import WidgetKit

@main
struct HomeCrewWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        NextDoseWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Reads the app's snapshot; new entries at each activity start so finished ones drop off.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .preview : (WidgetSnapshot.load() ?? .empty)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? .empty
        let now = Date.now
        let changes = snapshot.items.compactMap { $0.start?.addingTimeInterval(30 * 60) }.filter { $0 > now }
        let dates = [now] + changes.sorted()
        let entries = dates.map { SnapshotEntry(date: $0, snapshot: snapshot) }
        // Past midnight the snapshot is yesterday's; check back then even if the app is not opened.
        let tomorrow = Calendar.current.startOfDay(for: now.addingTimeInterval(24 * 3600))
        completion(Timeline(entries: entries, policy: .after(tomorrow)))
    }
}

// MARK: - Hoje

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(Color.hcBackground, for: .widget)
        }
        .configurationDisplayName(Text("Hoje"))
        .description(Text("Próximas atividades e tarefas."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let items = entry.snapshot.upcoming(after: entry.date)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.date, format: .dateTime.weekday(.wide).day())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.hcAccent)
                Spacer()
                Image(systemName: "sun.max.fill").foregroundStyle(Color.hcAccent)
            }
            if items.isEmpty {
                Spacer()
                Image(systemName: "checkmark.circle")
                    .font(.title)
                    .foregroundStyle(Color.hcSecondaryInk)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(items.prefix(family == .systemSmall ? 3 : 4)) { item in
                    ItemLine(item: item, showsPerson: family != .systemSmall)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct ItemLine: View {
    let item: WidgetSnapshot.Item
    let showsPerson: Bool

    var body: some View {
        let colors = Theme.Palette.members[min(max(item.colorIndex, 0), Theme.Palette.members.count - 1)]
        HStack(spacing: 6) {
            Image(systemName: item.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(colors.foreground))
                .frame(width: 22, height: 22)
                .background(Color(colors.soft), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.hcInk)
                    .lineLimit(1)
                if showsPerson, !item.person.isEmpty {
                    Text(item.person)
                        .font(.caption2)
                        .foregroundStyle(Color.hcSecondaryInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let start = item.start {
                Text(start, format: .dateTime.hour().minute())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.hcSecondaryInk)
            }
        }
    }
}

// MARK: - Próxima dose

struct NextDoseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextDoseWidget", provider: SnapshotProvider()) { entry in
            NextDoseView(entry: entry)
                .containerBackground(Color.hcBackground, for: .widget)
        }
        .configurationDisplayName(Text("Próxima dose"))
        .description(Text("Contagem até à próxima dose."))
        .supportedFamilies([.systemSmall])
    }
}

struct NextDoseView: View {
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "pills.fill")
                .font(.title3)
                .foregroundStyle(Color.hcAccent)
            if let dose = entry.snapshot.nextDose(after: entry.date) {
                Text(dose.medicine)
                    .font(.headline)
                    .foregroundStyle(Color.hcInk)
                    .lineLimit(1)
                Text([dose.person, dose.amount].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Color.hcSecondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let next = dose.nextAt, next > entry.date {
                    Text(next, style: .timer)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.hcInk)
                } else {
                    Text("Agora")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.hcWarning)
                }
            } else {
                Spacer()
                Text("Sem doses")
                    .font(.caption)
                    .foregroundStyle(Color.hcSecondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension WidgetSnapshot {
    static var preview: WidgetSnapshot {
        let now = Date.now
        return WidgetSnapshot(
            generatedAt: now,
            day: Calendar.current.startOfDay(for: now),
            items: [
                Item(id: "1", start: now.addingTimeInterval(3600), title: "Futebol", symbol: "soccerball",
                     person: "Rita", colorIndex: 1, isDone: false, isCancelled: false),
                Item(id: "2", start: nil, title: "Mochila", symbol: "checklist",
                     person: "Tomás", colorIndex: 2, isDone: false, isCancelled: false),
            ],
            doses: [Dose(id: "d", medicine: "Ben-u-ron", amount: "7,5 ml", person: "Rita", colorIndex: 1,
                         nextAt: now.addingTimeInterval(2 * 3600))]
        )
    }
}
