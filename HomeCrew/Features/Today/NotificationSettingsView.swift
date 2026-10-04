import SwiftUI

/// One switch per kind of agenda notification, and the time of the morning summary.
struct NotificationSettingsView: View {
    @AppStorage(AgendaNotificationSettings.beforeActivityKey) private var beforeActivity = true
    @AppStorage(AgendaNotificationSettings.dailySummaryKey) private var dailySummary = true
    @AppStorage(AgendaNotificationSettings.summaryMinutesKey) private var summaryMinutes = 7 * 60 + 30
    @AppStorage(AgendaNotificationSettings.changesKey) private var changes = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $beforeActivity) {
                        Label("30 min antes de levar", systemImage: "car")
                    }
                    Toggle(isOn: $dailySummary) {
                        Label("Resumo do dia", systemImage: "sun.horizon")
                    }
                    if dailySummary {
                        DatePicker("Hora", selection: summaryTime, displayedComponents: .hourAndMinute)
                    }
                    Toggle(isOn: $changes) {
                        Label("Alterações feitas por outros", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            .navigationTitle(Text("Notificações"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .onAppear { DoseReminderCenter.shared.requestAuthorization() }
    }

    /// The stored minutes as a time of day for the picker.
    private var summaryTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(byAdding: .minute, value: summaryMinutes, to: Calendar.current.startOfDay(for: .now)) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                summaryMinutes = (parts.hour ?? 7) * 60 + (parts.minute ?? 30)
            }
        )
    }
}
