import AVFoundation
import CoreData
import SwiftUI

/// The day at a glance: a greeting, whoever is ill, a short summary of the day, the day's activities in time
/// order, and the small chores not to forget.
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
                ForEach(people.filter { $0.activeEpisode != nil }, id: \.objectID) { person in
                    if let episode = person.activeEpisode {
                        NavigationLink(value: episode) {
                            IllnessRow(member: person, episode: episode)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("\(person.name ?? "") doente"))
                    }
                }
                DaySummaryCard(digest: digest, next: next, now: now)
                agendaSection(digest.agenda, next: next, now: now)
                if !digest.chores.isEmpty {
                    ChoreChecklist(chores: digest.chores, day: now) { chore in
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.dateLine(now))
                    .font(Theme.Typography.overline)
                    .tracking(0.6)
                    .foregroundStyle(Color.hcSecondaryInk)
                Text(Self.greeting(at: now, name: me?.name))
                    .font(Theme.Typography.screenTitle)
                    .foregroundStyle(Color.hcInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            Menu {
                Toggle(isOn: Binding(get: { onlyMine && me != nil }, set: { wanted in
                    if me == nil { isChoosingMe = true } else { onlyMine = wanted }
                })) {
                    Label("Só eu", systemImage: "person")
                }
                Button { isChoosingMe = true } label: { Label("Quem sou eu?", systemImage: "person.crop.circle.badge.questionmark") }
                Button { isShowingNotificationSettings = true } label: { Label("Notificações", systemImage: "bell") }
            } label: {
                HStack(spacing: -10) {
                    ForEach(people.prefix(4), id: \.objectID) { person in
                        MemberAvatar(member: person, size: 34, outlined: true)
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
                .frame(minHeight: Theme.minimumTapTarget)
            }
            .accessibilityLabel(Text(onlyMine ? "Só eu" : "Família"))
            .accessibilityIdentifier("today-people")
        }
    }

    /// "QUARTA-FEIRA, 22 DE OUTUBRO".
    static func dateLine(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_PT")
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: date).uppercased()
    }

    /// "Bom dia, Daniel", "Boa tarde" or "Boa noite", by the hour.
    static func greeting(at date: Date, name: String?, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let hello = hour < 12 ? String(localized: "Bom dia") : hour < 20 ? String(localized: "Boa tarde") : String(localized: "Boa noite")
        guard let first = name?.split(separator: " ").first else { return hello }
        return "\(hello), \(first)"
    }

    // MARK: Agenda

    private var showsCalendarOffer: Bool {
        deviceCalendar.access == .notAsked && !calendarOfferDismissed
    }

    private func agendaSection(_ agenda: [AgendaItem], next: ActivityOccurrence?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Hoje")
            VStack(spacing: 0) {
                if agenda.isEmpty {
                    Text("Nada marcado para hoje")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Color.hcSecondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                ForEach(Array(agenda.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowDivider() }
                    switch item {
                    case .activity(let occurrence):
                        NavigationLink {
                            ActivityDetailView(activity: occurrence.activity, day: now) { editingActivity = .existing($0) }
                        } label: {
                            AgendaRow(occurrence: occurrence, isNext: occurrence.id == next?.id, isPast: occurrence.start < now)
                        }
                        .buttonStyle(.plain)
                    case .external(let event):
                        ExternalEventRow(event: event)
                    }
                }
                if showsCalendarOffer {
                    RowDivider()
                    CalendarOfferRow {
                        Task { await deviceCalendar.requestAccess() }
                    } onDismiss: {
                        calendarOfferDismissed = true
                    }
                }
            }
            .card(padding: 0)
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

/// Someone ill, on rose, with their latest temperature; opens the episode.
struct IllnessRow: View {
    @ObservedObject var member: Member
    @ObservedObject var episode: IllnessEpisode

    var body: some View {
        HStack(spacing: 12) {
            MemberAvatar(member: member, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name ?? "")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Color.hcInk)
                HStack(spacing: 4) {
                    Image(systemName: "thermometer.medium")
                    Text("Doente")
                    if let reading = episode.latestReading {
                        Text(verbatim: "· " + reading.celsius.formatted(.number.precision(.fractionLength(1))) + "°")
                    }
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Color.hcWarning)
            }
            Spacer()
            Chevron()
        }
        .padding(14)
        .background(Color.hcWarningSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .contentShape(Rectangle())
    }
}

/// The day in one or two sentences on soft green, with a button to hear it read aloud.
struct DaySummaryCard: View {
    let digest: TodayDigest
    let next: ActivityOccurrence?
    let now: Date

    @State private var speaker = AVSpeechSynthesizer()

    var body: some View {
        let summary = Self.summary(digest: digest, next: next, now: now)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Calendar.current.component(.hour, from: now) < 18 ? "sun.max.fill" : "moon.stars.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color(UIColor(hex: 0xD99A2B)))
                .frame(width: 40, height: 40)
                .background(Color.hcCard, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("O teu dia")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Color.hcInk)
                Text(summary)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Color.hcSecondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                speak(summary)
            } label: {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.hcAccent)
                    .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Ouvir o resumo"))
        }
        .padding(14)
        .background(Color.hcAccentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityIdentifier("today-summary")
    }

    private func speak(_ text: String) {
        if speaker.isSpeaking {
            speaker.stopSpeaking(at: .immediate)
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "pt-PT")
        speaker.speak(utterance)
    }

    /// "3 atividades hoje. A seguir: Natação às 09:30. 2 tarefas por fazer."
    static func summary(digest: TodayDigest, next: ActivityOccurrence?, now: Date) -> String {
        let count = digest.activities.filter { !$0.isCancelled }.count
        var parts: [String] = []
        switch count {
        case 0: parts.append(String(localized: "Sem atividades hoje."))
        case 1: parts.append(String(localized: "1 atividade hoje."))
        default: parts.append(String(localized: "\(count) atividades hoje."))
        }
        if let next {
            let time = next.start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            parts.append(String(localized: "A seguir: \(next.activity.title ?? "") às \(time)."))
        } else if count > 0 {
            parts.append(String(localized: "Já não há mais nada hoje."))
        }
        let pending = digest.chores.filter { $0.completion(on: now) == nil }.count
        if pending == 1 {
            parts.append(String(localized: "1 tarefa por fazer."))
        } else if pending > 1 {
            parts.append(String(localized: "\(pending) tarefas por fazer."))
        }
        return parts.joined(separator: " ")
    }
}

/// An activity as a row: the time, a bar in the child's colour, the title and place, and the child's name on
/// their colour. The next one has its time in green; a sick child's activity says so; past ones fade.
struct AgendaRow: View {
    let occurrence: ActivityOccurrence
    let isNext: Bool
    let isPast: Bool

    var body: some View {
        let activity = occurrence.activity
        let child = activity.child
        let isSick = child?.activeEpisode != nil
        HStack(spacing: 12) {
            Text(occurrence.start, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(Theme.Typography.text(14, weight: isNext ? .bold : .semibold))
                .foregroundStyle(isNext ? Color.hcAccent : Color.hcInk)
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(child?.palette.foreground ?? Theme.Palette.accent))
                .frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title ?? "")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Color.hcInk)
                    .strikethrough(occurrence.isCancelled)
                    .lineLimit(1)
                if let place = activity.location, !place.isEmpty {
                    Text(place)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Color.hcSecondaryInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if isSick {
                Pill("Doente", foreground: .hcWarning, background: .hcWarningSoft)
            } else if let child {
                Pill(verbatim: child.name ?? "", foreground: Color(child.palette.foreground), background: Color(child.palette.soft))
            }
            Chevron()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(isPast || occurrence.isCancelled ? 0.45 : 1)
        .contentShape(Rectangle())
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

/// An event from the iPhone's calendar, as a row with a bar in the calendar's own colour.
struct ExternalEventRow: View {
    let event: ExternalEvent

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if event.isAllDay {
                    Image(systemName: "sun.max")
                } else {
                    Text(event.start, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                }
            }
            .font(Theme.Typography.text(14, weight: .semibold))
            .foregroundStyle(Color.hcInk)
            .monospacedDigit()
            .frame(width: 44, alignment: .leading)
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color.map { Color(cgColor: $0) } ?? Color.hcSecondaryInk)
                .frame(width: 4, height: 38)
            Text(event.title)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Color.hcInk)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "calendar")
                .font(.system(size: 13))
                .foregroundStyle(Color.hcSecondaryInk)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(event.title), \(event.start.formatted(date: .omitted, time: .shortened))"))
    }
}

