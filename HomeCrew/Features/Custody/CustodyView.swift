import CoreData
import SwiftUI

/// A month per child, each day in the colour of the house the child sleeps in.
struct CustodyView: View {
    @ObservedObject var family: Family
    @State private var childID: NSManagedObjectID?
    @State private var monthOffset = 0
    @State private var isEditing = false

    var body: some View {
        let children = family.sortedMembers.filter { $0.kind == .child }
        let child = children.first { $0.objectID == childID } ?? children.first

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(children, id: \.objectID) { candidate in
                            let isSelected = candidate == child
                            Button {
                                childID = candidate.objectID
                            } label: {
                                MemberAvatar(member: candidate, size: 44)
                                    .overlay { Circle().strokeBorder(Color.hcAccent, lineWidth: isSelected ? 3 : 0) }
                                    .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(candidate.name ?? ""))
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }

                if let child {
                    if let plan = child.custodyPlan {
                        HouseLegend(plan: plan)
                        MonthHeader(month: month, onPrevious: { monthOffset -= 1 }, onNext: { monthOffset += 1 }, onToday: { monthOffset = 0 })
                        CustodyMonthGrid(plan: plan, month: month)
                    } else {
                        Button {
                            isEditing = true
                        } label: {
                            Label("Definir guarda", systemImage: "calendar.badge.plus")
                                .font(Theme.Typography.cardTitle)
                                .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.hcAccent)
                    }
                } else {
                    EmptyHint(systemImage: "figure.child", message: "Ainda sem crianças")
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Color.hcBackground.ignoresSafeArea())
        .navigationTitle(Text("Guarda"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if child?.custodyPlan != nil {
                Button("Editar") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let child {
                CustodyPlanEditor(child: child, family: family)
            }
        }
    }

    private var month: Date {
        Calendar.current.date(byAdding: .month, value: monthOffset, to: .now) ?? .now
    }
}

private struct HouseLegend: View {
    @ObservedObject var plan: CustodyPlan

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            ForEach([plan.parentA, plan.parentB].compactMap { $0 }, id: \.objectID) { parent in
                HStack(spacing: Theme.Spacing.s) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(parent.palette.soft))
                        .frame(width: 18, height: 18)
                    MemberAvatar(member: parent, size: 24)
                    Text(parent.name ?? "")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Color.hcInk)
                }
            }
        }
    }
}

struct MonthHeader: View {
    let month: Date
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left").frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
            }
            .accessibilityLabel(Text("Mês anterior"))
            Spacer()
            Text(month, format: .dateTime.month(.wide).year())
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Color.hcInk)
                .onTapGesture(perform: onToday)
            Spacer()
            Button(action: onNext) {
                Image(systemName: "chevron.right").frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
            }
            .accessibilityLabel(Text("Mês seguinte"))
        }
    }
}

/// Monday-first month grid; blanks before the 1st keep weekdays in their columns.
struct CustodyMonthGrid: View {
    @ObservedObject var plan: CustodyPlan
    let month: Date

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let calendar = Calendar.current
        let days = Self.days(in: month, calendar: calendar)
        let symbols = calendar.veryShortWeekdaySymbols

        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(WeekdayPicker.mondayFirst, id: \.self) { weekday in
                Text(symbols[weekday - 1])
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Color.hcSecondaryInk)
            }
            ForEach(days.indices, id: \.self) { index in
                if let day = days[index] {
                    let custodian = plan.custodian(on: day, calendar: calendar)
                    let isToday = calendar.isDateInToday(day)
                    Text(day, format: .dateTime.day())
                        .font(Theme.Typography.body.weight(isToday ? .bold : .regular))
                        .foregroundStyle(custodian.map { Color($0.palette.foreground) } ?? Color.hcInk)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            custodian.map { Color($0.palette.soft) } ?? Color.hcCard,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay {
                            if isToday {
                                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.hcInk, lineWidth: 2)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(day.formatted(.dateTime.day().month())): \(custodian?.name ?? "")"))
                } else {
                    Color.clear.frame(minHeight: 40)
                }
            }
        }
    }

    static func days(in month: Date, calendar: Calendar) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = WeekdayPicker.mondayFirst.firstIndex(of: firstWeekday) ?? 0
        let days = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        return Array(repeating: nil, count: leading) + days.map { Optional($0) }
    }
}
