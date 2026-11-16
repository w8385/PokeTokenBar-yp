import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct DialProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: [EvoNode(speciesID: 5, children: [])]),
                rarity: .common, names: [4: ["en": "Charmander"], 5: ["en": "Charmeleon"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

private func time(_ minute: Int, _ second: Int = 0) -> Date {
    Calendar.current.date(bySettingHour: 12, minute: minute, second: second, of: Date())!
}

final class DayNightDialMathTests: XCTestCase {
    func testCycleDegreesRunThroughTwentyMinutes() {
        func degrees(_ minute: Int, _ second: Int = 0) -> Double { DayPeriod.cycleDegrees(from: time(minute, second)) }
        XCTAssertEqual(degrees(0), 0, accuracy: 0.001)
        XCTAssertEqual(degrees(5), 90, accuracy: 0.001)
        XCTAssertEqual(degrees(10), 180, accuracy: 0.001)
        XCTAssertEqual(degrees(15), 270, accuracy: 0.001)
        XCTAssertEqual(degrees(19, 59), 359.7, accuracy: 0.001)
        XCTAssertEqual(degrees(20), 0, accuracy: 0.001, "the cycle repeats")
        XCTAssertEqual(degrees(35), 270, accuracy: 0.001)
    }

    func testSunRisesLeftTopsOutAndSetsRightWhileTheMoonIsHalfATurnBehind() {
        func near(_ a: (x: Double, y: Double), _ x: Double, _ y: Double, _ message: String) {
            XCTAssertEqual(a.x, x, accuracy: 0.001, message)
            XCTAssertEqual(a.y, y, accuracy: 0.001, message)
        }
        near(DayNightSky.sun(degrees: 0), -1, 0, "sunrise on the left")
        near(DayNightSky.sun(degrees: 90), 0, 1, "noon at the top")
        near(DayNightSky.sun(degrees: 180), 1, 0, "sunset on the right")
        near(DayNightSky.moon(degrees: 180), -1, 0, "the moon rises on the left as the sun sets")
        near(DayNightSky.moon(degrees: 270), 0, 1, "the moon tops out at :15")
    }

    func testSkyIsBlueByDayOrangeAtTheSwitchesAndNavyAtNight() {
        let noon = DayNightSky.sky(degrees: 90), dawn = DayNightSky.sky(degrees: 0), midnight = DayNightSky.sky(degrees: 270)
        XCTAssertGreaterThan(noon.blue, noon.red)
        XCTAssertGreaterThan(dawn.red, dawn.blue)
        XCTAssertLessThan(midnight.red + midnight.green + midnight.blue, 0.6)
        XCTAssertEqual(DayNightSky.starOpacity(degrees: 90), 0)
        XCTAssertEqual(DayNightSky.starOpacity(degrees: 270), 1)
    }
}

@MainActor
final class DayNightLabelTests: XCTestCase {
    nonisolated(unsafe) private var scratch: URL?
    override func tearDown() {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        super.tearDown()
    }

    private func store(clock: @escaping () -> Date) throws -> CompanionStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("daynight-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        scratch = dir
        let file = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(CompanionState()).write(to: file)
        return CompanionStore(provider: DialProvider(), clock: clock, fileURL: file)
    }

    func testPeriodAndMinutesFlipAtTheTenMinuteMarks() throws {
        var now = time(9, 59)
        let s = try store { now }
        func read() -> (DayPeriod, Int) {
            let value = s.dayPeriodNow()
            return (value.period, CompanionStore.minutes(value.secondsLeft))
        }
        XCTAssertEqual(read().0, .day)
        XCTAssertEqual(read().1, 1)
        now = time(10, 0)
        XCTAssertEqual(read().0, .night)
        XCTAssertEqual(read().1, 10)
        now = time(12, 30)
        XCTAssertEqual(read().1, 8)
        now = time(19, 59)
        XCTAssertEqual(read().0, .night)
        XCTAssertEqual(read().1, 1)
        now = time(20, 0)
        XCTAssertEqual(read().0, .day)
        XCTAssertEqual(read().1, 10)
    }

    func testBadgeNamesThePeriodAndMinutes() {
        let l = L(.ko)
        XCTAssertEqual(l.dayNightBadge(.day, minutesLeft: 7), "낮 7분")
        XCTAssertEqual(l.dayNightBadge(.night, minutesLeft: 3), "밤 3분")
        XCTAssertEqual(l.dayNightAccessibility(.day, minutesLeft: 7), "낮, 밤까지 7분")
    }

    /// Opt-in PR captures: `PTB_DAYNIGHT_SHOT_DIR=/tmp/shots swift test --filter DayNightLabelTests/testCaptureDial`.
    func testCaptureDial() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_DAYNIGHT_SHOT_DIR"] else {
            throw XCTSkip("Set PTB_DAYNIGHT_SHOT_DIR to write the PR screenshots")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marks: [(String, Int, Int)] = [(":00", 0, 0), (":05", 5, 0), (":09", 9, 0), (":10", 10, 0), (":15", 15, 0)]
        for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let strip = HStack(spacing: 14) {
                ForEach(marks, id: \.0) { mark in
                    VStack(spacing: 4) {
                        DayNightDial(degrees: DayPeriod.cycleDegrees(from: time(mark.1, mark.2)), width: 40)
                        Text(mark.0).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            let size = NSSize(width: 320, height: 80)
            try await OffscreenRender.capture(
                strip.frame(width: size.width, height: size.height)
                    .background(scheme == "light" ? Color.white : Color(white: 0.16))
                    .environment(\.colorScheme, scheme == "light" ? .light : .dark),
                size: size, appearance: appearance, settle: .seconds(1),
                to: directory.appendingPathComponent("day-night-dial-strip-\(scheme).png"))
        }

        var state = CompanionState()
        state.language = .ko
        state.installBaselineSet = true
        state.active = MonState(baseID: 4, pathIDs: [4, 5], stageIndex: 0, usedAtStage: 0, rarity: .common,
                                totalForms: 2, profile: PokemonProfile.generate(seed: 5, instanceID: "raised"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("daynight-shot-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let sprites = SpriteStore(directory: dir.appendingPathComponent("sprites"))
        for (name, minute) in [("day", 3), ("night", 12)] {
            let now = time(minute, 30)
            let store = CompanionStore(provider: DialProvider(), clock: { now }, fileURL: file,
                                       rng: SeededRNG(seed: 3))
            let size = NSSize(width: PopoverMetrics.contentWidth, height: 150)
            try await OffscreenRender.capture(
                CompanionHeader(store: store, spriteStore: sprites).padding(12)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
                    .environment(\.locale, AppLanguage.ko.displayLocale),
                size: size, appearance: .aqua, settle: .seconds(2),
                to: directory.appendingPathComponent("day-night-dial-home-\(name).png"))
        }
    }
}
