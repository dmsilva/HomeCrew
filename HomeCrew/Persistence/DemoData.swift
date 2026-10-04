import CoreData

/// A family with a full day, used by `-demoData` launches so screenshots show real screens instead of empty ones.
extension PersistenceController {
    func seedDemoFamilyIfEmpty(now: Date = .now) {
        let request = NSFetchRequest<Family>(entityName: "Family")
        guard ((try? viewContext.count(for: request)) ?? 0) == 0 else { return }

        let family = createFamily(named: "Silva")
        let calendar = Calendar.current
        let everyDay = Set(1...7)

        func member(_ name: String, _ kind: Member.Kind, age: Int, color: Int16) -> Member {
            var draft = MemberDraft()
            draft.name = name
            draft.kind = kind
            draft.birthDate = calendar.date(byAdding: .year, value: -age, to: now) ?? now
            draft.colorIndex = color
            return addMember(draft, to: family)
        }
        let daniel = member("Daniel", .adult, age: 38, color: 0)
        let sofia = member("Sofia", .adult, age: 36, color: 1)
        let tomas = member("Tomás", .child, age: 8, color: 2)
        let leonor = member("Leonor", .child, age: 5, color: 3)
        UserDefaults.standard.set(daniel.identifier?.uuidString, forKey: "meMemberID")

        func activity(_ title: String, _ symbol: String, _ child: Member, at minutes: Int, place: String) {
            var draft = ActivityDraft()
            draft.title = title
            draft.symbolName = symbol
            draft.child = child
            draft.dropOff = daniel
            draft.pickUp = sofia
            draft.weekdays = everyDay
            draft.startMinutes = minutes
            draft.location = place
            draft.startDate = calendar.date(byAdding: .day, value: -14, to: now) ?? now
            addActivity(draft, to: family)
        }
        activity("Natação", "figure.pool.swim", tomas, at: 9 * 60 + 30, place: "Piscina municipal")
        activity("Futebol", "soccerball", tomas, at: 11 * 60, place: "Campo do Sporting")
        activity("Música", "music.note", leonor, at: 17 * 60, place: "Academia")

        func chore(_ title: String, _ assignee: Member) {
            var draft = ChoreDraft()
            draft.title = title
            draft.assignee = assignee
            draft.recurrence = .daily
            draft.startDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            addChore(draft, to: family)
        }
        chore("Compras", sofia)
        chore("Arrumar o quarto", tomas)
        chore("Roupa", daniel)

        leonor.allergies = "Amendoim"
        let episode = openEpisode(for: leonor, at: now.addingTimeInterval(-2 * 86_400))
        for (hoursAgo, celsius) in [(48.0, 38.4), (36, 39.1), (24, 38.8), (12, 38.5), (2, 38.2)] {
            recordTemperature(celsius, in: episode, at: now.addingTimeInterval(-hoursAgo * 3600), by: sofia)
        }
        setSymptom(.cough, present: true, in: episode)
        setSymptom(.runnyNose, present: true, in: episode)
        var medicine = MedicationDraft()
        medicine.name = "Ben-u-ron"
        medicine.dose = "5 ml"
        medicine.intervalHours = 6
        medicine.responsible = sofia
        let medication = addMedication(medicine, to: episode, by: sofia, at: now.addingTimeInterval(-30 * 3600))
        giveDose(of: medication, by: sofia, at: now.addingTimeInterval(-4 * 3600))
        save()
    }
}
