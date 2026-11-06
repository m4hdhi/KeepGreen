import AppKit
import KeepGreenKit
import SwiftUI

/// The panel under the menu bar icon: status, switch, quick boosts, today's numbers and a self-test.
struct MenuBarView: View {
    @ObservedObject var engine: PresenceEngine
    let openSettings: (SettingsPage?) -> Void

    @State private var testResult: SelfTestResult? = nil

    init(engine: PresenceEngine, openSettings: @escaping (SettingsPage?) -> Void) {
        self.engine = engine
        self.openSettings = openSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let warning = engine.warning {
                WarningBox(message: warning) {
                    if engine.settings.style == .invisibleMouse && !engine.isAccessibilityTrusted {
                        Button("Allow Accessibility…") { engine.requestAccessibility() }
                    }
                    Button("Open Behavior") { openSettings(.behavior) }
                }
            }

            Divider()
            boosts
            Divider()
            statsGrid
            Divider()
            selfTest
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .tint(.keepGreen)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusDot(state: engine.state, size: 12)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(engine.headline)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(engine.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if engine.hasBoost {
                    Label(engine.boostText, systemImage: "bolt.fill")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.keepGreen.opacity(0.15)))
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 8)

            Toggle("KeepGreen", isOn: $engine.settings.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help(engine.settings.isEnabled ? "Turn KeepGreen off" : "Turn KeepGreen on")
        }
    }

    private var boosts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Quick boost", systemImage: "bolt")
                .font(.subheadline.weight(.semibold))
            Text("Stay green for a while, even outside your schedule or with the switch off.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                boostButton("15 min", minutes: 15)
                boostButton("30 min", minutes: 30)
                boostButton("1 hour", minutes: 60)
                boostButton("2 hours", minutes: 120)
            }

            HStack(spacing: 6) {
                Button {
                    engine.boostUntilEndOfWorkday()
                } label: {
                    Text("Until the end of my workday").frame(maxWidth: .infinity)
                }
                if engine.hasBoost {
                    Button("Cancel boost") { engine.cancelBoost() }
                }
            }
        }
        .controlSize(.small)
    }

    private func boostButton(_ title: String, minutes: Int) -> some View {
        Button {
            engine.boost(minutes: minutes)
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
    }

    private var statsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                StatTile(title: "IDLE RIGHT NOW", value: engine.idleText, caption: "macOS idle timer")
                StatTile(title: "NEXT NUDGE", value: engine.nextNudgeText, caption: "Only if you stay idle")
            }
            GridRow {
                StatTile(title: "NUDGES TODAY", value: engine.nudgesTodayText, caption: engine.lastNudgeText)
                StatTile(title: "GREEN TODAY", value: engine.greenTimeText, caption: "Time KeepGreen was active")
            }
        }
    }

    private var selfTest: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                RowLabel(title: "Test it", subtitle: "Sends one nudge and checks that macOS really registered activity.")
                Spacer(minLength: 8)
                Button("Run test") {
                    testResult = nil
                    Task {
                        testResult = await engine.runSelfTest()
                    }
                }
                .disabled(engine.isSelfTestRunning)
                .controlSize(.small)
            }

            if engine.isSelfTestRunning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Keep your hands off the mouse and keyboard for 3 seconds…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let result = testResult {
                Label {
                    Text(result.message)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(result.ok ? Color.keepGreen : Color.red)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { openSettings(nil) }
                .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Button("Quit KeepGreen") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .controlSize(.small)
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
