import SwiftUI

/// Pick the person and the period, create the PDF, then share it through the iOS share sheet.
struct DoctorReportSheet: View {
    let members: [Member]

    @Environment(\.dismiss) private var dismiss
    @State private var member: Member?
    @State private var period: DoctorReport.Period = .month
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var pdf: URL?
    @State private var failed = false

    init(members: [Member], selected: Member? = nil) {
        self.members = members
        _member = State(initialValue: selected ?? members.first { $0.kind == .child } ?? members.first)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.m) {
                            ForEach(members, id: \.objectID) { candidate in
                                let isSelected = candidate == member
                                Button {
                                    member = candidate
                                    pdf = nil
                                } label: {
                                    VStack(spacing: Theme.Spacing.xs) {
                                        MemberAvatar(member: candidate, size: 48)
                                            .overlay {
                                                Circle().strokeBorder(Color.hcAccent, lineWidth: isSelected ? 3 : 0)
                                            }
                                        Text(candidate.name ?? "")
                                            .font(Theme.Typography.caption)
                                            .foregroundStyle(Color.hcInk)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(candidate.name ?? ""))
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                    }
                }
                Section {
                    Picker(selection: $period) {
                        ForEach(DoctorReport.Period.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label("Período", systemImage: "calendar")
                    }
                    if period == .custom {
                        DatePicker("De", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                        DatePicker("Até", selection: $customEnd, in: customStart...Date.now, displayedComponents: .date)
                    }
                }
                .onChange(of: period) { pdf = nil }
                .onChange(of: customStart) { pdf = nil }
                .onChange(of: customEnd) { pdf = nil }

                Section {
                    if let pdf {
                        ShareLink(item: pdf) {
                            Label("Partilhar PDF", systemImage: "square.and.arrow.up")
                                .font(Theme.Typography.cardTitle)
                        }
                    } else {
                        Button {
                            create()
                        } label: {
                            Label("Criar PDF", systemImage: "doc.richtext")
                                .font(Theme.Typography.cardTitle)
                        }
                        .disabled(member == nil)
                    }
                }
            }
            .navigationTitle(Text("PDF para o médico"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .alert("Não foi possível criar o PDF.", isPresented: $failed) {}
        }
    }

    private var interval: DateInterval {
        let calendar = Calendar.current
        if let preset = period.interval(endingAt: .now, calendar: calendar) { return preset }
        let start = calendar.startOfDay(for: customStart)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEnd)) ?? customEnd
        return DateInterval(start: start, end: max(start, end))
    }

    private func create() {
        guard let member else { return }
        do {
            pdf = try DoctorReportRenderer.render(DoctorReport(member: member, period: interval, createdAt: .now))
        } catch {
            failed = true
        }
    }
}
