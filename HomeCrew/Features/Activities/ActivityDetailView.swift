import SwiftUI

/// One activity on one day: when, where, what to bring and notes.
struct ActivityDetailView: View {
    @ObservedObject var activity: Activity
    let day: Date
    let onEdit: (Activity) -> Void

    var body: some View {
        List {
            Section {
                HStack(spacing: Theme.Spacing.l) {
                    ActivityIcon(activity: activity, size: 56)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(activity.title ?? "")
                            .font(Theme.Typography.screenTitle)
                            .foregroundStyle(Color.hcInk)
                        Text(day, format: .dateTime.weekday(.wide).day().month())
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Color.hcSecondaryInk)
                    }
                }
                .padding(.vertical, Theme.Spacing.s)

                detailRow("clock", Text(timeRange))
                if let child = activity.child {
                    HStack(spacing: Theme.Spacing.m) {
                        MemberAvatar(member: child, size: 28)
                        Text(child.name ?? "").foregroundStyle(Color.hcInk)
                    }
                }
                if let location = activity.location, !location.isEmpty {
                    detailRow("mappin.and.ellipse", Text(location))
                }
                if let equipment = activity.equipment, !equipment.isEmpty {
                    detailRow("bag", Text(equipment))
                }
                if let notes = activity.notes, !notes.isEmpty {
                    detailRow("note.text", Text(notes))
                }
            }
            .listRowBackground(Color.hcCard)
        }
        .scrollContentBackground(.hidden)
        .background(Color.hcBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Editar") { onEdit(activity) }
        }
    }

    private var timeRange: String {
        let start = activity.start(on: day)
        let end = start.addingTimeInterval(TimeInterval(activity.durationMinutes) * 60)
        return "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    private func detailRow(_ systemImage: String, _ text: Text) -> some View {
        Label { text.foregroundStyle(Color.hcInk) } icon: {
            Image(systemName: systemImage).foregroundStyle(Color.hcAccent)
        }
        .font(Theme.Typography.body)
    }
}
