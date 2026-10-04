import CoreData
import SwiftUI

/// The week as a grid (Direção E): a row per child, a column per day, each activity as its icon on the
/// child's colour. Tapping a square shows that day's activity in the dark card below.
struct ActivitiesWeekView: View {
    @FetchRequest(fetchRequest: Activity.all()) private var activities: FetchedResults<Activity>
    let days: [Date]
    let onEdit: (Activity) -> Void

    @State private var selected: WeekCell?
    @Environment(\.access) private var access

    var body: some View {
        let rows = rows
        let chosen = chosenCell(rows)
        VStack(spacing: Theme.Spacing.xl) {
            if rows.isEmpty {
                EmptyHint(systemImage: "figure.run", message: "Sem atividades")
            } else {
                WeekGrid(days: days, rowCount: rows.count) { row in
                    rowHeader(rows[row].child)
                } cell: { row, column in
                    cell(rows[row], day: days[column], chosen: chosen)
                }

                if let chosen, let row = rows.first(where: { $0.id == chosen.row }) {
                    VStack(spacing: Theme.Spacing.m) {
                        ForEach(row.occurrences(on: chosen.day)) { occurrence in
                            NavigationLink {
                                ActivityDetailView(activity: occurrence.activity, day: chosen.day, onEdit: onEdit)
                            } label: {
                                ActivityCard(occurrence: occurrence)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// What the person tapped, as long as it still has something; otherwise a sensible default.
    private func chosenCell(_ rows: [WeekRow]) -> WeekCell? {
        if let selected, let row = rows.first(where: { $0.id == selected.row }), !row.occurrences(on: selected.day).isEmpty {
            return selected
        }
        return defaultSelection(rows).map { WeekCell(row: $0.0.id, day: $0.1) }
    }

    /// One row per child with activities this week, then one for activities that belong to nobody.
    private var rows: [WeekRow] {
        let byDay = days.map { day in access.filter(ActivitySchedule.occurrences(of: Array(activities), on: day)) }
        var rows: [WeekRow] = []
        for (column, occurrences) in byDay.enumerated() {
            for occurrence in occurrences {
                let child = occurrence.activity.child
                let id = child?.objectID.uriRepresentation().absoluteString ?? "none"
                if let index = rows.firstIndex(where: { $0.id == id }) {
                    rows[index].byDay[column].append(occurrence)
                } else {
                    var row = WeekRow(id: id, child: child, days: days)
                    row.byDay[column].append(occurrence)
                    rows.append(row)
                }
            }
        }
        return rows.sorted { ($0.child?.createdAt ?? .distantFuture) < ($1.child?.createdAt ?? .distantFuture) }
    }

    /// Today's next activity if there is one, otherwise the first activity of the week.
    private func defaultSelection(_ rows: [WeekRow]) -> (WeekRow, Date)? {
        let calendar = Calendar.current
        if let today = days.first(where: calendar.isDateInToday) {
            let upcoming = rows
                .flatMap { row in row.occurrences(on: today).map { (row, $0) } }
                .filter { $0.1.start >= .now }
                .min { $0.1.start < $1.1.start }
            if let upcoming { return (upcoming.0, today) }
        }
        for day in days {
            if let row = rows.first(where: { !$0.occurrences(on: day).isEmpty }) { return (row, day) }
        }
        return nil
    }

    @ViewBuilder
    private func rowHeader(_ child: Member?) -> some View {
        if let child {
            MemberAvatar(member: child, size: 40)
        } else {
            Image(systemName: "person.2.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.hcInk)
                .frame(width: 40, height: 40)
                .background(Color.hcMuted, in: Circle())
                .accessibilityHidden(true)
        }
    }

    private func cell(_ row: WeekRow, day: Date, chosen: WeekCell?) -> some View {
        let occurrences = row.occurrences(on: day)
        let isSelected = chosen.map { $0.row == row.id && Calendar.current.isDate($0.day, inSameDayAs: day) } ?? false
        return Button {
            selected = WeekCell(row: row.id, day: day)
        } label: {
            WeekActivityCell(occurrences: occurrences, colour: row.colour, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(occurrences.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cellLabel(row, day: day, occurrences: occurrences))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHidden(occurrences.isEmpty)
    }

    private func cellLabel(_ row: WeekRow, day: Date, occurrences: [ActivityOccurrence]) -> Text {
        let titles = occurrences.map { $0.activity.title ?? "" }.joined(separator: ", ")
        let weekday = day.formatted(.dateTime.weekday(.wide))
        return Text("\(row.child?.name ?? ""), \(weekday), \(titles)")
    }
}

struct WeekCell: Equatable {
    let row: String
    let day: Date
}

/// One child's activities for each day of the shown week.
struct WeekRow: Identifiable {
    let id: String
    let child: Member?
    var byDay: [[ActivityOccurrence]]
    private let days: [Date]

    init(id: String, child: Member?, days: [Date]) {
        self.id = id
        self.child = child
        self.days = days
        byDay = Array(repeating: [], count: days.count)
    }

    var colour: Color { child.map { Color($0.palette.soft) } ?? .hcAccentSoft }

    func occurrences(on day: Date) -> [ActivityOccurrence] {
        guard let index = days.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: day) }) else { return [] }
        return byDay[index]
    }
}

/// The grid shared by activities and chores: a leading column, then seven day columns with today marked.
struct WeekGrid<Header: View, Cell: View>: View {
    let days: [Date]
    let rowCount: Int
    @ViewBuilder let header: (Int) -> Header
    @ViewBuilder let cell: (Int, Int) -> Cell

    static var leadingWidth: CGFloat { 44 }

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: Self.leadingWidth, height: 22)
                ForEach(days, id: \.self) { day in
                    dayLetter(day)
                }
            }
            ForEach(0..<rowCount, id: \.self) { row in
                GridRow {
                    header(row).frame(width: Self.leadingWidth)
                    ForEach(days.indices, id: \.self) { column in
                        cell(row, column)
                    }
                }
            }
        }
    }

    private func dayLetter(_ day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let letter = day.formatted(.dateTime.weekday(.narrow)).uppercased()
        return Text(verbatim: letter)
            .font(Theme.Typography.text(13, weight: .heavy))
            .foregroundStyle(isToday ? Color.white : Color.hcSecondaryInk)
            .frame(width: 28, height: 22)
            .background(isToday ? Color.hcAccent : Color.clear, in: Capsule())
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day()))
    }
}

/// A day square: empty, one or two icons on the child's colour, dashed coral when cancelled,
/// dark with a violet ring when chosen.
struct WeekActivityCell: View {
    let occurrences: [ActivityOccurrence]
    let colour: Color
    let isSelected: Bool

