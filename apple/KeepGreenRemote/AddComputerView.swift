import KeepGreenKit
import SwiftUI
import UIKit

/// Turns what people type into a host and port. Accepts "192.168.1.20", "192.168.1.20:47321",
/// "http://192.168.1.20:47321/" and names like "Studio-Mac.local".
enum AddressInput {
    static func split(_ text: String) -> (host: String, port: Int?) {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["http://", "https://"] where value.lowercased().hasPrefix(scheme) {
            value = String(value.dropFirst(scheme.count))
        }
        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }

        // [IPv6]:port
        if value.hasPrefix("["), let close = value.firstIndex(of: "]") {
            let host = String(value[value.index(after: value.startIndex)..<close])
            let rest = value[value.index(after: close)...]
            let port = rest.hasPrefix(":") ? Int(rest.dropFirst()) : nil
            return (host, port)
        }

        // host:port (a bare IPv6 address has more than one colon and is left alone)
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2, let port = Int(parts[1]) {
            return (String(parts[0]), port)
        }
        return (value, nil)
    }

    static func port(_ text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.isEmpty { return RemoteDefaults.port }
        guard let port = Int(digits), (1...65535).contains(port) else { return nil }
        return port
    }
}

/// Drives both the "Add computer" form and the "Pair with …?" sheet that a pairing link opens.
@MainActor
final class AddComputerViewModel: ObservableObject {
    enum ConnectionCheck: Equatable {
        case idle
        case checking
        case found(String)
        case failed(String)
    }

    @Published var address: String {
        didSet { fillFromPastedLink() }
    }
    @Published var port: String
    @Published var code: String
    @Published private(set) var check: ConnectionCheck = .idle
    @Published private(set) var isPairing = false
    @Published private(set) var errorMessage: String? = nil

    private let store: DesktopStore

    init(store: DesktopStore, host: String = "", port: Int = RemoteDefaults.port, code: String = "") {
        self.store = store
        _address = Published(initialValue: host)
        _port = Published(initialValue: String(port))
        _code = Published(initialValue: code)
    }

    /// The six digits, ignoring spaces or anything else typed along with them.
    var cleanCode: String {
        String(code.filter { $0.isASCII && $0.isNumber }.prefix(6))
    }

    var target: (host: String, port: Int)? {
        let parts = AddressInput.split(address)
        guard !parts.host.isEmpty, let typedPort = AddressInput.port(port) else { return nil }
        // A port typed into the address box wins over the separate field only if that field was left at the default.
        let finalPort = (parts.port != nil && typedPort == RemoteDefaults.port) ? parts.port! : typedPort
        return (parts.host, finalPort)
    }

    var canPair: Bool {
        target != nil && cleanCode.count == 6 && !isPairing
    }

    func testConnection() async {
        guard let target = target else {
            check = .failed("Type the address shown on your computer first.")
            return
        }
        check = .checking
        do {
            let ping = try await RemoteClient.ping(host: target.host, port: target.port)
            check = .found("Found \(ping.name), KeepGreen \(ping.version) on \(Format.platformName(ping.platform)).")
            Haptics.success()
        } catch is CancellationError {
            check = .idle
        } catch {
            check = .failed(error.localizedDescription)
            Haptics.failure()
        }
    }

    /// Pairs and saves the computer. Returns it on success; on failure `errorMessage` says why.
    func pair() async -> RemoteDesktop? {
        guard let target = target else {
            errorMessage = "Type the address shown on your computer."
            return nil
        }
        guard cleanCode.count == 6 else {
            errorMessage = "The pairing code has 6 digits."
            return nil
        }

        isPairing = true
        errorMessage = nil
        Haptics.tap()
        defer { isPairing = false }

        do {
            let desktop = try await RemoteClient.pair(
                host: target.host,
                port: target.port,
                code: cleanCode,
                device: UIDevice.current.name
            )
            let saved = store.savePaired(desktop)
            Haptics.success()
            return saved
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            Haptics.failure()
            return nil
        }
    }

