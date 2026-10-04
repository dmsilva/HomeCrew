import CoreData
import SwiftUI

/// A Monday-first week: each day lists its activities with the child's colour and icon.
struct ActivitiesWeekView: View {
    @FetchRequest(fetchRequest: Activity.all()) private var activities: FetchedResults<Activity>
    @State private var weekOffset = 0
    let onEdit: (Activity) -> Void

    var body: some View {
        let days = ActivitySchedule.week(containing: referenceDate)

        VStack(spacing: 0) {
            weekHeader(days)
            if activities.isEmpty {
                EmptyHint(systemImage: "figure.run", message: "Sem atividades")
            } else {
                List {
                    ForEach(days, id: \.self) { day in
                        let occurrences = ActivitySchedule.occurrences(of: Array(activities), on: day)
                        if !occurrences.isEmpty {
                            Section {
                                ForEach(occurrences) { occurrence in
                                    NavigationLink {
                                        ActivityDetailView(activity: occurrence.activity, day: day, onEdit: onEdit)
                                    } label: {
                                        ActivityRow(occurrence: occurrence)
                                    }
                                    .listRowBackground(Color.hcCard)
                                }
                            } header: {
                                Text(day, format: .dateTime.weekday(.wide).day())
                                    .font(Theme.Typography.caption.weight(.semibold))
                                    .foregroundStyle(Calendar.current.isDateInToday(day) ? Color.hcAccent : Color.hcSecondaryInk)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var referenceDate: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: weekOffset, to: .now) ?? .now
    }

    private func weekHeader(_ days: [Date]) -> some View {
        HStack {
            Button { weekOffset -= 1 } label: {
                Image(systemName: "chevron.left")
                    .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
            }
            .accessibilityLabel(Text("Semana anterior"))
            Spacer()
            if let first = days.first, let last = days.last {
                Text("\(first, format: .dateTime.day().month(.abbreviated)) – \(last, format: .dateTime.day().month(.abbreviated))")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Color.hcInk)
                    .onTapGesture { weekOffset = 0 }
            }
            Spacer()
            Button { weekOffset += 1 } label: {
                Image(systemName: "chevron.right")
                    .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
            }
            .accessibilityLabel(Text("Semana seguinte"))
        }
        .padding(.horizontal, Theme.Spacing.s)
    }
}

/// Time, icon on the child's colour, title and the child's avatar.
struct ActivityRow: View {
    let occurrence: ActivityOccurrence

    var body: some View {
        let activity = occurrence.activity
        HStack(spacing: Theme.Spacing.m) {
            Text(occurrence.start, format: .dateTime.hour().minute())
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Color.hcSecondaryInk)
                .frame(width: 48, alignment: .leading)
            ActivityIcon(activity: activity, size: 36)
            Text(activity.title ?? "")
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Color.hcInk)
            Spacer()
            if let child = activity.child {
                MemberAvatar(member: child, size: 28)
            }
        }
    }
}

/// The activity's symbol tinted with its child's colour (accent when nobody is set).
struct ActivityIcon: View {
    @ObservedObject var activity: Activity
    var size: CGFloat = 44

    var body: some View {
        let colors = activity.child?.palette ?? (foreground: Theme.Palette.accent, soft: Theme.Palette.accentSoft)
        Image(systemName: activity.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(Color(colors.foreground))
            .frame(width: size, height: size)
            .background(Color(colors.soft), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .accessibilityHidden(true)
    }
}
