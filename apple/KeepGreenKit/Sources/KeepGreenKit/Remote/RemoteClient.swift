import Foundation

/// What can go wrong when talking to a desktop, in words people can act on.
public enum RemoteClientError: Error, LocalizedError {
    /// The address can't be turned into a URL.
    case invalidAddress
    /// `401` from `/v1/pair`, or a code that isn't six digits.
    case wrongCode
    /// `429`: five wrong codes in a row.
    case lockedOut
    /// `401` on a signed request: the key changed (Unpair all phones) or the clocks are too far apart.
    case unauthorized
    /// No answer: wrong address, different network, remote turned off, or a timeout.
    case unreachable
    /// An answer that isn't what the protocol says.
    case badResponse
    /// Any other error answer, with the desktop's own message.
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "That address doesn't look right. Type it as shown on your computer, like 192.168.1.20."
        case .wrongCode:
            return "Wrong or expired pairing code."
        case .lockedOut:
            return "Too many tries. Wait a minute and get a new code."
        case .unauthorized:
            return "Your computer didn't accept this phone. Pair it again, and check both clocks are set automatically."
        case .unreachable:
            return "Couldn't reach the computer. Check it's on the same Wi-Fi and Phone remote is on."
        case .badResponse:
            return "Your computer sent an answer KeepGreen didn't understand. Make sure both apps are up to date."
        case .server(let message):
            return message.isEmpty ? RemoteClientError.badResponse.errorDescription : message
        }
    }
}

/// Talks to one paired desktop. Every call is a single short HTTP request; nothing is kept open.
public final class RemoteClient {
    /// The desktop this client signs requests for.
    public let desktop: RemoteDesktop
    private let session: URLSession

    /// Seconds to wait for the desktop. It's on the same network, so anything slower means it's gone.
    static let requestTimeout: TimeInterval = 5

    public init(desktop: RemoteDesktop, session: URLSession = .shared) {
        self.desktop = desktop
        self.session = session
    }

    // MARK: Signed endpoints

    public func status() async throws -> RemoteStatus {
        try await signed(method: "GET", path: "/v1/status", body: "")
    }

    public func setEnabled(_ enabled: Bool) async throws -> RemoteStatus {
        try await signed(method: "POST", path: "/v1/enabled", body: RemoteClient.json(EnabledBody(enabled: enabled)))
    }

    /// Starts a boost. Minutes are clamped to what the desktop accepts, 1 to 720.
    public func boost(minutes: Int) async throws -> RemoteStatus {
        let clamped = min(max(minutes, 1), 720)
        return try await signed(method: "POST", path: "/v1/boost", body: RemoteClient.json(BoostMinutesBody(minutes: clamped)))
    }

    public func boostUntilEndOfWorkday() async throws -> RemoteStatus {
        try await signed(method: "POST", path: "/v1/boost", body: RemoteClient.json(BoostEndOfWorkdayBody(untilEndOfWorkday: true)))
    }

    public func cancelBoost() async throws -> RemoteStatus {
        try await signed(method: "POST", path: "/v1/boost/cancel", body: "{}")
    }

    // MARK: Unsigned endpoints

    /// The unsigned health check. Use it to test an address before pairing.
    public static func ping(host: String, port: Int, session: URLSession = .shared) async throws -> RemotePing {
        let url = try makeURL(host: host, port: port, path: "/v1/ping")
        let request = makeRequest(url: url, method: "GET", body: "")
        let ping: RemotePing = try await send(request, session: session, unauthorizedError: .unauthorized)
        guard ping.app.lowercased() == "keepgreen" else { throw RemoteClientError.badResponse }
        return ping
    }

    /// Trades a six-digit pairing code for the desktop's key. Store the result; it's needed for every later call.
    public static func pair(
        host: String,
        port: Int,
        code: String,
        device: String,
        session: URLSession = .shared
    ) async throws -> RemoteDesktop {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCode = code.filter { !$0.isWhitespace }
        guard cleanCode.utf8.count == 6,
              cleanCode.utf8.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") })
        else { throw RemoteClientError.wrongCode }

        let url = try makeURL(host: cleanHost, port: port, path: "/v1/pair")
        let body = json(RemotePairRequest(code: cleanCode, device: String(device.prefix(64))))
        let request = makeRequest(url: url, method: "POST", body: body)
        let answer: RemotePairResponse = try await send(request, session: session, unauthorizedError: .wrongCode)
        guard !answer.key.isEmpty else { throw RemoteClientError.badResponse }

        return RemoteDesktop(
            host: cleanHost,
            port: port,
            key: answer.key,
            name: answer.name.isEmpty ? cleanHost : answer.name,
            platform: answer.platform
        )
    }

    // MARK: Plumbing

    private struct EnabledBody: Encodable {
        let enabled: Bool
    }

    private struct BoostMinutesBody: Encodable {
        let minutes: Int
    }

    private struct BoostEndOfWorkdayBody: Encodable {
        let untilEndOfWorkday: Bool
    }

    private func signed<T: Decodable>(method: String, path: String, body: String) async throws -> T {
        let url = try RemoteClient.makeURL(host: desktop.host, port: desktop.port, path: path)
        let time = Int(Date().timeIntervalSince1970)
        // Sign the very string that goes on the wire.
        let signature = RemoteSignature.sign(key: desktop.key, method: method, path: path, time: time, body: body)
        var request = RemoteClient.makeRequest(url: url, method: method, body: body)
        request.setValue(String(time), forHTTPHeaderField: "X-KeepGreen-Time")
        request.setValue(signature, forHTTPHeaderField: "X-KeepGreen-Signature")
        return try await RemoteClient.send(request, session: session, unauthorizedError: .unauthorized)
    }

    /// Encodes one of the tiny request bodies. They can't fail to encode.
    private static func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func makeURL(host: String, port: Int, path: String) throws -> URL {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:[]")
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              (1...65535).contains(port)
        else { throw RemoteClientError.invalidAddress }

        // A bare IPv6 address needs brackets in a URL.
        let hostPart = trimmed.contains(":") && !trimmed.hasPrefix("[") ? "[\(trimmed)]" : trimmed
        guard let url = URL(string: "http://\(hostPart):\(port)\(path)") else { throw RemoteClientError.invalidAddress }
        return url
    }

    private static func makeRequest(url: URL, method: String, body: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requestTimeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        }
        return request
    }

    private static func send<T: Decodable>(
        _ request: URLRequest,
        session: URLSession,
        unauthorizedError: RemoteClientError
    ) async throws -> T {
        let (data, response) = try await load(request, session: session)
        guard let http = response as? HTTPURLResponse else { throw RemoteClientError.badResponse }

        switch http.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw RemoteClientError.badResponse
            }
        case 401:
            throw unauthorizedError
        case 429:
            throw RemoteClientError.lockedOut
        default:
            if let message = try? JSONDecoder().decode(RemoteError.self, from: data).error, !message.isEmpty {
                throw RemoteClientError.server(message)
            }
            throw RemoteClientError.badResponse
        }
    }

    /// Runs the request. Cancellation stays a `CancellationError`; every other failure means "unreachable".
    private static func load(_ request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        var retried = false
        while true {
            do {
                return try await session.data(for: request)
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch let error as URLError where error.code == .networkConnectionLost && !retried {
                // The desktop closes every connection after answering. If a pooled one went stale, try once more.
                retried = true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw RemoteClientError.unreachable
            }
        }
    }
}
