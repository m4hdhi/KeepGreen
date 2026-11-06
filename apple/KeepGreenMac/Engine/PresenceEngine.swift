import AppKit
import Combine
import KeepGreenKit

/// The menu bar symbol, published separately so the menu bar only redraws when it really changes.
@MainActor
final class MenuBarIcon: ObservableObject {
    @Published private(set) var symbol = "circle.dashed"
    @Published private(set) var label = "Starting"

    func update(symbol: String, label: String) {
        if symbol != self.symbol { self.symbol = symbol }
        if label != self.label { self.label = label }
    }
}

enum SchedulePreset: CaseIterable, Identifiable {
    case weekdaysNineToFive
    case weekdaysEightToSix
    case everyDayEightToEight

    var id: Self { self }

    var title: String {
        switch self {
        case .weekdaysNineToFive: return "Mon–Fri 9–17"
        case .weekdaysEightToSix: return "Mon–Fri 8–18"
        case .everyDayEightToEight: return "Every day 8–20"
        }
    }

    var days: [Weekday] {
        switch self {
        case .weekdaysNineToFive, .weekdaysEightToSix: return [.monday, .tuesday, .wednesday, .thursday, .friday]
        case .everyDayEightToEight: return Weekday.weekOrder
        }
    }

    var start: TimeOfDay { self == .weekdaysNineToFive ? TimeOfDay(9) : TimeOfDay(8) }

    var end: TimeOfDay {
        switch self {
        case .weekdaysNineToFive: return TimeOfDay(17)
        case .weekdaysEightToSix: return TimeOfDay(18)
        case .everyDayEightToEight: return TimeOfDay(20)
        }
    }
}

struct SelfTestResult: Equatable {
    var ok: Bool
    var message: String
}

/// The heart of KeepGreen. Once a second it asks PresencePolicy whether to be working,
/// holds the Mac awake while it is, and nudges only after the user has been idle long enough.
@MainActor
final class PresenceEngine: ObservableObject {
    private static let appScanInterval: TimeInterval = 5
    private static let statsSaveInterval: TimeInterval = 60

    private static let accessibilityWarning =
        "The Invisible mouse style needs Accessibility access. Allow KeepGreen in System Settings → Privacy & Security → " +
        "Accessibility, or switch How to nudge to Declare activity."

    private static let refusedWarning =
        "macOS refused KeepGreen's nudge. Try the Invisible mouse style under Behavior in Settings."

    /// Every setting. Changing it saves to disk (debounced) and re-evaluates right away.
    @Published var settings: AppSettings {
        didSet { settingsChanged(from: oldValue) }
    }

    @Published private(set) var warning: String? = nil
    @Published private(set) var isAccessibilityTrusted = MacSystem.isAccessibilityTrusted()
    @Published private(set) var isSelfTestRunning = false

    // Refreshed every tick; one objectWillChange per tick updates every view, like the Windows dashboard.
    private(set) var decision = PresenceDecision(state: .disabled, isBoosted: false, nextChange: nil)
    private(set) var boostUntil: Date?
    private(set) var headline = "Starting…"
    private(set) var detail = ""
    private(set) var scheduleSummary = ""
    private(set) var idleSeconds: TimeInterval = 0
    private(set) var stats: DailyStats

    let icon = MenuBarIcon()
    let store: SettingsStore

    /// Called after the state or the boost changes: (previous, current).
    var onTransition: ((PresenceDecision, PresenceDecision) -> Void)?

    /// Called after any setting changes, with the new settings.
    var onSettingsChange: ((AppSettings) -> Void)?

    private let nudger = Nudger()
    private let awake = AwakeAssertion()
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var saveTask: Task<Void, Never>?
    private var lastTick = Date()
    private var lastStatsSave = Date()
    private var lastAppScan = Date.distantPast
    private var nextAttemptAllowed = Date.distantPast
    private var awaitingVerification: Date?
    private var watchedAppRunning = false
    private var isLocked = false
    private var threshold: Double
    private var failedNudges = 0

