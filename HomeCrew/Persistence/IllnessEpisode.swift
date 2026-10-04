import CoreData

/// Symptoms recorded with a tap each; stored as bits so a set fits in one attribute.
enum Symptom: Int, CaseIterable, Identifiable {
    case cough, runnyNose, soreThroat, earache, headache, tummy, rash, tiredness

    var id: Int { rawValue }

    var systemImage: String {
        switch self {
        case .cough: "wind"
        case .runnyNose: "drop"
        case .soreThroat: "mouth"
        case .earache: "ear"
        case .headache: "brain.head.profile"
        case .tummy: "toilet"
        case .rash: "allergens"
        case .tiredness: "bed.double"
        }
    }

    var title: String {
        switch self {
        case .cough: String(localized: "Tosse")
        case .runnyNose: String(localized: "Nariz")
        case .soreThroat: String(localized: "Garganta")
        case .earache: String(localized: "Ouvidos")
        case .headache: String(localized: "Cabeça")
        case .tummy: String(localized: "Barriga")
        case .rash: String(localized: "Pele")
        case .tiredness: String(localized: "Cansaço")
        }
    }
}

/// A period of illness for one person: temperatures, symptoms and notes, from opening until it is ended.
@objc(IllnessEpisode)
final class IllnessEpisode: NSManagedObject {
    /// From this temperature on, a reading counts as fever.
    static let feverCelsius = 38.0

    @NSManaged var identifier: UUID?
    @NSManaged var startedAt: Date?
    @NSManaged var endedAt: Date?
    @NSManaged var symptomMask: Int64
    @NSManaged var notes: String?
    @NSManaged var member: Member?
    @NSManaged var readings: NSSet?
    @NSManaged var medications: NSSet?

    static func active() -> NSFetchRequest<IllnessEpisode> {
        let request = NSFetchRequest<IllnessEpisode>(entityName: "IllnessEpisode")
        request.predicate = NSPredicate(format: "endedAt == nil")
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: true)]
        return request
    }

    var isActive: Bool { endedAt == nil }

    var symptoms: Set<Symptom> {
        get { Set(Symptom.allCases.filter { symptomMask & (1 << Int64($0.rawValue)) != 0 }) }
        set { symptomMask = newValue.reduce(0) { $0 | (1 << Int64($1.rawValue)) } }
    }

    /// Readings oldest first, ready for the chart.
    var sortedReadings: [TemperatureReading] {
        ((readings as? Set<TemperatureReading>) ?? []).sorted {
            ($0.takenAt ?? .distantPast) < ($1.takenAt ?? .distantPast)
        }
    }

    var latestReading: TemperatureReading? { sortedReadings.last }

    var highestCelsius: Double? { sortedReadings.map(\.celsius).max() }
}

@objc(TemperatureReading)
final class TemperatureReading: NSManagedObject {
    @NSManaged var identifier: UUID?
    @NSManaged var takenAt: Date?
    @NSManaged var celsius: Double
    @NSManaged var episode: IllnessEpisode?

    var isFever: Bool { celsius >= IllnessEpisode.feverCelsius }
}

extension Member {
    var activeEpisode: IllnessEpisode? {
        ((episodes as? Set<IllnessEpisode>) ?? []).first(where: \.isActive)
    }

    /// Past and current episodes, newest first.
    var episodeHistory: [IllnessEpisode] {
        ((episodes as? Set<IllnessEpisode>) ?? []).sorted {
            ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast)
        }
    }
}

extension PersistenceController {
    /// Opens an episode, or returns the one already open: a person is ill once at a time.
    @discardableResult
    func openEpisode(for member: Member, at date: Date = .now) -> IllnessEpisode {
        if let open = member.activeEpisode { return open }
        let episode = IllnessEpisode(context: viewContext)
        if let store = member.objectID.persistentStore {
            viewContext.assign(episode, to: store)
        }
        episode.identifier = UUID()
        episode.startedAt = date
        episode.member = member
        save()
        return episode
    }

    func end(_ episode: IllnessEpisode, at date: Date = .now) {
        // The member's views (avatar badge, health page) observe the member, not the episode.
        episode.member?.objectWillChange.send()
        episode.endedAt = date
        save()
    }

    @discardableResult
    func recordTemperature(_ celsius: Double, in episode: IllnessEpisode, at date: Date = .now) -> TemperatureReading {
        let reading = TemperatureReading(context: viewContext)
        if let store = episode.objectID.persistentStore {
            viewContext.assign(reading, to: store)
        }
        reading.identifier = UUID()
        reading.takenAt = date
        reading.celsius = (celsius * 10).rounded() / 10
        reading.episode = episode
        save()
        return reading
    }

    func delete(_ reading: TemperatureReading) {
        viewContext.delete(reading)
        save()
    }

    func setSymptom(_ symptom: Symptom, present: Bool, in episode: IllnessEpisode) {
        var symptoms = episode.symptoms
        if present { symptoms.insert(symptom) } else { symptoms.remove(symptom) }
        episode.symptoms = symptoms
        save()
    }

    func setNotes(_ notes: String, in episode: IllnessEpisode) {
        episode.notes = notes
        save()
    }
}

extension TodayAlert {
    /// One alert per person who is ill, showing their latest temperature when there is one.
    static func illness(_ episodes: [IllnessEpisode]) -> [TodayAlert] {
        episodes.filter(\.isActive).map { episode in
            let temperature = episode.latestReading.map {
                $0.celsius.formatted(.number.precision(.fractionLength(1))) + "°"
            }
            return TodayAlert(
                id: "episode-\(episode.objectID.uriRepresentation().absoluteString)",
                systemImage: "thermometer.medium",
                title: temperature ?? (episode.member?.name ?? ""),
                member: episode.member
            )
        }
    }
}
