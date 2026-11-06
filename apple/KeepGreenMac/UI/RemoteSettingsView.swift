import AppKit
import KeepGreenKit
import SwiftUI

struct RemoteSettingsView: View {
    @ObservedObject var engine: PresenceEngine
    @ObservedObject var remote: RemoteServer

    @State private var confirmUnpair = false

    init(engine: PresenceEngine, remote: RemoteServer) {
        self.engine = engine
        self.remote = remote
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { engine.settings.remoteEnabled }, set: { engine.setRemoteEnabled($0) })) {
                    RowLabel(
                        title: "Let my phone see and control KeepGreen",
                        subtitle: "Off by default. Your phone and this Mac need to be on the same network.")
                }

                if engine.settings.remoteEnabled {
                    statusLine
                }
            } footer: {
                Text("Paired phones can see the status and today's numbers, flip the switch and start or cancel boosts. Nothing leaves your local network.")
                    .foregroundStyle(.secondary)
            }

            if engine.settings.remoteEnabled && remote.isRunning {
                Section("Pair a phone") {
                    pairing
                }

                Section {
                    if let device = remote.lastPairedDevice {
                        Label("Paired with \(device).", systemImage: "checkmark.circle")
                            .foregroundStyle(Color.keepGreen)
                    }
                    HStack {
                        RowLabel(
                            title: "Unpair all phones",
                            subtitle: "Makes a new key. Every paired phone has to pair again.")
                        Spacer()
                        Button("Unpair all phones", role: .destructive) { confirmUnpair = true }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { remote.refreshAddresses() }
        .confirmationDialog("Unpair all phones?", isPresented: $confirmUnpair) {
            Button("Unpair all phones", role: .destructive) { engine.unpairAllPhones() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every phone paired with this Mac is signed out and has to pair again with a new code.")
        }
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(remote.statusText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if case .failed = remote.status {
                Button("Try again") { remote.restart() }
            }
        }
    }

    private var statusColor: Color {
        switch remote.status {
        case .listening: return .keepGreen
        case .off: return .statusGray
        default: return .statusAmber
        }
    }

    private var pairing: some View {
        HStack(alignment: .top, spacing: 24) {
            if let image = remote.qrImage {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 168, height: 168)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
                    .accessibilityLabel("QR code for pairing")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Open KeepGreen on your phone and scan this code, or type in the address and the pairing code.")
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("PAIRING CODE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(spacedCode)
                        .font(.system(size: 36, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        Text(timeLeftText(at: context.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Button("New code") { remote.newCode() }

                VStack(alignment: .leading, spacing: 2) {
                    Text("ADDRESS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if remote.addresses.isEmpty {
                        Text("No network found. Connect this Mac to Wi-Fi or Ethernet.")
                            .foregroundStyle(Color.statusAmber)
                    } else {
                        ForEach(remote.addresses, id: \.self) { address in
                            Text(verbatim: "\(address):\(remote.port)")
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// "123 456", easier to read out and type.
    private var spacedCode: String {
        let code = remote.pairingCode
        guard code.count == 6 else { return code }
        return String(code.prefix(3)) + " " + String(code.suffix(3))
    }

    private func timeLeftText(at now: Date) -> String {
        if let until = remote.lockedUntil, until > now {
            return "Too many wrong codes. Pairing is paused for \(Int(until.timeIntervalSince(now).rounded(.up))) s."
        }
        let left = max(0, Int(remote.codeExpires.timeIntervalSince(now).rounded(.up)))
        let seconds = left % 60
        return "Valid for \(left / 60):\(seconds < 10 ? "0" : "")\(seconds), then a new one appears."
    }
}