    private var allCancelled: Bool { !occurrences.isEmpty && occurrences.allSatisfy(\.isCancelled) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control)
        ZStack {
            if occurrences.isEmpty {
                shape.fill(Color.hcMuted)
            } else if allCancelled {
                shape.fill(Color.hcCard)
                shape.strokeBorder(Color.hcWarning, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            } else {
                shape.fill(isSelected ? Color.hcNight : colour)
            }
            icons
            if allCancelled {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: CGPoint(x: proxy.size.width * 0.2, y: proxy.size.height * 0.8))
                        path.addLine(to: CGPoint(x: proxy.size.width * 0.8, y: proxy.size.height * 0.2))
                    }
                    .stroke(Color.hcWarning, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }
        }
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .overlay {
            if isSelected { shape.inset(by: -3).strokeBorder(Color.hcAccent, lineWidth: 3) }
        }
    }

    private var icons: some View {
        let shown = occurrences.prefix(2)
        let size: CGFloat = shown.count > 1 ? 16 : 20
        return VStack(spacing: 4) {
            ForEach(shown) { occurrence in
                Image(systemName: occurrence.activity.symbol)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(iconColour)
            }
        }
    }

    private var iconColour: Color {
        if allCancelled { return .hcWarning }
        return isSelected ? colour : .hcNight
    }
}