/// A row that offers, once, to show the iPhone's calendar here.
struct CalendarOfferRow: View {
    let onAllow: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onAllow) {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.hcAccent)
                        .frame(width: 44, alignment: .leading)
                    Text("Ver aqui o Calendário do iPhone")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Color.hcAccent)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Ver o teu Calendário aqui"))
            .accessibilityHint(Text("Só leitura"))
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.hcSecondaryInk)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Agora não"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// Today's chores as a checklist: tap to tick, whose it is on the right.
struct ChoreChecklist: View {
    let chores: [Chore]
    let day: Date
    let onToggle: (Chore) -> Void

    var body: some View {
        let done = chores.filter { $0.completion(on: day) != nil }.count
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Não esquecer") {
                Text(verbatim: "\(done)/\(chores.count)")
                    .monospacedDigit()
                    .accessibilityLabel(Text("\(done) de \(chores.count) tarefas feitas"))
            }
            VStack(spacing: 0) {
                ForEach(Array(chores.enumerated()), id: \.element.objectID) { index, chore in
                    if index > 0 { RowDivider() }
                    row(for: chore)
                }
            }
            .card(padding: 0)
        }
    }

    private func row(for chore: Chore) -> some View {
        let isDone = chore.completion(on: day) != nil
        return Button { onToggle(chore) } label: {
            HStack(spacing: 12) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isDone ? Color.hcAccent : Color.hcSecondaryInk)
                Text(chore.title ?? "")
                    .font(Theme.Typography.body)
                    .foregroundStyle(isDone ? Color.hcSecondaryInk : Color.hcInk)
                    .strikethrough(isDone)
                Spacer()
                if let assignee = chore.assignee {
                    MemberAvatar(member: assignee, size: 26)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(chore.title ?? ""), \(chore.assignee?.name ?? "")"))
        .accessibilityValue(isDone ? Text("Feita") : Text("Por fazer"))
        .accessibilityAddTraits(.isButton)
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