    init(settings: AppSettings, store: SettingsStore) {
        self.settings = settings
        self.store = store
        stats = store.loadStats(today: LocalDate(Date()))
        threshold = PresenceEngine.makeThreshold(settings)
    }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }

        observeSystem()
        tick()
        startTimer()
    }

    /// Releases every assertion and writes everything to disk. Called when KeepGreen quits.
    func stop() {
        timer?.invalidate()
        timer = nil

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers.forEach { distributedCenter.removeObserver($0) }
        distributedObservers.removeAll()

        awake.release()
        nudger.releaseActivity()
        saveTask?.cancel()
        saveSettingsNow()
        saveStats()
    }

    // MARK: - Commands

    func setEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
    }

    func boost(minutes: Int) {
        setBoost(Date().addingTimeInterval(TimeInterval(minutes * 60)))
    }

    func boostUntilEndOfWorkday() {
        setBoost(WorkSchedule.endOfWorkday(settings, now: Date()))
    }

    func cancelBoost() {
        setBoost(nil)
    }

    func applyPreset(_ preset: SchedulePreset) {
        var updated = settings
        for index in updated.week.indices {
            updated.week[index].enabled = preset.days.contains(updated.week[index].day)
            updated.week[index].start = preset.start
            updated.week[index].end = preset.end
        }
        updated.useSchedule = true
        settings = updated
    }

    func addDayOff(_ day: LocalDate) {
        guard !settings.daysOff.contains(day) else { return }
        var updated = settings
        updated.daysOff.append(day)
        updated.daysOff.sort()
        settings = updated
    }

    func removeDayOff(_ day: LocalDate) {
        settings.daysOff.removeAll { $0 == day }
    }

    /// Turns the phone remote on or off. The first time it turns on, a pairing key is made.
    func setRemoteEnabled(_ enabled: Bool) {
        var updated = settings
        updated.remoteEnabled = enabled
        if enabled && updated.remoteKey == nil {
            updated.remoteKey = RemoteKeyMaker.makeKey()
        }
        settings = updated
    }

    /// Makes a new key, which signs every paired phone out.
    func unpairAllPhones() {
        settings.remoteKey = RemoteKeyMaker.makeKey()
    }

    func requestAccessibility() {
        MacSystem.requestAccessibility()
        refreshAccessibility()
    }

    /// Sends one nudge and checks that macOS really registered it.
    func runSelfTest() async -> SelfTestResult {
        isSelfTestRunning = true
        defer { isSelfTestRunning = false }

        let style: NudgeStyle = settings.style == .awakeOnly ? .declareActivity : settings.style

        // Wait for the click on "Run test" to age, so the check measures KeepGreen and not the click.
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard MacSystem.idleSeconds() >= 2 else {
            return SelfTestResult(
                ok: false,
                message: "You used the mouse or keyboard during the test. Run it again and keep your hands off for 3 seconds.")
        }

        switch nudger.send(style) {
        case .needsAccessibility:
            refreshAccessibility()
            return SelfTestResult(ok: false, message: PresenceEngine.accessibilityWarning)
        case .refused:
            return SelfTestResult(ok: false, message: PresenceEngine.refusedWarning)
        case .sent:
            break
        }

        try? await Task.sleep(nanoseconds: 500_000_000)
        let idle = MacSystem.idleSeconds()
        if idle < 1 {
            return SelfTestResult(
                ok: true,
                message: "Activity registered: the macOS idle timer went back to 0. Teams, Slack and Zoom will see you as active.")
        }
        return SelfTestResult(
            ok: false,
            message: "macOS didn't register the nudge (idle time is still \(Humanize.duration(idle))). " + PresenceEngine.otherStyleHint(for: style))
    }

    // MARK: - Texts for the menu, the settings window and the phone remote

    var state: PresenceState { decision.state }

    var isActive: Bool { decision.isActive }

    var hasBoost: Bool { boostUntil != nil }

    var shortStatus: String {
        switch decision.state {
        case .active: return decision.isBoosted ? "Boosted" : "Active"
        case .disabled: return "Off"
        case .offSchedule: return "Off schedule"
        case .dayOff: return "Day off"
        case .onBreak: return "On a break"
        case .locked: return "Paused: locked"
        case .onBattery, .lowBattery: return "Paused: battery"
        case .waitingForApp: return "Waiting for apps"
        }
    }

    var idleText: String { Humanize.duration(idleSeconds) }

    var nextNudgeText: String {
        if !isActive { return "—" }
        if settings.style == .awakeOnly { return "Off" }
        return Humanize.duration(max(0, threshold - idleSeconds))
    }

    var nudgesTodayText: String { stats.nudges.formatted() }

    var lastNudgeText: String {
        guard let last = stats.lastNudge else { return "None yet today" }
        return "Last one at \(Humanize.time(last))"
    }

    var greenTimeText: String { Humanize.duration(stats.activeSeconds) }

    var boostText: String {
        guard let until = boostUntil else { return "" }
        return "Boost on until \(Humanize.time(until))"
    }

    // MARK: - The tick

    func tick() {
        objectWillChange.send()

        let now = Date()
        let calendar = Calendar.keepGreen
        rollOverDay(now, calendar: calendar)

        if let until = boostUntil, until <= now {
            boostUntil = nil
        }

        let power = MacSystem.powerStatus()
        let context = PresenceContext(
            now: now,
            isLocked: isLocked,
            isOnBattery: power.isOnBattery,
            batteryPercent: power.batteryPercent,
            isWatchedAppRunning: isWatchedAppRunning(now))
        let newDecision = PresencePolicy.evaluate(settings, context: context, boostUntil: boostUntil, calendar: calendar)

        if newDecision.isActive {
            awake.hold()
        } else {
            awake.release()
            nudger.releaseActivity()
        }
        idleSeconds = MacSystem.idleSeconds()
        refreshAccessibility()

        if newDecision.isActive {
            let elapsed = now.timeIntervalSince(lastTick)
            if elapsed > 0 && elapsed < 5 {
                stats.activeSeconds += elapsed
            }

            verifyLastNudge(now)
            let due = idleSeconds >= threshold && now >= nextAttemptAllowed
            if settings.style != .awakeOnly && due {
                sendNudge(now)
            }
        } else {
            awaitingVerification = nil
        }

        lastTick = now
        let previous = decision
        decision = newDecision
        updateTexts(now, calendar: calendar)
        updateIcon()

        if previous.state != newDecision.state || previous.isBoosted != newDecision.isBoosted {
            onTransition?(previous, newDecision)
        }

        if now.timeIntervalSince(lastStatsSave) >= PresenceEngine.statsSaveInterval {
            saveStats()
        }
    }

    private func sendNudge(_ now: Date) {
        let outcome = nudger.send(settings.style)
        nextAttemptAllowed = now.addingTimeInterval(outcome == .sent ? 2 : 15)
        threshold = PresenceEngine.makeThreshold(settings)

        switch outcome {
        case .sent:
            awaitingVerification = now
            stats.nudges += 1
            stats.lastNudge = now
        case .needsAccessibility:
            warning = PresenceEngine.accessibilityWarning
        case .refused:
            warning = PresenceEngine.refusedWarning
        }
    }

    /// A second after a nudge, checks that the idle timer actually reset.
    private func verifyLastNudge(_ now: Date) {
        guard let sentAt = awaitingVerification, now.timeIntervalSince(sentAt) >= 1 else { return }

        awaitingVerification = nil
        if idleSeconds <= now.timeIntervalSince(sentAt) + 1 {
            failedNudges = 0
            warning = nil
            return
        }

        nextAttemptAllowed = now.addingTimeInterval(15)
        failedNudges += 1
        if failedNudges >= 2 {
            warning = PresenceEngine.notRegisteringWarning(for: settings.style)
        }
    }

    private func isWatchedAppRunning(_ now: Date) -> Bool {
        guard settings.onlyWhenAppsRunning else { return true }
        if now.timeIntervalSince(lastAppScan) < PresenceEngine.appScanInterval {
            return watchedAppRunning
        }

        lastAppScan = now
        watchedAppRunning = MacSystem.isAnyAppRunning(settings.watchedAppNames())
        return watchedAppRunning
    }

    private func refreshAccessibility() {
        let trusted = MacSystem.isAccessibilityTrusted()
        if trusted != isAccessibilityTrusted {
            isAccessibilityTrusted = trusted
            if trusted && warning == PresenceEngine.accessibilityWarning {
                warning = nil
            }
        }
    }

    private func updateTexts(_ now: Date, calendar: Calendar) {
        func when(_ moment: Date?) -> String {
            guard let moment = moment else { return "soon" }
            return Humanize.when(moment, now: now, calendar: calendar)
        }

        let current = decision
        switch current.state {
        case .active where current.isBoosted:
            headline = "Boosted: you're staying green"
            detail = "The boost ends \(when(current.nextChange))."
        case .active where current.nextChange != nil:
            headline = "You're staying green"
            detail = "Work hours end \(when(current.nextChange))."
        case .active:
            headline = "You're staying green"
            detail = "Your Mac stays awake and your status stays available."
        case .disabled:
            headline = "KeepGreen is off"
            detail = "Flip the switch to turn it on."
        case .offSchedule:
            headline = "Outside your work hours"
            detail = current.nextChange == nil
                ? "No work hours are set. Pick some days under Schedule in Settings."
                : "Turns on by itself \(when(current.nextChange))."
        case .dayOff:
            headline = "Day off. Enjoy it!"
            detail = "Back to work \(when(current.nextChange))."
        case .onBreak:
            headline = "On a lunch break"
            detail = "Your status can show Away until \(when(current.nextChange))."
        case .locked:
            headline = "Paused while your Mac is locked"
            detail = "Starts again as soon as you unlock."
        case .onBattery:
            headline = "Paused on battery power"
            detail = "Starts again when you plug in."
        case .lowBattery:
            headline = "Paused: battery is low"
            detail = "Starts again when you plug in."
        case .waitingForApp:
            headline = "Waiting for your apps"
            let names = settings.watchedAppNames().prefix(3)
            detail = names.isEmpty
                ? "Add your chat apps under Behavior in Settings."
                : "Starts when \(names.joined(separator: " or ")) is running."
        }

        scheduleSummary = buildScheduleSummary(now, calendar: calendar, when: when)
    }

    private func buildScheduleSummary(_ now: Date, calendar: Calendar, when: (Date?) -> String) -> String {
        guard settings.useSchedule else {
            return "Schedule is off: KeepGreen works whenever its switch is on."
        }

        let status = WorkSchedule.evaluate(settings, now: now, calendar: calendar)
        switch status.state {
        case .active:
            return "Work hours right now. They end \(when(status.nextChange))."
        case .onBreak:
            return "Lunch break right now. Back \(when(status.nextChange))."
        default:
            return status.nextChange == nil
                ? "No work hours set yet. Tick at least one day."
                : "Next work hours start \(when(status.nextChange))."
        }
    }

    private func updateIcon() {
        let symbol: String
        switch decision.state {
        case .active: symbol = decision.isBoosted ? "bolt.circle.fill" : "checkmark.circle.fill"
        case .disabled: symbol = "circle.dashed"
        case .offSchedule, .dayOff, .onBreak: symbol = "moon.circle"
        case .locked, .onBattery, .lowBattery, .waitingForApp: symbol = "pause.circle"
        }
        icon.update(symbol: symbol, label: shortStatus)
    }

    // MARK: - Helpers

    private func setBoost(_ until: Date?) {
        boostUntil = until
        tick()
    }

    private static func makeThreshold(_ settings: AppSettings) -> Double {
        let interval = Double(settings.intervalSeconds)
        return settings.randomizeInterval ? interval * Double.random(in: 0.8...1.2) : interval
    }

    private static func notRegisteringWarning(for style: NudgeStyle) -> String {
        switch style {
        case .invisibleMouse:
            return "macOS is ignoring KeepGreen's mouse nudges, so your status may still go Away. " + otherStyleHint(for: style)
        case .declareActivity, .awakeOnly:
            return "macOS isn't counting KeepGreen's nudges as activity, so your status may still go Away. " + otherStyleHint(for: style)
        }
    }

    private static func otherStyleHint(for style: NudgeStyle) -> String {
        style == .invisibleMouse
            ? "Check that KeepGreen is allowed under System Settings → Privacy & Security → Accessibility, or try Declare activity."
            : "Try the Invisible mouse style under Behavior in Settings."
    }

    private func rollOverDay(_ now: Date, calendar: Calendar) {
        let today = LocalDate(now, calendar: calendar)
        guard stats.date != today else { return }
        stats = DailyStats(date: today)
        saveStats()
    }

    private func saveStats() {
        lastStatsSave = Date()
        // Stats are nice to have; a failed write must never stop the engine.
        try? store.saveStats(stats)
    }

    private func saveSettingsNow() {
        try? store.saveSettings(settings)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 600_000_000)
            } catch {
                return
            }
            self?.saveSettingsNow()
        }
    }

    private func settingsChanged(from old: AppSettings) {
        if old.intervalSeconds != settings.intervalSeconds || old.randomizeInterval != settings.randomizeInterval {
            threshold = PresenceEngine.makeThreshold(settings)
        }
        if old.onlyWhenAppsRunning != settings.onlyWhenAppsRunning || old.watchedApps != settings.watchedApps {
            lastAppScan = .distantPast
        }
        if old.isEnabled && !settings.isEnabled {
            boostUntil = nil
        }
        if old.style != settings.style {
            failedNudges = 0
            awaitingVerification = nil
            nextAttemptAllowed = .distantPast
            warning = nil
        }

        scheduleSave()
        onSettingsChange?(settings)
        if timer != nil {
            tick()
        }
    }

    // MARK: - System events

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let engine = self else { return }
            Task { @MainActor in engine.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func observeSystem() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let engine = self else { return }
            Task { @MainActor in engine.handleWake() }
        })

        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers.append(distributedCenter.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            guard let engine = self else { return }
            Task { @MainActor in engine.setLocked(true) }
        })
        distributedObservers.append(distributedCenter.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            guard let engine = self else { return }
            Task { @MainActor in engine.setLocked(false) }
        })
    }

    private func setLocked(_ locked: Bool) {
        guard locked != isLocked else { return }
        isLocked = locked
        tick()
    }

    /// After sleep: restart the timer, take the assertions again and don't count the time asleep as green time.
    private func handleWake() {
        timer?.invalidate()
        timer = nil
        lastTick = Date()
        awake.release()
        nudger.releaseActivity()
        tick()
        startTimer()
    }
}
