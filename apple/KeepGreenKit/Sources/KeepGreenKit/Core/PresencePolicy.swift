import Foundation

/// What KeepGreen is doing right now. The raw values are part of the remote API and match the Windows app.
public enum PresenceState: String, Codable, CaseIterable, Sendable {
    /// Keeping the computer awake and the status green.
    case active = "Active"

    /// The master switch is off.
    case disabled = "Disabled"

    case offSchedule = "OffSchedule"
    case dayOff = "DayOff"
    case onBreak = "Break"
    case locked = "Locked"
    case onBattery = "OnBattery"
    case lowBattery = "LowBattery"
    case waitingForApp = "WaitingForApp"
}

/// A snapshot of the machine, gathered by the app once per tick.
public struct PresenceContext: Equatable, Sendable {
    public var now: Date
    public var isLocked: Bool
    public var isOnBattery: Bool

    /// 0 to 100, or -1 when unknown (for example on a desktop Mac).
    public var batteryPercent: Int

    public var isWatchedAppRunning: Bool

    public init(now: Date, isLocked: Bool = false, isOnBattery: Bool = false, batteryPercent: Int = -1, isWatchedAppRunning: Bool = true) {
        self.now = now
        self.isLocked = isLocked
        self.isOnBattery = isOnBattery
        self.batteryPercent = batteryPercent
        self.isWatchedAppRunning = isWatchedAppRunning
    }
}

public struct PresenceDecision: Equatable, Sendable {
    public let state: PresenceState
    public let isBoosted: Bool
    public let nextChange: Date?

    public init(state: PresenceState, isBoosted: Bool, nextChange: Date?) {
        self.state = state
        self.isBoosted = isBoosted
        self.nextChange = nextChange
    }

    public var isActive: Bool { state == .active }
}

/// Decides whether KeepGreen should be working right now. Pure, so it is fully unit-tested.
public enum PresencePolicy {
    public static func evaluate(
        _ settings: AppSettings,
        context: PresenceContext,
        boostUntil: Date?,
        calendar: Calendar = .keepGreen
    ) -> PresenceDecision {
        // A boost beats the master switch and the schedule, but never the safety pauses below.
        let boosted = boostUntil.map { $0 > context.now } ?? false
        var nextChange: Date? = boosted ? boostUntil : nil

        if !boosted {
            if !settings.isEnabled {
                return PresenceDecision(state: .disabled, isBoosted: false, nextChange: nil)
            }

            if settings.useSchedule {
                let schedule = WorkSchedule.evaluate(settings, now: context.now, calendar: calendar)
                if schedule.state != .active {
                    return PresenceDecision(state: schedule.state, isBoosted: false, nextChange: schedule.nextChange)
                }
                nextChange = schedule.nextChange
            }
        }

        if settings.pauseWhenLocked && context.isLocked {
            return PresenceDecision(state: .locked, isBoosted: boosted, nextChange: nextChange)
        }

        if context.isOnBattery {
            if settings.pauseOnBattery {
                return PresenceDecision(state: .onBattery, isBoosted: boosted, nextChange: nextChange)
            }

            let batteryKnown = context.batteryPercent >= 0
            if settings.pauseOnLowBattery && batteryKnown && context.batteryPercent < settings.lowBatteryPercent {
                return PresenceDecision(state: .lowBattery, isBoosted: boosted, nextChange: nextChange)
            }
        }

        if settings.onlyWhenAppsRunning && !context.isWatchedAppRunning {
            return PresenceDecision(state: .waitingForApp, isBoosted: boosted, nextChange: nextChange)
        }

        return PresenceDecision(state: .active, isBoosted: boosted, nextChange: nextChange)
    }
}
