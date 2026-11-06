import SwiftUI
import UIKit

/// The KeepGreen status colours, the same on every platform.
enum Palette {
    /// #22C55E: Active, and the app's tint.
    static let green = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
    /// #94A3B8: Disabled, and computers we can't reach.
    static let grey = Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
    /// #F59E0B: every other state (schedule, break, locked, battery, waiting for apps).
    static let amber = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)

    /// Active is green, Disabled is grey, everything else (including states this app doesn't know yet) is amber.
    static func color(forState state: String) -> Color {
        switch state {
        case "Active": return green
        case "Disabled": return grey
        default: return amber
        }
    }
}

/// Short, friendly text, matching the desktop dashboard.
enum Format {
    /// "42 s", "5 min" or "6 h 12 min", like the desktop app.
    static func duration(seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }

    /// A clock time in the phone's own style, e.g. "14:30" or "2:30 PM".
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Reads `boostUntil`. Accepts the spec's "2026-11-05T14:30:00+04:00" and .NET's seven fractional digits.
    static func date(fromISO8601 text: String?) -> Date? {
        guard let text = text, !text.isEmpty else { return nil }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }

        if let range = text.range(of: #"\.\d+"#, options: .regularExpression) {
            var trimmed = text
            trimmed.removeSubrange(range)
            return plain.date(from: trimmed)
        }
        return nil
    }

    static func platformName(_ platform: String) -> String {
        switch platform.lowercased() {
        case "windows": return "Windows"
        case "macos": return "Mac"
        default: return platform.isEmpty ? "Computer" : platform
        }
    }

    static func platformSymbol(_ platform: String) -> String {
        switch platform.lowercased() {
        case "windows": return "pc"
        case "macos": return "laptopcomputer"
        default: return "desktopcomputer"
        }
    }
}

/// A light tap when something starts, and a success or error buzz when it ends.
@MainActor
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func failure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

extension View {
    /// The rounded card every section of the app sits on. Works in light and dark mode.
    func keepGreenCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }
}

/// The big round status light, with a slow pulse while the computer is staying green.
struct StatusOrb: View {
    let color: Color
    /// SF Symbol in the middle; `nil` shows a spinner.
    let symbol: String?
    let pulses: Bool
    var size: CGFloat = 88

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if pulses && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let phase: Double = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
                    Circle()
                        .fill(color.opacity(0.35))
                        .scaleEffect(CGFloat(0.55 + 0.45 * phase))
                        .opacity(1 - phase)
                }
            } else if pulses {
                Circle()
                    .fill(color.opacity(0.15))
            }

            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.4), radius: 12, x: 0, y: 4)

            if let symbol = symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundColor(.white)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(width: size * 1.7, height: size * 1.7)
        .animation(.easeInOut(duration: 0.3), value: color)
        .accessibilityHidden(true)
    }
}

/// A short message on an amber background, with an optional action.
struct NoticeBanner: View {
    let systemImage: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundColor(Palette.amber)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle = actionTitle, let action = action {
                    Button(actionTitle, action: action)
                        .font(.subheadline.weight(.semibold))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.amber.opacity(0.15))
        )
        .accessibilityElement(children: .combine)
    }
}
