import Foundation
import XCTest
import KeepGreenKit

/// Mirrors tests/KeepGreen.Tests/Program.cs, plus a few Swift-specific checks.
/// 2 November 2026 is a Monday; 6 November is a Friday.
final class CoreTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func on(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func defaults() -> AppSettings {
        var settings = AppSettings()
        settings.normalize(today: LocalDate(year: 2026, month: 11, day: 1))
        return settings
    }

    private func at(_ now: Date, locked: Bool = false, onBattery: Bool = false, battery: Int = 100, appRunning: Bool = true) -> PresenceContext {
        PresenceContext(now: now, isLocked: locked, isOnBattery: onBattery, batteryPercent: battery, isWatchedAppRunning: appRunning)
    }

    private func schedule(_ settings: AppSettings, _ now: Date) -> ScheduleStatus {
        WorkSchedule.evaluate(settings, now: now, calendar: calendar)
    }

    private func decide(_ settings: AppSettings, _ context: PresenceContext, boostUntil: Date? = nil) -> PresenceDecision {
        PresencePolicy.evaluate(settings, context: context, boostUntil: boostUntil, calendar: calendar)
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("KeepGreen.Tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // MARK: - Schedule

    func testWeekdayInsideWorkHoursIsActiveUntilTheEnd() {
        let status = schedule(defaults(), on(2, 10))
        XCTAssertEqual(status.state, .active)
        XCTAssertEqual(status.nextChange, on(2, 17))
    }

    func testBeforeWorkHoursWaitsForTodaysStart() {
        let status = schedule(defaults(), on(2, 7))
        XCTAssertEqual(status.state, .offSchedule)
        XCTAssertEqual(status.nextChange, on(2, 8))
    }

    func testFridayEveningSkipsTheWeekend() {
        let status = schedule(defaults(), on(6, 18))
        XCTAssertEqual(status.state, .offSchedule)
        XCTAssertEqual(status.nextChange, on(9, 8))
    }

    func testSaturdayIsOffByDefault() {
        let status = schedule(defaults(), on(7, 12))
        XCTAssertEqual(status.state, .offSchedule)
        XCTAssertEqual(status.nextChange, on(9, 8))
    }

    func testLunchBreakPausesAndResumes() {
        var settings = defaults()
        settings.lunchBreakEnabled = true

        let during = schedule(settings, on(2, 12, 10))
        XCTAssertEqual(during.state, .onBreak)
        XCTAssertEqual(during.nextChange, on(2, 12, 30))

        let before = schedule(settings, on(2, 11))
        XCTAssertEqual(before.state, .active)
        XCTAssertEqual(before.nextChange, on(2, 12))
    }

    func testADayOffIsSkipped() {
        var settings = defaults()
        settings.daysOff.append(LocalDate(year: 2026, month: 11, day: 2))

        let status = schedule(settings, on(2, 10))
        XCTAssertEqual(status.state, .dayOff)
        XCTAssertEqual(status.nextChange, on(3, 8))
    }

    func testNightShiftRunsPastMidnight() {
        var settings = defaults()
        for index in settings.week.indices {
            settings.week[index].enabled = settings.week[index].day == .monday
        }
        settings.updateDay(.monday) {
            $0.start = TimeOfDay(22, 0)
            $0.end = TimeOfDay(6, 0)
        }

        let night = schedule(settings, on(3, 3))
        XCTAssertEqual(night.state, .active)
        XCTAssertEqual(night.nextChange, on(3, 6))

        let morning = schedule(settings, on(3, 7))
        XCTAssertEqual(morning.state, .offSchedule)
        XCTAssertEqual(morning.nextChange, on(9, 22))
    }

    func testEqualStartAndEndMeansAFullDay() {
        var settings = defaults()
        settings.updateDay(.monday) {
            $0.start = TimeOfDay(0, 0)
            $0.end = TimeOfDay(0, 0)
        }

        let status = schedule(settings, on(2, 23, 30))
        XCTAssertEqual(status.state, .active)
        XCTAssertEqual(status.nextChange, on(3, 0))
        XCTAssertEqual(settings.day(.monday)?.lengthText, "24 h")
    }

    func testNightShiftAcrossTheEndOfDaylightSavingTime() {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!

        var settings = defaults()
        for index in settings.week.indices {
            settings.week[index].enabled = settings.week[index].day == .saturday
        }
        settings.updateDay(.saturday) {
            $0.start = TimeOfDay(22, 0)
            $0.end = TimeOfDay(6, 0)
        }

        // Clocks go back from 03:00 to 02:00 early on Sunday 25 October 2026, so this shift lasts 9 hours.
        let now = berlin.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 5, minute: 30))!
        let status = WorkSchedule.evaluate(settings, now: now, calendar: berlin)
        XCTAssertEqual(status.state, .active)
        XCTAssertEqual(status.nextChange, berlin.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 6))!)

        let window = WorkSchedule.windowFor(settings, day: LocalDate(year: 2026, month: 10, day: 24), calendar: berlin)
        XCTAssertEqual(window.map { $0.end.timeIntervalSince($0.start) }, TimeInterval(9 * 3600))
    }

    // MARK: - Presence policy

    func testMasterSwitchOffMeansDisabled() {
        var settings = defaults()
        settings.isEnabled = false
        XCTAssertEqual(decide(settings, at(on(2, 10))).state, .disabled)
    }

    func testABoostBeatsTheSwitchAndTheSchedule() {
        var settings = defaults()
        settings.isEnabled = false

        let decision = decide(settings, at(on(7, 12)), boostUntil: on(7, 13))
        XCTAssertEqual(decision.state, .active)
        XCTAssertTrue(decision.isBoosted, "expected a boosted decision")
        XCTAssertEqual(decision.nextChange, on(7, 13))
    }

    func testAnExpiredBoostNoLongerCounts() {
        let decision = decide(defaults(), at(on(7, 12)), boostUntil: on(7, 11))
        XCTAssertEqual(decision.state, .offSchedule)
        XCTAssertFalse(decision.isBoosted, "expected no boost")
    }

    func testLockingPausesEvenWhenBoosted() {
        let decision = decide(defaults(), at(on(2, 10), locked: true), boostUntil: on(2, 11))
        XCTAssertEqual(decision.state, .locked)
    }

    func testLowBatteryPausesOnlyWhenUnplugged() {
        XCTAssertEqual(decide(defaults(), at(on(2, 10), onBattery: true, battery: 10)).state, .lowBattery)
        XCTAssertEqual(decide(defaults(), at(on(2, 10), onBattery: false, battery: 10)).state, .active)
        XCTAssertEqual(decide(defaults(), at(on(2, 10), onBattery: true, battery: -1)).state, .active)
    }

    func testPauseOnBatteryPower() {
        var settings = defaults()
        settings.pauseOnBattery = true
        XCTAssertEqual(decide(settings, at(on(2, 10), onBattery: true, battery: 80)).state, .onBattery)
    }

    func testWaitsForWatchedApps() {
        var settings = defaults()
        settings.onlyWhenAppsRunning = true
        XCTAssertEqual(decide(settings, at(on(2, 10), appRunning: false)).state, .waitingForApp)
        XCTAssertEqual(decide(settings, at(on(2, 10), appRunning: true)).state, .active)
    }

    func testScheduleOffRunsAroundTheClock() {
        var settings = defaults()
        settings.useSchedule = false

        let decision = decide(settings, at(on(7, 3)))
        XCTAssertEqual(decision.state, .active)
        XCTAssertNil(decision.nextChange)
    }

    func testEndOfWorkday() {
        XCTAssertEqual(WorkSchedule.endOfWorkday(defaults(), now: on(2, 10), calendar: calendar), on(2, 17))
        XCTAssertEqual(WorkSchedule.endOfWorkday(defaults(), now: on(2, 7), calendar: calendar), on(2, 17))
        XCTAssertEqual(WorkSchedule.endOfWorkday(defaults(), now: on(7, 12), calendar: calendar), on(8, 0))
    }

    func testStateRawValuesMatchTheRemoteAPI() {
        XCTAssertEqual(
            PresenceState.allCases.map(\.rawValue),
            ["Active", "Disabled", "OffSchedule", "DayOff", "Break", "Locked", "OnBattery", "LowBattery", "WaitingForApp"])
    }

    // MARK: - Settings files

    func testSettingsSurviveASaveAndLoad() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = SettingsStore(folder: folder)
        var settings = defaults()
        settings.style = .invisibleMouse
        settings.intervalSeconds = 90
        settings.lunchStart = TimeOfDay(13, 15)
        settings.daysOff.append(LocalDate(year: 2026, month: 12, day: 24))
        settings.updateDay(.saturday) { $0.enabled = true }
        try store.saveSettings(settings)

        let loaded = store.loadSettings(today: LocalDate(year: 2026, month: 11, day: 1))
        XCTAssertEqual(loaded.style, .invisibleMouse)
        XCTAssertEqual(loaded.intervalSeconds, 90)
        XCTAssertEqual(loaded.lunchStart, TimeOfDay(13, 15))
        XCTAssertEqual(loaded.daysOff, [LocalDate(year: 2026, month: 12, day: 24)])
        XCTAssertEqual(loaded.day(.saturday)?.enabled, true, "Saturday should stay enabled")
        XCTAssertEqual(loaded, settings)
    }

    func testACorruptSettingsFileFallsBackToDefaults() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = SettingsStore(folder: folder)
        try Data("{ not json".utf8).write(to: store.settingsURL)

        let loaded = store.loadSettings(today: LocalDate(year: 2026, month: 11, day: 1))
        XCTAssertEqual(loaded.intervalSeconds, 60)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.settingsURL.path + ".broken"), "the broken file should be kept")
    }

    func testMissingKeysFallBackToDefaults() throws {
        let json = #"{"intervalSeconds": 90, "style": "SomethingNewer", "week": [{"day": "Saturday", "enabled": true}]}"#
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        settings.normalize(today: LocalDate(year: 2026, month: 11, day: 1))

        XCTAssertEqual(settings.intervalSeconds, 90)
        XCTAssertEqual(settings.style, .declareActivity)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.watchedApps, AppSettings.defaultWatchedApps)
        XCTAssertEqual(settings.week.count, 7)
        XCTAssertEqual(settings.day(.saturday)?.enabled, true)
        XCTAssertEqual(settings.day(.saturday)?.start, TimeOfDay(8))
        XCTAssertEqual(settings.day(.monday)?.enabled, true)
        XCTAssertFalse(settings.remoteEnabled)
        XCTAssertNil(settings.remoteKey)
    }

    func testStatsFromAnotherDayStartFresh() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = SettingsStore(folder: folder)
        try store.saveStats(DailyStats(date: LocalDate(year: 2026, month: 11, day: 1), nudges: 12, activeSeconds: 300, lastNudge: on(1, 9)))

        let sameDay = store.loadStats(today: LocalDate(year: 2026, month: 11, day: 1))
        XCTAssertEqual(sameDay.nudges, 12)
        XCTAssertEqual(sameDay.lastNudge, on(1, 9))

        let nextDay = store.loadStats(today: LocalDate(year: 2026, month: 11, day: 2))
        XCTAssertEqual(nextDay, DailyStats(date: LocalDate(year: 2026, month: 11, day: 2)))
    }

    func testNormalizeRepairsBadValues() {
        var settings = AppSettings()
        settings.intervalSeconds = 5
        settings.lowBatteryPercent = 200
        settings.week.remove(at: 3)
        settings.updateDay(.monday) { $0.start = TimeOfDay(8, 10) }
        settings.daysOff.append(LocalDate(year: 2026, month: 10, day: 1))
        settings.remoteKey = "not a key"
        settings.normalize(today: LocalDate(year: 2026, month: 11, day: 1))

        XCTAssertEqual(settings.intervalSeconds, AppSettings.minIntervalSeconds)
        XCTAssertEqual(settings.lowBatteryPercent, 95)
        XCTAssertEqual(settings.week.count, 7)
        XCTAssertEqual(settings.week.map(\.day), Weekday.weekOrder)
        XCTAssertEqual(settings.day(.monday)?.start, TimeOfDay(8, 0))
        XCTAssertEqual(settings.daysOff.count, 0)
        XCTAssertNil(settings.remoteKey)

        settings.intervalSeconds = 999
        settings.normalize(today: LocalDate(year: 2026, month: 11, day: 1))
        XCTAssertEqual(settings.intervalSeconds, AppSettings.maxIntervalSeconds)
    }

    func testRemoteKeyValidation() {
        XCTAssertTrue(AppSettings.isValidRemoteKey("00112233445566778899aabbccddeeff"))
        XCTAssertFalse(AppSettings.isValidRemoteKey("00112233445566778899AABBCCDDEEFF"))
        XCTAssertFalse(AppSettings.isValidRemoteKey("0011"))
    }

    func testWatchedAppNamesAreCleanedUp() {
        var settings = AppSettings()
        settings.watchedApps = "Microsoft Teams.app, Slack;  zoom.us\nslack ; , SLACK.exe"
        XCTAssertEqual(settings.watchedAppNames(), ["Microsoft Teams", "Slack", "zoom.us"])
        XCTAssertEqual(AppSettings().watchedAppNames(), ["Microsoft Teams", "Slack", "zoom.us"])
    }

    // MARK: - Time types and friendly text

    func testTimesAndDatesUseStableJSON() throws {
        let encoded = try JSONEncoder().encode([TimeOfDay(8, 5)])
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #"["08:05"]"#)

        let times = try JSONDecoder().decode([TimeOfDay].self, from: Data(#"["17:30:00", "9:00"]"#.utf8))
        XCTAssertEqual(times, [TimeOfDay(17, 30), TimeOfDay(9, 0)])

        let dates = try JSONEncoder().encode([LocalDate(year: 2026, month: 12, day: 24)])
        XCTAssertEqual(String(decoding: dates, as: UTF8.self), #"["2026-12-24"]"#)
    }

    func testLocalDateArithmetic() {
        XCTAssertEqual(LocalDate(year: 2026, month: 11, day: 2).weekday, .monday)
        XCTAssertEqual(LocalDate(year: 2026, month: 11, day: 8).weekday, .sunday)
        XCTAssertEqual(LocalDate(year: 2026, month: 12, day: 31).adding(days: 1), LocalDate(year: 2027, month: 1, day: 1))
        XCTAssertEqual(LocalDate(year: 2028, month: 2, day: 28).adding(days: 1), LocalDate(year: 2028, month: 2, day: 29))
        XCTAssertEqual(LocalDate(year: 2026, month: 3, day: 1).adding(days: -1), LocalDate(year: 2026, month: 2, day: 28))
        XCTAssertEqual(LocalDate(on(5, 23, 59), calendar: calendar), LocalDate(year: 2026, month: 11, day: 5))
    }

    func testFriendlyTimes() {
        let now = on(2, 9)
        XCTAssertEqual(Humanize.when(on(2, 17), now: now, calendar: calendar), "today at 17:00")
        XCTAssertTrue(Humanize.when(on(3, 8), now: now, calendar: calendar).hasPrefix("tomorrow at"), "tomorrow")
        XCTAssertTrue(Humanize.when(on(5, 8), now: now, calendar: calendar).hasPrefix("Thursday at"), "weekday")
        XCTAssertTrue(Humanize.when(on(20, 8), now: now, calendar: calendar).hasPrefix("on 20 Nov at"), "date")
        XCTAssertEqual(Humanize.time(on(2, 8, 5), calendar: calendar), "08:05")
    }

    func testFriendlyDurations() {
        XCTAssertEqual(Humanize.duration(42), "42 s")
        XCTAssertEqual(Humanize.duration(5.5 * 60), "5 min")
        XCTAssertEqual(Humanize.duration(6 * 3600 + 12 * 60 + 30), "6 h 12 min")
        XCTAssertEqual(Humanize.duration(2 * 3600), "2 h")
        XCTAssertEqual(Humanize.duration(-5), "0 s")
    }
}
