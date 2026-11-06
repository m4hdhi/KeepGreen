import KeepGreenKit
import SwiftUI

struct ScheduleSettingsView: View {
    @ObservedObject var engine: PresenceEngine
    @State private var newDayOff = Date()

    init(engine: PresenceEngine) {
        self.engine = engine
    }

    var body: some View {
        Form {
            Section {
                Text(engine.scheduleSummary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: $engine.settings.useSchedule) {
                    RowLabel(
                        title: "Follow my work schedule",
                        subtitle: "Turns on during your work hours and off outside them, all by itself.")
                }
            }

            Section {
                HStack(spacing: 6) {
                    Text("Presets").foregroundStyle(.secondary)
                    Spacer()
                    ForEach(SchedulePreset.allCases) { preset in
                        Button(preset.title) { engine.applyPreset(preset) }
                    }
                }
                .controlSize(.small)

                ForEach($engine.settings.week) { $day in
                    DayRow(day: $day)
                }
            } header: {
                Text("Working days and hours")
            } footer: {
                Text("An end time before the start time runs past midnight, for night shifts.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $engine.settings.lunchBreakEnabled) {
                    RowLabel(
                        title: "Lunch break",
                        subtitle: "Let your status go Away while you eat. Applies on every working day.")
                }
                HStack {
                    Text("From")
                    QuarterHourPicker(selection: $engine.settings.lunchStart)
                    Text("to").foregroundStyle(.secondary)
                    QuarterHourPicker(selection: $engine.settings.lunchEnd)
                    Spacer()
                }
                .disabled(!engine.settings.lunchBreakEnabled)
                if engine.settings.lunchBreakEnabled && engine.settings.lunchEnd <= engine.settings.lunchStart {
                    Text("The lunch break needs to end after it starts.")
                        .font(.caption)
                        .foregroundStyle(Color.statusAmber)
                }
            }

            Section {
                HStack {
                    DatePicker("Add a day off", selection: $newDayOff, in: Calendar.keepGreen.startOfDay(for: Date())..., displayedComponents: .date)
                    Button("Add day off") {
                        engine.addDayOff(LocalDate(newDayOff))
                    }
                    .buttonStyle(.borderedProminent)
                }

                if engine.settings.daysOff.isEmpty {
                    Text("No days off planned.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(engine.settings.daysOff, id: \.self) { day in
                        HStack {
                            Text(day.displayText)
                            Spacer()
                            Button {
                                engine.removeDayOff(day)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove")
                            .accessibilityLabel("Remove \(day.displayText)")
                        }
                    }
                }
            } header: {
                Text("Days off")
            } footer: {
                Text("Holidays and vacation days stay off, even on a working day. Past days clean themselves up.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DayRow: View {
    @Binding var day: DaySchedule

    var body: some View {
        HStack(spacing: 10) {
            Toggle(day.dayName, isOn: $day.enabled)
                .toggleStyle(.checkbox)
                .frame(width: 120, alignment: .leading)

            QuarterHourPicker(selection: $day.start)
            Text("to").foregroundStyle(.secondary)
            QuarterHourPicker(selection: $day.end)

            Spacer()

            Text(day.lengthText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .opacity(day.enabled ? 1 : 0.55)
    }
}
