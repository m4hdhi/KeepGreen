import AppKit
import Foundation
import KeepGreenKit
import Network

/// Serves docs/remote-api.md on the local network so the phone apps can watch and control KeepGreen.
/// Off by default. One request per connection, 4 KB bodies, 10 seconds per request.
@MainActor
final class RemoteServer: ObservableObject {
    enum Status: Equatable {
        case off
        case starting
        case listening
        case waiting(String)
        case failed(String)
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var pairingCode = ""
    @Published private(set) var codeExpires = Date.distantPast
    @Published private(set) var addresses: [String] = []
    @Published private(set) var pairingLink: URL? = nil
    @Published private(set) var qrImage: NSImage? = nil
    @Published private(set) var lockedUntil: Date? = nil
    @Published private(set) var lastPairedDevice: String? = nil

    weak var engine: PresenceEngine?

    private static let codeLifetime: TimeInterval = 10 * 60
    private static let maxAttempts = 5
    private static let lockout: TimeInterval = 60
    private static let requestTimeout: TimeInterval = 10
    private static let maxConnections = 32

    private var listener: NWListener?
    private var listenerID: UUID?
    private var connections: [UUID: RemoteConnection] = [:]
    private var key = ""
    private var failedAttempts = 0
    private var housekeeping: Timer?
    private var lastAddressRefresh = Date.distantPast

    var isRunning: Bool { listener != nil }

    var port: Int { RemoteDefaults.port }

    var statusText: String {
        switch status {
        case .off: return "Off"
        case .starting: return "Starting…"
        case .listening: return "Listening on port \(port). Phones on the same network can connect."
        case .waiting(let reason): return reason
        case .failed(let reason): return reason
        }
    }

    // MARK: - Control

    /// Starts, stops or re-keys the server to match the settings.
    func update(enabled: Bool, key newKey: String?) {
        let key = newKey ?? ""
        let keyChanged = key != self.key
        self.key = key

        if enabled && !key.isEmpty {
            if listener == nil {
                start()
            } else if keyChanged {
                // Phones were just unpaired; a fresh code avoids reusing the one that may already be out there.
                newCode()
            }
        } else {
            stop()
        }
    }

    func restart() {
        let key = self.key
        stop()
        self.key = key
        if !key.isEmpty {
            start()
        }
    }

    func newCode() {
        pairingCode = RemoteKeyMaker.makePairingCode()
        codeExpires = Date().addingTimeInterval(RemoteServer.codeLifetime)
        failedAttempts = 0
        refreshPairingLink()
    }

    func refreshAddresses() {
        lastAddressRefresh = Date()
        let found = NetworkInfo.localIPv4Addresses()
        if found != addresses {
            addresses = found
            refreshPairingLink()
        }
    }

