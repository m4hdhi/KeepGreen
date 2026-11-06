import KeepGreenKit
import SwiftUI

extension Color {
    /// KeepGreen's accent and the "Active" status colour, #22C55E.
    static let keepGreen = Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)

    /// "Disabled", #94A3B8.
    static let statusGray = Color(red: 0x94 / 255, green: 0xA3 / 255, blue: 0xB8 / 255)

    /// Every paused or waiting state, #F59E0B.
    static let statusAmber = Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
}

extension PresenceState {
    var color: Color {
        switch self {
        case .active: return .keepGreen
        case .disabled: return .statusGray
        default: return .statusAmber
        }
    }
}

extension NudgeStyle {
    var title: String {
        switch self {
        case .declareActivity: return "Declare activity (recommended)"
        case .invisibleMouse: return "Invisible mouse"
        case .awakeOnly: return "Awake only"
        }
    }

    var explanation: String {
        switch self {
        case .declareActivity:
            return "Tells macOS that you're active, the way a key press would. Needs no permissions."
        case .invisibleMouse:
            return "A zero-distance mouse signal. Your cursor never moves. Needs Accessibility access."
        case .awakeOnly:
            return "No input at all. Keeps the Mac and screen awake, but your status can still go Away."
        }
    }
}

/// A title with a smaller grey line under it, used for most settings rows.
struct RowLabel: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The coloured status dot, with a soft halo while KeepGreen is active.
struct StatusDot: View {
    let state: PresenceState
    var size: CGFloat = 12

    var body: some View {
        ZStack {
            if state == .active {
                Circle()
                    .fill(state.color.opacity(0.3))
                    .frame(width: size * 1.8, height: size * 1.8)
            }
            Circle()
                .fill(state.color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 1.8, height: size * 1.8)
        .accessibilityHidden(true)
    }
}

/// An amber "Heads up" box for nudge warnings.
struct WarningBox<Actions: View>: View {
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.statusAmber)
            }
            .font(.callout)

            HStack(spacing: 8) {
                actions()
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.statusAmber.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.statusAmber.opacity(0.4)))
    }
}

/// A 24-hour time picker in 15-minute steps.
struct QuarterHourPicker: View {
    @Binding var selection: TimeOfDay

    var body: some View {
        Picker("Time", selection: $selection) {
            ForEach(choices, id: \.self) { time in
                Text(time.description).tag(time)
            }
        }
        .labelsHidden()
        .frame(width: 92)
    }

    private var choices: [TimeOfDay] {
        // A hand-edited file may hold a time between the quarters; keep it selectable.
        TimeOfDay.quarterHours.contains(selection)
            ? TimeOfDay.quarterHours
            : (TimeOfDay.quarterHours + [selection]).sorted()
    }
}

extension LocalDate {
    /// "Thu, 24 Dec 2026" in the user's language.
    var displayText: String {
        date(at: TimeOfDay(12)).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }
}
