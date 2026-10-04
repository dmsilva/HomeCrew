import CoreData
import UIKit
import XCTest
@testable import HomeCrew

final class IllnessEpisodeTests: XCTestCase {
    private var persistence: PersistenceController!
    private var rita: Member!
    private let morning = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        let family = persistence.createFamily(named: "Silva")
        var draft = MemberDraft()
        draft.name = "Rita"
        draft.kind = .child
        rita = persistence.addMember(draft, to: family)
    }

    private func hours(_ value: Double) -> Date { morning.addingTimeInterval(value * 3600) }

    func testOpeningAnEpisodeMakesThePersonIll() {
        XCTAssertNil(rita.activeEpisode)

        let episode = persistence.openEpisode(for: rita, at: morning)

        XCTAssertEqual(rita.activeEpisode, episode)
        XCTAssertTrue(episode.isActive)
        XCTAssertEqual(episode.startedAt, morning)
    }

    func testOpeningTwiceReusesTheOpenEpisode() {
        let first = persistence.openEpisode(for: rita, at: morning)
        let second = persistence.openEpisode(for: rita, at: hours(2))

        XCTAssertEqual(first, second)
        XCTAssertEqual(rita.episodeHistory.count, 1)
    }

    func testEndingAnEpisodeKeepsItInTheHistory() {
        let episode = persistence.openEpisode(for: rita, at: morning)
        persistence.end(episode, at: hours(48))

        XCTAssertNil(rita.activeEpisode)
        XCTAssertFalse(episode.isActive)
        XCTAssertEqual(rita.episodeHistory, [episode])
    }

    func testHistoryIsNewestFirst() {
        let older = persistence.openEpisode(for: rita, at: morning)
        persistence.end(older, at: hours(24))
        let newer = persistence.openEpisode(for: rita, at: hours(200))

        XCTAssertEqual(rita.episodeHistory, [newer, older])
    }

    func testTemperaturesAreRoundedToOneDecimalAndSortedByTime() {
        let episode = persistence.openEpisode(for: rita, at: morning)
        persistence.recordTemperature(38.46, in: episode, at: hours(3))
        persistence.recordTemperature(37.2, in: episode, at: hours(1))
        persistence.recordTemperature(39.04, in: episode, at: hours(2))

        XCTAssertEqual(episode.sortedReadings.map(\.celsius), [37.2, 39.0, 38.5])
        XCTAssertEqual(episode.latestReading?.celsius, 38.5)
        XCTAssertEqual(episode.highestCelsius, 39.0)
    }

    func testFeverStartsAtThirtyEight() {
        let episode = persistence.openEpisode(for: rita, at: morning)
        let below = persistence.recordTemperature(37.9, in: episode, at: hours(1))
        let at = persistence.recordTemperature(38.0, in: episode, at: hours(2))

        XCTAssertFalse(below.isFever)
        XCTAssertTrue(at.isFever)
    }

    func testDeletingAReading() {
        let episode = persistence.openEpisode(for: rita, at: morning)
        let reading = persistence.recordTemperature(38.2, in: episode, at: hours(1))
        persistence.delete(reading)

        XCTAssertEqual(episode.sortedReadings, [])
        XCTAssertNil(episode.highestCelsius)
    }

    func testSymptomsAreToggled() {
        let episode = persistence.openEpisode(for: rita, at: morning)
        persistence.setSymptom(.cough, present: true, in: episode)
        persistence.setSymptom(.tiredness, present: true, in: episode)
        persistence.setSymptom(.cough, present: false, in: episode)

        XCTAssertEqual(episode.symptoms, [.tiredness])
    }

    func testEverySymptomSetSurvivesTheMask() {
        let episode = persistence.openEpisode(for: rita, at: morning)
        episode.symptoms = Set(Symptom.allCases)
        XCTAssertEqual(episode.symptoms, Set(Symptom.allCases))
        episode.symptoms = []
        XCTAssertEqual(episode.symptomMask, 0)
    }

    func testEverySymptomHasARealSymbol() {
        for symptom in Symptom.allCases {
            XCTAssertNotNil(UIImage(systemName: symptom.systemImage), "\(symptom) uses a missing SF Symbol")
        }
    }

    func testNotesAreSaved() {
        let episode = persistence.openEpisode(for: rita, at: morning)
        persistence.setNotes("Vomitou à noite", in: episode)
        XCTAssertEqual(episode.notes, "Vomitou à noite")
    }

    func testActiveRequestOnlyFindsOpenEpisodes() throws {
        let ended = persistence.openEpisode(for: rita, at: morning)
        persistence.end(ended, at: hours(24))
        let open = persistence.openEpisode(for: rita, at: hours(100))

        let found = try persistence.viewContext.fetch(IllnessEpisode.active())

        XCTAssertEqual(found, [open])
    }

    func testTodayAlertShowsTheLatestTemperatureOrTheName() {
        let episode = persistence.openEpisode(for: rita, at: morning)

        XCTAssertEqual(TodayAlert.illness([episode]).map(\.title), ["Rita"])

        persistence.recordTemperature(38.5, in: episode, at: hours(1))
        let alerts = TodayAlert.illness([episode])

        XCTAssertEqual(alerts.count, 1)
        XCTAssertTrue(alerts[0].title.hasSuffix("°"))
        XCTAssertTrue(alerts[0].title.contains("38"))
        XCTAssertEqual(alerts[0].member, rita)
    }

    func testEndedEpisodesRaiseNoAlert() {
        let episode = persistence.openEpisode(for: rita, at: morning)
        persistence.end(episode, at: hours(1))

        XCTAssertEqual(TodayAlert.illness([episode]), [])
    }

    func testDeletingThePersonDeletesTheirEpisodes() throws {
        let episode = persistence.openEpisode(for: rita, at: morning)
        persistence.recordTemperature(38.0, in: episode, at: hours(1))
        persistence.delete(rita)

        XCTAssertEqual(try persistence.viewContext.count(for: IllnessEpisode.active()), 0)
        XCTAssertEqual(try persistence.viewContext.count(for: NSFetchRequest<TemperatureReading>(entityName: "TemperatureReading")), 0)
    }
}
