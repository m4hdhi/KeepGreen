import KeepGreenKit
import SwiftUI

struct BehaviorSettingsView: View {
    @ObservedObject var engine: PresenceEngine

    @State private var appsDraft = ""
    @FocusState private var appsFocused: Bool

    init(engine: PresenceEngine) {
        self.engine = engine
    }

    var body: some View {
        Form {
            Section {
                Text("Teams shows you as Away after about 5 minutes without input. KeepGreen steps in well before that, and only when you're idle, so it never gets in your way.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let warning = engine.warning {
                    WarningBox(message: warning) {
                        if engine.settings.style == .invisibleMouse && !engine.isAccessibilityTrusted {
                            Button("Allow Accessibility…") { engine.requestAccessibility() }
                        }
                    }
                }
            }

            Section {
                HStack {
                    RowLabel(
                        title: "Nudge after I've been idle for",
                        subtitle: "Shorter is safer; anything up to 4 minutes keeps Teams green.")
                    Spacer()
                    Text("\(engine.settings.intervalSeconds) s")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                }
                Slider(
                    value: intervalBinding,
                    in: Double(AppSettings.minIntervalSeconds)...Double(AppSettings.maxIntervalSeconds),
                    step: 5)
                Toggle(isOn: $engine.settings.randomizeInterval) {
                    Text(verbatim: "Vary the timing slightly (±20%) so it's never robotic")
                }
            }

            Section {
                ForEach(NudgeStyle.allCases) { style in
                    NudgeStyleRow(style: style, isSelected: engine.settings.style == style) {
                        engine.settings.style = style
                    }
                }

                if engine.settings.style == .invisibleMouse {
                    accessibilityRow
                }
            } header: {
                Text("How to nudge")
            } footer: {
                Text("Every style resets the macOS idle timer that Teams, Slack and Zoom watch. Use Run test in the menu to check yours.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $engine.settings.pauseWhenLocked) {
                    RowLabel(
                        title: "Pause when the Mac is locked",
                        subtitle: "Locking up means you've stepped away, so your status should show it.")
                }
                Toggle(isOn: $engine.settings.pauseOnBattery) {
                    RowLabel(title: "Pause on battery power", subtitle: "Only work while the laptop is plugged in.")
                }
                HStack {
                    Toggle(isOn: $engine.settings.pauseOnLowBattery) {
                        RowLabel(title: "Pause when the battery is low", subtitle: "Lets an unplugged laptop sleep before it runs flat.")
                    }
                    Spacer()
                    Text("Below").foregroundStyle(.secondary)
                    Picker("Battery level", selection: $engine.settings.lowBatteryPercent) {
                        ForEach(batteryChoices, id: \.self) { percent in
                            Text(verbatim: "\(percent) %").tag(percent)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 84)
                    .disabled(!engine.settings.pauseOnLowBattery)
                }

                Toggle(isOn: $engine.settings.onlyWhenAppsRunning) {
                    RowLabel(
                        title: "Only while my chat apps are running",
                        subtitle: "App names as the Dock shows them, separated by commas.")
                }
                TextField("Apps", text: $appsDraft, prompt: Text(AppSettings.defaultWatchedApps))
                    .labelsHidden()
                    .focused($appsFocused)
                    .onSubmit { commitApps() }
                    .disabled(!engine.settings.onlyWhenAppsRunning)
            } header: {
                Text("Smart pauses")
            }
        }
        .formStyle(.grouped)
        .onAppear { appsDraft = engine.settings.watchedApps }
        .onDisappear { commitApps() }
        .onChange(of: appsFocused) { focused in
            if !focused {
                commitApps()
            }
        }
    }

    private var intervalBinding: Binding<Double> {
        Binding(
            get: { Double(engine.settings.intervalSeconds) },
            set: { newValue in
                let seconds = Int(newValue.rounded())
                if seconds != engine.settings.intervalSeconds {
                    engine.settings.intervalSeconds = seconds
                }
            })
    }

    private var batteryChoices: [Int] {
        let current = engine.settings.lowBatteryPercent
        return AppSettings.batteryChoices.contains(current)
            ? AppSettings.batteryChoices
            : (AppSettings.batteryChoices + [current]).sorted()
    }

    @ViewBuilder
    private var accessibilityRow: some View {
        if engine.isAccessibilityTrusted {
            Label("Accessibility access is allowed.", systemImage: "checkmark.shield")
                .foregroundStyle(Color.keepGreen)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("macOS only accepts mouse events from apps you allow under Privacy & Security → Accessibility. KeepGreen uses this access for one thing: a mouse event at the spot where your cursor already is. It never reads what you type or click.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Allow Accessibility…") { engine.requestAccessibility() }
                    Button("Open Privacy & Security") { MacSystem.openAccessibilitySettings() }
                }
            }
        }
    }

    private func commitApps() {
        if appsDraft != engine.settings.watchedApps {
            engine.settings.watchedApps = appsDraft
        }
    }
}

private struct NudgeStyleRow: View {
    let style: NudgeStyle
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.keepGreen : Color.secondary)
                    .font(.body)
                RowLabel(title: style.title, subtitle: style.explanation)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
