import SwiftUI

/// Requests waiting for an answer first (with Aceitar/Recusar for whoever must answer), then the history.
struct SwapList: View {
    @ObservedObject var plan: CustodyPlan
    let me: Member?

    var body: some View {
        let swaps = plan.sortedSwaps
        if !swaps.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Label("Trocas", systemImage: "clock.arrow.circlepath")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Color.hcSecondaryInk)
                ForEach(swaps, id: \.objectID) { swap in
                    SwapRow(swap: swap, me: me)
                }
            }
            .padding(Theme.Spacing.l)
            .background(Color.hcCard, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }
}

struct SwapRow: View {
    @ObservedObject var swap: CustodySwap
    let me: Member?

    private let persistence = PersistenceController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                if let requester = swap.requester {
                    MemberAvatar(member: requester, size: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(SwapNotifications.dates(of: swap))
                        .font(Theme.Typography.body)
                        .foregroundStyle(Color.hcInk)
                    Text("\(swap.dayCount) dias")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Color.hcSecondaryInk)
                }
                Spacer()
                statusIcon
            }
            if swap.status == .pending {
                if canAnswer {
                    HStack {
                        Button("Recusar", role: .destructive) { persistence.respond(to: swap, accept: false) }
                            .buttonStyle(.bordered)
                        Button("Aceitar") { persistence.respond(to: swap, accept: true) }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.hcAccent)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else if swap.requester == me {
                    Button("Retirar pedido") { persistence.withdraw(swap) }
                        .font(Theme.Typography.caption)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    /// The other parent answers; on an iPhone that has not said who uses it, whoever holds it may.
    private var canAnswer: Bool {
        me == nil ? true : swap.responder == me
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch swap.status {
        case .pending:
            Image(systemName: "hourglass")
                .foregroundStyle(Color.hcSecondaryInk)
                .accessibilityLabel(Text("À espera"))
        case .accepted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.hcAccent)
                .accessibilityLabel(Text("Aceite"))
        case .declined:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.hcWarning)
                .accessibilityLabel(Text("Recusada"))
        }
    }
}

/// Pick the days to hand over; the other parent gets a notification and answers.
struct SwapRequestSheet: View {
    @ObservedObject var plan: CustodyPlan
    let me: Member?

    @Environment(\.dismiss) private var dismiss
    @State private var first = Calendar.current.startOfDay(for: .now)
    @State private var last = Calendar.current.startOfDay(for: .now)
    @State private var requester: Member?

    private let persistence = PersistenceController.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DriverPicker(
                        title: "Quem pede",
                        systemImage: "person.fill.questionmark",
                        adults: [plan.parentA, plan.parentB].compactMap { $0 },
                        selection: $requester
                    )
                }
                Section {
                    DatePicker("De", selection: $first, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    DatePicker("Até", selection: $last, in: first..., displayedComponents: .date)
                } footer: {
                    if let other = plan.otherParent(than: requester) {
                        Text("\(other.name ?? "") recebe o pedido.")
                    }
                }
            }
            .navigationTitle(Text("Pedir troca"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pedir") {
                        persistence.requestSwap(in: plan, from: first, to: last, by: requester)
                        DoseReminderCenter.shared.requestAuthorization()
                        dismiss()
                    }
                    .disabled(requester == nil)
                }
            }
            .onChange(of: first) { _, newFirst in
                if last < newFirst { last = newFirst }
            }
        }
        .onAppear {
            requester = me.flatMap { plan.otherParent(than: $0) != nil ? $0 : nil } ?? plan.parentA
        }
    }
}
