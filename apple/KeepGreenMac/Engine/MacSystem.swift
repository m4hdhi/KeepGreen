import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.ps
import IOKit.pwr_mgt
import KeepGreenKit

/// Read-only questions KeepGreen asks macOS once per tick.
enum MacSystem {
    struct PowerStatus: Equatable {
        var isOnBattery: Bool

        /// 0 to 100, or -1 when there is no internal battery.
        var batteryPercent: Int
    }

    /// Seconds since the last keyboard, mouse or trackpad input from anyone (or anything) on this Mac.
    static func idleSeconds() -> TimeInterval {
        // kCGAnyInputEventType is ~0; Swift has no named case for it.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        let seconds = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
        return seconds.isFinite ? max(0, seconds) : 0
    }

    static func powerStatus() -> PowerStatus {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerStatus(isOnBattery: false, batteryPercent: -1)
        }

        var onBattery = false
        if let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
            onBattery = (providing as String) == kIOPSBatteryPowerValue
        }

        var percent = -1
        if let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
                else { continue }

                if let current = description[kIOPSCurrentCapacityKey] as? Int,
                   let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
                    percent = min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded())))
                }
                break
            }
        }

        return PowerStatus(isOnBattery: onBattery, batteryPercent: percent)
    }

    /// True when any of `names` matches a running app's name or bundle name, ignoring case.
    static func isAnyAppRunning(_ names: [String]) -> Bool {
        let wanted = Set(names.map { $0.lowercased() })
        guard !wanted.isEmpty else { return false }

        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName?.lowercased(), wanted.contains(name) {
                return true
            }
            if let bundleName = app.bundleURL?.deletingPathExtension().lastPathComponent.lowercased(), wanted.contains(bundleName) {
                return true
            }
        }
        return false
    }

    /// Whether KeepGreen may post input events (needed for the Invisible mouse style).
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that sends people to Privacy & Security → Accessibility.
    @discardableResult
    static func requestAccessibility() -> Bool {
        // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Holds macOS awake (display included) while KeepGreen is active.
@MainActor
final class AwakeAssertion {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isHeld = false

    func hold() {
        guard !isHeld else { return }

        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "KeepGreen is keeping your status available" as CFString,
            &id)
        if result == kIOReturnSuccess {
            assertionID = id
            isHeld = true
        }
    }

    func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isHeld = false
    }
}

enum NudgeOutcome: Equatable {
    case sent
    case needsAccessibility
    case refused
}

/// Sends the tiny signal that tells macOS someone is at the keyboard.
@MainActor
final class Nudger {
    private var activityID: IOPMAssertionID = 0

    func send(_ style: NudgeStyle) -> NudgeOutcome {
        switch style {
        case .declareActivity:
            return declareActivity() ? .sent : .refused
        case .invisibleMouse:
            return moveMouseInPlace()
        case .awakeOnly:
            return .sent
        }
    }

    /// Lets the display sleep again after a declared activity. Safe to call repeatedly.
    func releaseActivity() {
        guard activityID != 0 else { return }
        IOPMAssertionRelease(activityID)
        activityID = 0
    }

    private func declareActivity() -> Bool {
        // Passing the previous ID renews the same assertion instead of piling up new ones.
        var id = activityID
        var result = IOPMAssertionDeclareUserActivity("KeepGreen" as CFString, kIOPMUserActiveLocal, &id)
        if result != kIOReturnSuccess && activityID != 0 {
            id = 0
            result = IOPMAssertionDeclareUserActivity("KeepGreen" as CFString, kIOPMUserActiveLocal, &id)
        }
        guard result == kIOReturnSuccess else { return false }
        activityID = id
        return true
    }

    private func moveMouseInPlace() -> NudgeOutcome {
        guard MacSystem.isAccessibilityTrusted() else { return .needsAccessibility }

        // A mouse-moved event to where the cursor already is: the idle timer resets, the cursor stays put.
        let location = CGEvent(source: nil)?.location ?? .zero
        guard let event = CGEvent(
            mouseEventSource: CGEventSource(stateID: .hidSystemState),
            mouseType: .mouseMoved,
            mouseCursorPosition: location,
            mouseButton: .left)
        else { return .refused }

        event.post(tap: .cghidEventTap)
        return .sent
    }
}