/// The chosen activity, big: icon, time, where, who takes and brings, and what to pack.
struct ActivityCard: View {
    let occurrence: ActivityOccurrence

    var body: some View {
        let activity = occurrence.activity
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(spacing: 14) {
                Image(systemName: activity.symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.hcNight)
                    .frame(width: 64, height: 64)
                    .background(Color(activity.child?.palette.soft ?? Theme.Palette.lime), in: RoundedRectangle(cornerRadius: 20))
                Text(occurrence.start, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(Theme.Typography.display(44))
                    .foregroundStyle(.white)
                    .strikethrough(occurrence.isCancelled, color: .hcWarning)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let location = activity.location, !location.isEmpty, let url = Self.mapsURL(for: location) {
                    Link(destination: url) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .overlay { Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 2) }
                    }
                    .accessibilityLabel(Text(location))
                }
            }
            HStack(spacing: 10) {
                if occurrence.isCancelled {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.hcWarning)
                        .accessibilityLabel(Text("Cancelada"))
                } else if occurrence.dropOff != nil || occurrence.pickUp != nil {
                    Image(systemName: "car.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .accessibilityHidden(true)
                    driver(occurrence.dropOff)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .accessibilityHidden(true)
                    driver(occurrence.pickUp)
                }
                Spacer(minLength: 0)
                ForEach(Array(Self.items(in: activity.equipment).prefix(3).enumerated()), id: \.offset) { _, item in
                    Image(systemName: Self.symbol(forItem: item))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.12), in: Circle())
                        .accessibilityLabel(Text(item))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hcNight, in: RoundedRectangle(cornerRadius: 30))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(activity.title ?? ""), \(activity.child?.name ?? ""), \(occurrence.start.formatted(date: .omitted, time: .shortened))"))
    }

    @ViewBuilder
    private func driver(_ member: Member?) -> some View {
        if let member {
            MemberAvatar(member: member, size: 40)
        } else {
            Image(systemName: "questionmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [4, 3])) }
                .accessibilityLabel(Text("Ninguém"))
        }
    }

    /// "Chuteiras, água" → ["Chuteiras", "água"].
    static func items(in equipment: String?) -> [String] {
        (equipment ?? "")
            .split(whereSeparator: { ",;\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// A guess at an icon for something to pack, from words parents tend to write.
    static func symbol(forItem item: String) -> String {
        let text = item.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let guesses: [(words: [String], symbol: String)] = [
            (["agua", "garrafa", "cantil"], "drop.fill"),
            (["chuteira", "sapat", "tenis", "sapatilha", "bota"], "shoe.fill"),
            (["toalha", "touca", "fato de banho", "oculos"], "figure.pool.swim"),
            (["lanche", "comida", "fruta", "sandes"], "takeoutbag.and.cup.and.straw.fill"),
            (["livro", "caderno", "partitura"], "book.fill"),
            (["roupa", "equipamento", "camisola", "fato"], "tshirt.fill"),
            (["raquete", "bola"], "tennisball.fill"),
            (["instrumento", "flauta", "violino", "guitarra"], "music.note"),
        ]
        return guesses.first { guess in guess.words.contains { text.contains($0) } }?.symbol ?? "bag.fill"
    }

    static func mapsURL(for location: String) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: location)]
        return components?.url
    }
}

/// The activity's symbol on its child's colour (violet when nobody is set).
struct ActivityIcon: View {
    @ObservedObject var activity: Activity
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: activity.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(Color.hcNight)
            .frame(width: size, height: size)
            .background(Color(activity.child?.palette.soft ?? Theme.Palette.accentSoft), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .accessibilityHidden(true)
    }
}
