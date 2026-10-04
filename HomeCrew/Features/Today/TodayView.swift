import CoreData
import SwiftUI

/// The day at a glance, drawn rather than written (Direção E): who is home, a ring per person with their
/// activities around the clock, the activities as big icons, and the chores as circles to tick.
struct TodayView: View {
    @FetchRequest(fetchRequest: Activity.all()) private var activities: FetchedResults<Activity>
    @FetchRequest(fetchRequest: Chore.all()) private var chores: FetchedResults<Chore>
    @FetchRequest(fetchRequest: Family.all()) private var families: FetchedResults<Family>
    @FetchRequest(fetchRequest: IllnessEpisode.active()) private var episodes: FetchedResults<IllnessEpisode>

    @AppStorage("meMemberID") private var meMemberID = ""
    @AppStorage("onlyMine") private var onlyMine = false
    @AppStorage("calendarOfferDismissed") private var calendarOfferDismissed = false
    @State private var isChoosingMe = false
    @State private var isShowingNotificationSettings = false
    @State private var editingActivity: ActivityEditorTarget?
    @StateObject private var deviceCalendar = DeviceCalendar()
    @Environment(\.access) private var access

    private let persistence = PersistenceController.shared

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                content(now: context.date)
            }
            .background(Color.hcBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { deviceCalendar.day = .now }
            .navigationDestination(for: IllnessEpisode.self) { EpisodeView(episode: $0) }
            .sheet(isPresented: $isShowingNotificationSettings) {
                NotificationSettingsView()
            }
            .sheet(isPresented: $isChoosingMe) {
                WhoAmIView(adults: families.first?.adults ?? []) { member in
                    meMemberID = member.identifier?.uuidString ?? ""
                    onlyMine = true
                    DoseReminderCenter.shared.requestAuthorization()
                    isChoosingMe = false
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $editingActivity) { target in
                if let family = families.first {
                    ActivityEditor(target: target, family: family, persistence: persistence)
                }
            }
        }
    }

    private func content(now: Date) -> some View {
        let digest = TodayDigest.build(
            day: now,
            activities: Array(activities),
            chores: Array(chores),
            alerts: TodayAlert.illness(Array(episodes)),
            externalEvents: deviceCalendar.events,
            me: onlyMine ? me : nil,
            access: access,
            viewer: me
        )
        let people = peopleToday(on: now)
        let next = digest.activities.first { !$0.isCancelled && $0.start > now }

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(now: now, people: people)
                    .accessibilityIdentifier("today-header")
                DayRings(people: people, occurrences: digest.activities, next: next, now: now)
                if !digest.agenda.isEmpty || showsCalendarOffer {
                    agendaGrid(digest.agenda, next: next, now: now)
                }
                if !digest.chores.isEmpty {
                    ChoreCircles(chores: digest.chores, day: now) { chore in
                        persistence.toggleDone(chore, on: now, by: me)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    // MARK: Header

    private func header(now: Date, people: [Member]) -> some View {
        HStack {
            Text(Self.dayTitle(now))
                .font(Theme.Typography.display(34))
                .foregroundStyle(Color.hcInk)
            Spacer()
            HStack(spacing: -12) {
                Menu {
                    Toggle(isOn: Binding(get: { onlyMine && me != nil }, set: { wanted in
                        if me == nil { isChoosingMe = true } else { onlyMine = wanted }
                    })) {
                        Label("Só eu", systemImage: "person")
                    }
                    Button { isChoosingMe = true } label: { Label("Quem sou eu?", systemImage: "person.crop.circle.badge.questionmark") }
                    Button { isShowingNotificationSettings = true } label: { Label("Notificações", systemImage: "bell") }
                } label: {
                    HStack(spacing: -12) {
                        ForEach(people.filter { $0.activeEpisode == nil }.prefix(5), id: \.objectID) { person in
                            MemberAvatar(member: person, size: 40, outlined: true)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if onlyMine, me != nil {
                            Image(systemName: "person.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Color.hcAccent, in: Circle())
                        }
                    }
                }
                .accessibilityLabel(Text(onlyMine ? "Só eu" : "Família"))
                .accessibilityIdentifier("today-people")

                ForEach(people.filter { $0.activeEpisode != nil }, id: \.objectID) { person in
                    if let episode = person.activeEpisode {
                        NavigationLink(value: episode) {
                            MemberAvatar(member: person, size: 40, outlined: true)
                        }
                        .accessibilityLabel(Text("\(person.name ?? "") doente"))
                    }
                }
            }
        }
    }

    /// "Dom 4": short weekday and the day, nothing else.
    static func dayTitle(_ date: Date, calendar: Calendar = .current) -> String {
        let symbols = DateFormatter()
        symbols.locale = Locale(identifier: "pt_PT")
        let weekday = symbols.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
            .replacingOccurrences(of: ".", with: "")
        return weekday.prefix(1).uppercased() + weekday.dropFirst() + " \(calendar.component(.day, from: date))"
    }

    // MARK: Agenda

    private var showsCalendarOffer: Bool {
        deviceCalendar.access == .notAsked && !calendarOfferDismissed
    }

    private func agendaGrid(_ agenda: [AgendaItem], next: ActivityOccurrence?, now: Date) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(agenda) { item in
                switch item {
                case .activity(let occurrence):
                    NavigationLink {
                        ActivityDetailView(activity: occurrence.activity, day: now) { editingActivity = .existing($0) }
                    } label: {
                        ActivityTile(occurrence: occurrence, isNext: occurrence.id == next?.id, isPast: occurrence.start < now)
                    }
                    .buttonStyle(.plain)
                case .external(let event):
                    ExternalEventTile(event: event)
                }
            }
            if showsCalendarOffer {
                CalendarOfferTile {
                    Task { await deviceCalendar.requestAccess() }
                } onDismiss: {
                    calendarOfferDismissed = true
                }
            }
        }
    }

    // MARK: People

    private var me: Member? {
        guard !meMemberID.isEmpty else { return nil }
        return families.lazy.flatMap(\.sortedMembers).first { $0.identifier?.uuidString == meMemberID }
    }

    /// Everyone this person can see who is home today: children at the other house are left out.
    private func peopleToday(on day: Date) -> [Member] {
        guard let family = families.first else { return [] }
        let everyone = access.visibleMembers(of: family).filter { $0.isWith(me, on: day) }
        if onlyMine, let me { return everyone.filter { $0 == me } }
        return everyone
    }
}

/// One ring per person on the violet card, 7:00 at the top round to 22:00: a solid arc while they are at an
/// activity, a short arc when they take or bring someone, a dashed coral ring while they are ill.
/// The middle shows the next activity's icon and how long until it starts.
struct DayRings: View {
    let people: [Member]
    let occurrences: [ActivityOccurrence]
    let next: ActivityOccurrence?
    let now: Date
    var calendar: Calendar = .current

    static let dayStartHour = 7
    static let dayEndHour = 22
    private static let lineWidth: CGFloat = 16
    private static let gap: CGFloat = 8
    private static let size: CGFloat = 250
    private static let driveMinutes = 20.0

    var body: some View {
        let rings = Array(people.prefix(5).enumerated())
        ZStack {
            ForEach(rings, id: \.element.objectID) { index, person in
                ring(for: person, diameter: Self.size - CGFloat(index) * 2 * (Self.lineWidth + Self.gap))
            }
            if let fraction = fraction(of: now), !rings.isEmpty {
                nowDot(at: fraction)
            }
            center
        }
        .frame(width: Self.size, height: Self.size)
        .frame(maxWidth: .infinity)
        .frame(height: 290)
        .background(Color.hcAccent, in: RoundedRectangle(cornerRadius: Theme.Radius.hero))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func ring(for person: Member, diameter: CGFloat) -> some View {
        let colour = Color(person.palette.soft)
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: Self.lineWidth)
            if person.activeEpisode != nil {
                Circle()
                    .stroke(Color.hcWarning, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, dash: [3, 10]))
            }
            ForEach(Array(segments(for: person).enumerated()), id: \.offset) { _, segment in
                Circle()
                    .trim(from: segment.lowerBound, to: segment.upperBound)
                    .stroke(colour, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func nowDot(at fraction: Double) -> some View {
        let radius = Self.size / 2
        let angle = fraction * 2 * .pi - .pi / 2
        return Circle()
            .fill(Color.white)
            .frame(width: 20, height: 20)
            .offset(x: cos(angle) * radius, y: sin(angle) * radius)
    }

    @ViewBuilder
    private var center: some View {
        VStack(spacing: 4) {
            if let next {
                Image(systemName: next.activity.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.hcLime)
                Text(Self.countdown(from: now, to: next.start))
                    .font(Theme.Typography.display(30))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Color.hcLime)
            }
        }
    }

    /// Parts of the day, as fractions of the ring, when this person is busy.
    func segments(for person: Member) -> [ClosedRange<Double>] {
        occurrences.filter { !$0.isCancelled }.flatMap { occurrence -> [ClosedRange<Double>] in
            let start = occurrence.start
            let end = start.addingTimeInterval(Double(occurrence.activity.durationMinutes) * 60)
            var parts: [(Date, Date)] = []
            if occurrence.activity.child == person { parts.append((start, end)) }
            if occurrence.dropOff == person { parts.append((start.addingTimeInterval(-Self.driveMinutes * 60), start)) }
            if occurrence.pickUp == person { parts.append((end, end.addingTimeInterval(Self.driveMinutes * 60))) }
            return parts.compactMap { from, to in
                guard let low = fraction(of: from, clamped: true), let high = fraction(of: to, clamped: true), high > low else { return nil }
                return low...high
            }
        }
    }

    /// Where a moment falls on the ring; nil outside the day unless clamped.
    func fraction(of date: Date, clamped: Bool = false) -> Double? {
        let dayStart = calendar.date(bySettingHour: Self.dayStartHour, minute: 0, second: 0, of: now) ?? now
        let span = Double(Self.dayEndHour - Self.dayStartHour) * 3600
        let value = date.timeIntervalSince(dayStart) / span
        if clamped { return min(max(value, 0), 1) }
        return (0...1).contains(value) ? value : nil
    }

    /// "12 min", "1h12", "3h".
    static func countdown(from now: Date, to start: Date) -> String {
        let minutes = max(Int(start.timeIntervalSince(now) / 60), 0)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours)h" : String(format: "%dh%02d", hours, rest)
    }

    private var accessibilitySummary: Text {
        guard let next else { return Text("Nada mais hoje") }
        return Text("\(next.activity.title ?? "") daqui a \(Self.countdown(from: now, to: next.start))")
    }
}

/// An activity as a square: its icon, the time, and a dot per adult who takes and brings.
/// The next one is dark; a sick child's activity is coral; past ones fade.
struct ActivityTile: View {
    let occurrence: ActivityOccurrence
    let isNext: Bool
    let isPast: Bool

    var body: some View {
        let activity = occurrence.activity
        let isSick = activity.child?.activeEpisode != nil
        let background: Color = isNext ? .hcNight : isSick ? .hcWarning : .hcCard
        let ink: Color = isNext ? .white : .hcNight
        VStack(spacing: 6) {
            Image(systemName: activity.symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isNext ? Color(activity.child?.palette.soft ?? Theme.Palette.lime) : ink)
            Text(occurrence.start, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                .font(Theme.Typography.text(16, weight: .heavy))
                .foregroundStyle(isSick && !isNext ? Color.hcNight : (isNext ? .white : .hcInk))
                .strikethrough(occurrence.isCancelled)
            HStack(spacing: 3) {
                ForEach([occurrence.dropOff, occurrence.pickUp].compactMap { $0 }.uniqued(), id: \.objectID) { adult in
                    Circle().fill(Color(adult.palette.soft)).frame(width: 10, height: 10)
                }
            }
            .frame(height: 10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay {
            if !isNext && !isSick {
                RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Color.hcInk, lineWidth: 2)
            }
        }
        .opacity(isPast || occurrence.isCancelled ? 0.45 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: Text {
        let activity = occurrence.activity
        let time = occurrence.start.formatted(date: .omitted, time: .shortened)
        return Text("\(activity.title ?? ""), \(activity.child?.name ?? ""), \(time)")
    }
}

/// An event from the iPhone's calendar, as a tile with a calendar glyph in the calendar's own colour.
struct ExternalEventTile: View {
    let event: ExternalEvent

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(event.color.map { Color(cgColor: $0) } ?? Color.hcInk)
            Group {
                if event.isAllDay {
                    Image(systemName: "sun.max")
                } else {
                    Text(event.start, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                }
            }
            .font(Theme.Typography.text(16, weight: .heavy))
            .foregroundStyle(Color.hcInk)
            Color.clear.frame(height: 10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background(Color.hcMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(event.title), \(event.start.formatted(date: .omitted, time: .shortened))"))
    }
}

/// A dashed tile that offers, once, to show the iPhone's calendar here.
struct CalendarOfferTile: View {
    let onAllow: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onAllow) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.hcInk)
                .frame(maxWidth: .infinity)
                .frame(height: 104)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .strokeBorder(Color.hcInk, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Agora não", action: onDismiss)
        }
        .accessibilityLabel(Text("Ver o teu Calendário aqui"))
        .accessibilityHint(Text("Só leitura"))
    }
}

/// Today's chores as circles: tap to tick. A dot in the person's colour says whose it is; done ones turn dark.
struct ChoreCircles: View {
    let chores: [Chore]
    let day: Date
    let onToggle: (Chore) -> Void

    var body: some View {
        let done = chores.filter { $0.completion(on: day) != nil }.count
        HStack(spacing: Theme.Spacing.m) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.m) {
                    ForEach(chores, id: \.objectID) { chore in
                        circle(for: chore)
                    }
                }
                .padding(4)
            }
            Text(verbatim: "\(done)/\(chores.count)")
                .font(Theme.Typography.display(22))
                .foregroundStyle(Color.hcInk)
                .monospacedDigit()
                .accessibilityLabel(Text("\(done) de \(chores.count) tarefas feitas"))
        }
    }

    private func circle(for chore: Chore) -> some View {
        let isDone = chore.completion(on: day) != nil
        return Button { onToggle(chore) } label: {
            Image(systemName: isDone ? "checkmark" : chore.symbol)
                .font(.system(size: 22, weight: isDone ? .heavy : .semibold))
                .foregroundStyle(isDone ? Color.hcLime : Color.hcInk)
                .frame(width: 58, height: 58)
                .background(isDone ? Color.hcNight : Color.hcCard, in: Circle())
                .overlay {
                    if !isDone { Circle().strokeBorder(Color.hcInk, lineWidth: 2) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let assignee = chore.assignee, !isDone {
                        Circle()
                            .fill(Color(assignee.palette.soft))
                            .frame(width: 18, height: 18)
                            .overlay { Circle().strokeBorder(Color.hcBackground, lineWidth: 2) }
                            .offset(x: 2, y: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(chore.title ?? ""), \(chore.assignee?.name ?? "")"))
        .accessibilityValue(isDone ? Text("Feita") : Text("Por fazer"))
        .accessibilityIdentifier("chore-\(chore.title ?? "")")
    }
}

extension Array where Element: Hashable {
    /// The elements in order, each only once.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

/// Pick which adult uses this iPhone, so "só eu" knows what is yours.
struct WhoAmIView: View {
    let adults: [Member]
    let onPick: (Member) -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Text("Quem sou eu?")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Color.hcInk)
            if adults.isEmpty {
                EmptyHint(systemImage: "person.2", message: "Ainda sem adultos")
            } else {
                HStack(spacing: Theme.Spacing.l) {
                    ForEach(adults, id: \.objectID) { adult in
                        Button { onPick(adult) } label: {
                            VStack(spacing: Theme.Spacing.s) {
                                MemberAvatar(member: adult, size: 64)
                                Text(adult.name ?? "")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Color.hcInk)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(Theme.Spacing.xl)
    }
}

#Preview {
    TodayView()
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).viewContext)
}