    /// Someone pasted a whole pairing link into the address box: fill in everything from it.
    private func fillFromPastedLink() {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.lowercased().hasPrefix("keepgreen:"),
              let url = URL(string: text),
              let link = PairingLink(url: url)
        else { return }
        address = link.host
        port = String(link.port)
        code = link.code
    }
}

// MARK: - Add computer

/// The form for typing a computer's address and pairing code (the Windows way, or any time the camera isn't handy).
struct AddComputerView: View {
    @StateObject private var model: AddComputerViewModel
    @Environment(\.dismiss) private var dismiss
    private let title: String
    private let onPaired: (RemoteDesktop) -> Void

    init(
        store: DesktopStore,
        title: String = "Add computer",
        host: String = "",
        port: Int = RemoteDefaults.port,
        onPaired: @escaping (RemoteDesktop) -> Void
    ) {
        _model = StateObject(wrappedValue: AddComputerViewModel(store: store, host: host, port: port))
        self.title = title
        self.onPaired = onPaired
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("192.168.1.20", text: $model.address)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                    HStack {
                        Text("Port")
                            .foregroundColor(.secondary)
                        TextField(String(RemoteDefaults.port), text: $model.port)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Address")
                } footer: {
                    Text("On your computer, open KeepGreen → Settings → Phone remote and turn it on. The address is shown there.")
                }

                Section {
                    TextField("123456", text: $model.code)
                        .keyboardType(.numberPad)
                        .font(.title2.monospacedDigit())
                } header: {
                    Text("Pairing code")
                } footer: {
                    Text("The 6-digit code next to the address. It changes every 10 minutes.")
                }

                Section {
                    Button {
                        Task { await model.testConnection() }
                    } label: {
                        HStack {
                            Label("Test connection", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            if model.check == .checking {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(model.check == .checking)

                    checkResult
                } footer: {
                    Text("Your iPhone and computer need to be on the same Wi-Fi. If iPhone asks to find devices on your local network, tap Allow.")
                }

                if let message = model.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(Palette.amber)
                    }
                }

                Section {
                    Button {
                        Task { await pair() }
                    } label: {
                        HStack {
                            Spacer()
                            if model.isPairing {
                                ProgressView()
                            } else {
                                Text("Pair").fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!model.canPair)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pair") {
                        Task { await pair() }
                    }
                    .disabled(!model.canPair)
                }
            }
        }
    }

    @ViewBuilder
    private var checkResult: some View {
        switch model.check {
        case .idle, .checking:
            EmptyView()
        case .found(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundColor(Palette.green)
        case .failed(let message):
            Label(message, systemImage: "wifi.exclamationmark")
                .foregroundColor(Palette.amber)
        }
    }

    private func pair() async {
        if let desktop = await model.pair() {
            onPaired(desktop)
            dismiss()
        }
    }
}

// MARK: - Pair from a link

/// Shown when the iPhone Camera opens a keepgreen://pair link from the QR code on a Mac.
struct PairConfirmView: View {
    let link: PairingLink
    @StateObject private var model: AddComputerViewModel
    @Environment(\.dismiss) private var dismiss
    private let onPaired: (RemoteDesktop) -> Void

    init(link: PairingLink, store: DesktopStore, onPaired: @escaping (RemoteDesktop) -> Void) {
        self.link = link
        self.onPaired = onPaired
        _model = StateObject(wrappedValue: AddComputerViewModel(store: store, host: link.host, port: link.port, code: link.code))
    }

    private var displayName: String {
        link.name ?? link.host
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer(minLength: 0)

                StatusOrb(color: Palette.green, symbol: "link", pulses: !model.isPairing, size: 64)

                Text("Pair with \(displayName)?")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("This iPhone will show its status, and can turn KeepGreen on or off and start boosts. Address: \(link.host):\(String(link.port)).")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                if let message = model.errorMessage {
                    NoticeBanner(systemImage: "exclamationmark.triangle.fill", message: message)
                }

                Spacer(minLength: 0)

                Button {
                    Task {
                        if let desktop = await model.pair() {
                            onPaired(desktop)
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if model.isPairing {
                            ProgressView().tint(.white)
                        } else {
                            Text("Pair").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isPairing)

                Button("Not now") { dismiss() }
                    .padding(.bottom, 4)
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