    private func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: UInt16(clamping: RemoteDefaults.port)) else { return }

        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        parameters.allowLocalEndpointReuse = true
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: port)
        } catch {
            status = .failed("Couldn't start the phone remote: \(error.localizedDescription)")
            return
        }

        let id = UUID()
        listener.stateUpdateHandler = { [weak self] state in
            guard let server = self else { return }
            Task { @MainActor in server.listenerChanged(state, id: id) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let server = self else {
                connection.cancel()
                return
            }
            Task { @MainActor in server.accept(connection) }
        }

        self.listener = listener
        listenerID = id
        status = .starting
        lockedUntil = nil
        refreshAddresses()
        newCode()
        startHousekeeping()
        listener.start(queue: .main)
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        listenerID = nil

        let open = Array(connections.values)
        connections.removeAll()
        open.forEach { $0.close() }

        housekeeping?.invalidate()
        housekeeping = nil
        key = ""
        failedAttempts = 0
        status = .off
        pairingCode = ""
        codeExpires = .distantPast
        lockedUntil = nil
        pairingLink = nil
        qrImage = nil
    }

    private func listenerChanged(_ state: NWListener.State, id: UUID) {
        guard id == listenerID else { return }

        switch state {
        case .ready:
            status = .listening
        case .waiting(let error):
            status = .waiting("Waiting for the network: \(error.localizedDescription)")
        case .failed(let error):
            status = .failed(describe(error))
            listener?.cancel()
            listener = nil
            listenerID = nil
            housekeeping?.invalidate()
            housekeeping = nil
            pairingLink = nil
            qrImage = nil
        default:
            break
        }
    }

    private func describe(_ error: NWError) -> String {
        if case .posix(let code) = error, code == .EADDRINUSE {
            return "Port \(port) is already in use, maybe by another copy of KeepGreen. Quit it and try again."
        }
        return "The phone remote stopped: \(error.localizedDescription)"
    }

    private func startHousekeeping() {
        housekeeping?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let server = self else { return }
            Task { @MainActor in server.housekeep() }
        }
        RunLoop.main.add(timer, forMode: .common)
        housekeeping = timer
    }

    private func housekeep() {
        guard isRunning else { return }

        let now = Date()
        if now >= codeExpires {
            newCode()
        }
        if let until = lockedUntil, until <= now {
            lockedUntil = nil
        }
        if now.timeIntervalSince(lastAddressRefresh) >= 10 {
            refreshAddresses()
        }
    }

    private func refreshPairingLink() {
        guard isRunning, !pairingCode.isEmpty, let host = addresses.first else {
            pairingLink = nil
            qrImage = nil
            return
        }

        let link = PairingLink(host: host, port: port, code: pairingCode, name: MacInfo.computerName).url
        if link != pairingLink {
            pairingLink = link
            qrImage = QRCode.image(for: link.absoluteString)
        }
    }

    // MARK: - Connections

    private func accept(_ nwConnection: NWConnection) {
        guard isRunning, connections.count < RemoteServer.maxConnections else {
            nwConnection.cancel()
            return
        }

        let connection = RemoteConnection(
            connection: nwConnection,
            timeout: RemoteServer.requestTimeout,
            handle: { [weak self] request in
                self?.handle(request) ?? .error(503, "KeepGreen is shutting down.")
            },
            closed: { [weak self] id in
                self?.connections[id] = nil
            })
        connections[connection.id] = connection
        connection.start()
    }

    // MARK: - Routing

    private struct EnabledBody: Decodable {
        var enabled: Bool
    }

    private struct BoostBody: Decodable {
        var minutes: Int?
        var untilEndOfWorkday: Bool?
    }

    private func handle(_ request: HTTPRequest) -> HTTPResponse {
        let now = Date()
        switch request.path {
        case "/v1/ping":
            guard request.method == "GET" else { return methodNotAllowed("GET", request.path) }
            return .json(RemotePing(
                app: "KeepGreen", api: 1, name: MacInfo.computerName, platform: MacInfo.platform, version: MacInfo.version))

        case "/v1/pair":
            guard request.method == "POST" else { return methodNotAllowed("POST", request.path) }
            return pair(request, now: now)

        case "/v1/status":
            return signed(request, method: "GET", now: now) { _, _ in nil }

        case "/v1/enabled":
            return signed(request, method: "POST", now: now) { engine, body in
                guard let payload = try? JSONDecoder().decode(EnabledBody.self, from: body) else {
                    return .error(400, #"Send {"enabled": true} or {"enabled": false}."#)
                }
                engine.setEnabled(payload.enabled)
                return nil
            }

        case "/v1/boost":
            return signed(request, method: "POST", now: now) { engine, body in
                guard let payload = try? JSONDecoder().decode(BoostBody.self, from: body) else {
                    return .error(400, #"Send {"minutes": 60} or {"untilEndOfWorkday": true}."#)
                }
                if payload.untilEndOfWorkday == true {
                    engine.boostUntilEndOfWorkday()
                } else if let minutes = payload.minutes, (1...720).contains(minutes) {
                    engine.boost(minutes: minutes)
                } else {
                    return .error(400, #"Send "minutes" from 1 to 720, or "untilEndOfWorkday": true."#)
                }
                return nil
            }

        case "/v1/boost/cancel":
            return signed(request, method: "POST", now: now) { engine, _ in
                engine.cancelBoost()
                return nil
            }

        default:
            return .error(404, "Unknown path \(request.path).")
        }
    }

    private func methodNotAllowed(_ method: String, _ path: String) -> HTTPResponse {
        .error(405, "Use \(method) for \(path).")
    }

    /// Checks the signature, runs `action` (which returns an error response or nil) and answers with the status.
    private func signed(
        _ request: HTTPRequest,
        method: String,
        now: Date,
        action: (PresenceEngine, Data) -> HTTPResponse?
    ) -> HTTPResponse {
        guard request.method == method else { return methodNotAllowed(method, request.path) }
        guard let engine = engine else { return .error(503, "KeepGreen is starting up. Try again in a moment.") }
        guard let body = String(data: request.body, encoding: .utf8) else {
            return .error(400, "The body must be UTF-8 JSON.")
        }

        guard !key.isEmpty,
              let timeText = request.headers["x-keepgreen-time"], let time = Int(timeText),
              let signature = request.headers["x-keepgreen-signature"],
              RemoteSignature.isValid(
                  signature: signature.lowercased(), key: key, method: method, path: request.path,
                  time: time, body: body, now: Int(now.timeIntervalSince1970))
        else {
            return .error(401, "Bad signature or clock. Check that the clocks on your phone and Mac are right, or pair again.")
        }

        if let failure = action(engine, request.body) {
            return failure
        }
        return .json(engine.remoteStatus())
    }

    private func pair(_ request: HTTPRequest, now: Date) -> HTTPResponse {
        if let until = lockedUntil, until > now {
            return .error(429, "Too many wrong codes. Wait a minute, then use the new code shown on your Mac.")
        }
        lockedUntil = nil

        guard let payload = try? JSONDecoder().decode(RemotePairRequest.self, from: request.body) else {
            return .error(400, #"Send {"code": "123456", "device": "My phone"}."#)
        }

        if now >= codeExpires {
            newCode()
            return .error(401, "That pairing code has expired. Use the new code shown on your Mac.")
        }

        let submitted = payload.code.filter { $0.isASCII && $0.isNumber }
        guard RemoteServer.constantTimeEquals(submitted, pairingCode) else {
            failedAttempts += 1
            if failedAttempts >= RemoteServer.maxAttempts {
                newCode()
                lockedUntil = now.addingTimeInterval(RemoteServer.lockout)
            }
            return .error(401, "Wrong pairing code.")
        }

        guard !key.isEmpty else { return .error(503, "The phone remote is turning off.") }

        newCode()
        let device = payload.device.trimmingCharacters(in: .whitespacesAndNewlines)
        lastPairedDevice = device.isEmpty ? "a phone" : String(device.prefix(60))
        return .json(RemotePairResponse(
            key: key, name: MacInfo.computerName, platform: MacInfo.platform, version: MacInfo.version))
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count, !left.isEmpty else { return false }

        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }
}

/// One phone request: read it, answer it, close. Dropped after 10 seconds no matter what.
@MainActor
final class RemoteConnection {
    let id = UUID()

    private let connection: NWConnection
    private let timeout: TimeInterval
    private let handle: (HTTPRequest) -> HTTPResponse
    private let closed: (UUID) -> Void
    private var buffer = Data()
    private var responded = false
    private var isClosed = false
    private var timeoutTask: Task<Void, Never>?

    init(
        connection: NWConnection,
        timeout: TimeInterval,
        handle: @escaping (HTTPRequest) -> HTTPResponse,
        closed: @escaping (UUID) -> Void
    ) {
        self.connection = connection
        self.timeout = timeout
        self.handle = handle
        self.closed = closed
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let owner = self else { return }
            Task { @MainActor in owner.stateChanged(state) }
        }
        connection.start(queue: .main)

        let nanoseconds = UInt64(timeout * 1_000_000_000)
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            self?.close()
        }

        receive()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        timeoutTask?.cancel()
        connection.stateUpdateHandler = nil
        connection.cancel()
        closed(id)
    }

    private func stateChanged(_ state: NWConnection.State) {
        switch state {
        case .failed, .cancelled:
            close()
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let owner = self else { return }
            let failed = error != nil
            Task { @MainActor in owner.received(data, isComplete: isComplete, failed: failed) }
        }
    }

    private func received(_ data: Data?, isComplete: Bool, failed: Bool) {
        guard !responded, !isClosed else { return }
        if let data = data {
            buffer.append(data)
        }

        switch HTTPRequest.parse(buffer) {
        case .incomplete:
            if isComplete || failed {
                close()
            } else {
                receive()
            }
        case .failure(let response):
            respond(response)
        case .request(let request):
            respond(handle(request))
        }
    }

    private func respond(_ response: HTTPResponse) {
        responded = true
        connection.send(
            content: response.serialized(),
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { [weak self] _ in
                guard let owner = self else { return }
                Task { @MainActor in owner.close() }
            })
    }
}

extension PresenceEngine {
    /// The status object of the remote API, with the same sentences the menu shows.
    func remoteStatus() -> RemoteStatus {
        RemoteStatus(
            name: MacInfo.computerName,
            platform: MacInfo.platform,
            version: MacInfo.version,
            state: decision.state.rawValue,
            isActive: decision.isActive,
            isEnabled: settings.isEnabled,
            isBoosted: decision.isBoosted,
            boostUntil: decision.isBoosted ? boostUntil.map { RemoteTime.iso8601($0) } : nil,
            headline: headline,
            detail: detail,
            idleSeconds: Int(idleSeconds),
            nudgesToday: stats.nudges,
            greenSecondsToday: Int(stats.activeSeconds))
    }
}
