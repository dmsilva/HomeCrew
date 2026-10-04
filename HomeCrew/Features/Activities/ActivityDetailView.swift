import SwiftUI

/// One activity on one day: when, where, what to bring and notes.
struct ActivityDetailView: View {
    @ObservedObject var activity: Activity
    let day: Date
    let onEdit: (Activity) -> Void

    @Environment(\.access) private var access
    private let persistence = PersistenceController.shared

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

            Section {
                if isCancelled {
                    Label("Cancelada neste dia", systemImage: "xmark.circle")
                        .foregroundStyle(Color.hcSecondaryInk)
                } else {
                    driverRow(title: "Leva", systemImage: "arrow.right.circle", current: activity.dropOff(on: day)) { member in
                        persistence.overrideDrivers(activity, on: day, dropOff: member, pickUp: exception?.pickUp)
                    }
                    driverRow(title: "Traz", systemImage: "arrow.left.circle", current: activity.pickUp(on: day)) { member in
                        persistence.overrideDrivers(activity, on: day, dropOff: exception?.dropOff, pickUp: member)
                    }
                }
            } footer: {
                if exception != nil && !isCancelled {
                    Text("Alterado só neste dia")
                }
            }
            .listRowBackground(Color.hcCard)

            if access.canEdit {
                Section {
                    Button(role: isCancelled ? nil : .destructive) {
                        persistence.setCancelled(!isCancelled, activity, on: day)
                    } label: {
                        Label(
                            isCancelled ? LocalizedStringKey("Repor este dia") : LocalizedStringKey("Cancelar este dia"),
                            systemImage: isCancelled ? "arrow.uturn.backward" : "xmark"
                        )
                    }
                    if exception != nil && !isCancelled {
                        Button {
                            persistence.overrideDrivers(activity, on: day, dropOff: nil, pickUp: nil)
                        } label: {
                            Label("Voltar à regra", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
                .listRowBackground(Color.hcCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.hcBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if access.canEdit {
                Button("Editar") { onEdit(activity) }
            }
        }
    }

    private var exception: ActivityException? { activity.exception(on: day) }
    private var isCancelled: Bool { activity.isCancelled(on: day) }

    /// The person for this day, with a menu to pick someone else for this day only.
    private func driverRow(
        title: LocalizedStringKey,
        systemImage: String,
        current: Member?,
        change: @escaping (Member?) -> Void
    ) -> some View {
        Menu {
            ForEach(activity.family?.adults ?? [], id: \.objectID) { adult in
                Button(adult.name ?? "") { change(adult) }
            }
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.hcAccent)
                    .accessibilityLabel(Text(title))
                if let current {
                    MemberAvatar(member: current, size: 28)
                    Text(current.name ?? "").foregroundStyle(Color.hcInk)
                } else {
                    Text("Ninguém").foregroundStyle(Color.hcSecondaryInk)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.hcSecondaryInk)
            }
            .frame(minHeight: Theme.minimumTapTarget)
        }
        .disabled(!access.canEdit)
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
