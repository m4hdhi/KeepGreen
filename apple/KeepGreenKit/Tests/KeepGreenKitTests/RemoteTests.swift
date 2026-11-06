import Foundation
import KeepGreenKit
import XCTest

final class RemoteTests: XCTestCase {
    private let vectorKey = "00112233445566778899aabbccddeeff"
    private let vectorTime = 1_700_000_000

    private let sampleStatusJSON = """
    {
      "name": "DESKTOP-ABC",
      "platform": "windows",
      "version": "2.0.0",
      "state": "Active",
      "isActive": true,
      "isEnabled": true,
      "isBoosted": false,
      "boostUntil": null,
      "headline": "You're staying green",
      "detail": "Work hours end today at 17:00.",
      "idleSeconds": 12,
      "nudgesToday": 87,
      "greenSecondsToday": 22320
    }
    """

    override func tearDown() {
        RemoteMockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: Signature

    func testSignatureMatchesSpecTestVector() {
        let signature = RemoteSignature.sign(key: vectorKey, method: "GET", path: "/v1/status", time: vectorTime, body: "")
        XCTAssertEqual(signature, "e61ba19958971173e1d8eb4038ff25f241eb73396f25529d28cfd3d602fd5e80")
    }

    func testSignatureCoversTheBody() {
        // Computed independently: HMAC-SHA256("00112233445566778899aabbccddeeff", "POST\n/v1/enabled\n1700000000\n{\"enabled\":true}")
        let signature = RemoteSignature.sign(
            key: vectorKey, method: "POST", path: "/v1/enabled", time: vectorTime, body: #"{"enabled":true}"#
        )
        XCTAssertEqual(signature, "94f5b142272af929468f3704a788d9ab3651f789ab9144c6e33454dd19f4eb85")
    }

    func testIsValidAcceptsAGoodSignatureWithinTheSkew() {
        let signature = RemoteSignature.sign(key: vectorKey, method: "GET", path: "/v1/status", time: vectorTime, body: "")
        for now in [vectorTime, vectorTime + 30, vectorTime - 30, vectorTime + 120, vectorTime - 120] {
            XCTAssertTrue(
                RemoteSignature.isValid(
                    signature: signature, key: vectorKey, method: "GET", path: "/v1/status", time: vectorTime, body: "", now: now
                ),
                "now = \(now)"
            )
        }
    }

    func testIsValidRejectsClockSkewOverTwoMinutes() {
        let signature = RemoteSignature.sign(key: vectorKey, method: "GET", path: "/v1/status", time: vectorTime, body: "")
        for now in [vectorTime + 121, vectorTime - 121, vectorTime + 3600] {
            XCTAssertFalse(
                RemoteSignature.isValid(
                    signature: signature, key: vectorKey, method: "GET", path: "/v1/status", time: vectorTime, body: "", now: now
                ),
                "now = \(now)"
            )
        }
    }

    func testIsValidRejectsBadSignatures() {
        let good = RemoteSignature.sign(key: vectorKey, method: "POST", path: "/v1/boost", time: vectorTime, body: #"{"minutes":60}"#)
        let flipped = String(good.dropLast()) + (good.hasSuffix("0") ? "1" : "0")

        func check(_ signature: String, key: String? = nil, method: String = "POST", path: String = "/v1/boost",
                   body: String = #"{"minutes":60}"#, line: UInt = #line) {
            XCTAssertFalse(
                RemoteSignature.isValid(
                    signature: signature, key: key ?? vectorKey, method: method, path: path, time: vectorTime, body: body, now: vectorTime
                ),
                line: line
            )
        }

        check(flipped)
        check("")
        check(String(good.prefix(63)))
        check(good + "0")
        check(String(repeating: "z", count: 64))
        check(good, key: "ffeeddccbbaa99887766554433221100")
        check(good, method: "GET")
        check(good, path: "/v1/boost/cancel")
        check(good, body: #"{"minutes":120}"#)

        XCTAssertTrue(
            RemoteSignature.isValid(
                signature: good, key: vectorKey, method: "POST", path: "/v1/boost", time: vectorTime, body: #"{"minutes":60}"#, now: vectorTime
            )
        )
    }

    func testIsValidSurvivesExtremeTimes() {
        let signature = RemoteSignature.sign(key: vectorKey, method: "GET", path: "/v1/status", time: Int.min, body: "")
        XCTAssertFalse(
            RemoteSignature.isValid(signature: signature, key: vectorKey, method: "GET", path: "/v1/status", time: Int.min, body: "", now: Int.max)
        )
        XCTAssertFalse(
            RemoteSignature.isValid(signature: signature, key: vectorKey, method: "GET", path: "/v1/status", time: Int.max, body: "", now: Int.min)
        )
    }

    // MARK: Pairing link

    func testPairingLinkParsesTheSpecExample() throws {
        let url = try XCTUnwrap(URL(string: "keepgreen://pair?host=192.168.1.20&port=47321&code=123456&name=Mahdhi%E2%80%99s%20PC"))
        let link = try XCTUnwrap(PairingLink(url: url))
        XCTAssertEqual(link.host, "192.168.1.20")
        XCTAssertEqual(link.port, 47321)
        XCTAssertEqual(link.code, "123456")
        XCTAssertEqual(link.name, "Mahdhi\u{2019}s PC")
    }

    func testPairingLinkDefaultsThePortAndAllowsNoName() throws {
        let url = try XCTUnwrap(URL(string: "keepgreen://pair?host=10.0.0.5&code=000042"))
        let link = try XCTUnwrap(PairingLink(url: url))
        XCTAssertEqual(link, PairingLink(host: "10.0.0.5", port: RemoteDefaults.port, code: "000042", name: nil))
        XCTAssertEqual(RemoteDefaults.port, 47321)
    }

    func testPairingLinkReadsPlusAsSpace() throws {
        let url = try XCTUnwrap(URL(string: "keepgreen://pair?host=10.0.0.5&code=123456&name=Office+PC"))
        XCTAssertEqual(PairingLink(url: url)?.name, "Office PC")
    }

    func testPairingLinkRoundTrips() throws {
        let links = [
            PairingLink(host: "192.168.1.20", port: 47321, code: "123456", name: "Mahdhi\u{2019}s PC"),
            PairingLink(host: "10.0.0.7", port: 50000, code: "987654", name: "Ana & Bo's + PC = 100% #1"),
            PairingLink(host: "studio-mac.local", port: 47321, code: "000000", name: nil),
        ]
        for link in links {
            XCTAssertTrue(link.url.absoluteString.hasPrefix("keepgreen://pair?"), link.url.absoluteString)
            XCTAssertEqual(PairingLink(url: link.url), link, link.url.absoluteString)
        }
    }

    func testPairingLinkWritesTheSpecFormat() {
        let link = PairingLink(host: "192.168.1.20", port: 47321, code: "123456", name: "Mahdhi\u{2019}s PC")
        XCTAssertEqual(
            link.url.absoluteString,
            "keepgreen://pair?host=192.168.1.20&port=47321&code=123456&name=Mahdhi%E2%80%99s%20PC"
        )
    }

    func testPairingLinkRejectsBadCodes() {
        let codes = ["", "12345", "1234567", "12a456", "12%20456", "%20123456", "-12345", "12.456",
                     "%D9%A1%D9%A2%D9%A3%D9%A4%D9%A5%D9%A6"] // Arabic-Indic digits
        for code in codes {
            let url = URL(string: "keepgreen://pair?host=192.168.1.20&port=47321&code=\(code)")!
            XCTAssertNil(PairingLink(url: url), "code \(code)")
        }
        XCTAssertNil(PairingLink(url: URL(string: "keepgreen://pair?host=192.168.1.20&port=47321")!), "missing code")
    }

    func testPairingLinkRejectsOtherLinks() {
        let links = [
            "https://pair?host=192.168.1.20&code=123456",
            "keepgreen://unpair?host=192.168.1.20&code=123456",
            "keepgreen://pair?code=123456",
            "keepgreen://pair?host=&code=123456",
            "keepgreen://pair?host=192.168.1.20&port=0&code=123456",
            "keepgreen://pair?host=192.168.1.20&port=70000&code=123456",
            "keepgreen://pair?host=192.168.1.20&port=abc&code=123456",
        ]
        for text in links {
            XCTAssertNil(PairingLink(url: URL(string: text)!), text)
        }
    }

    // MARK: Status JSON

    func testStatusDecodesTheSpecSample() throws {
        let status = try JSONDecoder().decode(RemoteStatus.self, from: Data(sampleStatusJSON.utf8))
        XCTAssertEqual(
            status,
            RemoteStatus(
                name: "DESKTOP-ABC",
                platform: "windows",
                version: "2.0.0",
                state: "Active",
                isActive: true,
                isEnabled: true,
                isBoosted: false,
                boostUntil: nil,
                headline: "You're staying green",
                detail: "Work hours end today at 17:00.",
                idleSeconds: 12,
                nudgesToday: 87,
                greenSecondsToday: 22320
            )
        )
    }

    func testStatusDecodesABoostTime() throws {
        let json = sampleStatusJSON
            .replacingOccurrences(of: #""boostUntil": null"#, with: #""boostUntil": "2026-11-05T14:30:00+04:00""#)
            .replacingOccurrences(of: #""isBoosted": false"#, with: #""isBoosted": true"#)
        let status = try JSONDecoder().decode(RemoteStatus.self, from: Data(json.utf8))
        XCTAssertTrue(status.isBoosted)
        XCTAssertEqual(status.boostUntil, "2026-11-05T14:30:00+04:00")
    }

    func testStatusWritesNullBoostUntilAndRoundTrips() throws {
        let status = try JSONDecoder().decode(RemoteStatus.self, from: Data(sampleStatusJSON.utf8))
        let data = try JSONEncoder().encode(status)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(object["boostUntil"] is NSNull, "boostUntil must be written as null")
        XCTAssertEqual(object.count, 13)
        XCTAssertEqual(try JSONDecoder().decode(RemoteStatus.self, from: data), status)
    }

    func testPingPairAndErrorBodiesDecode() throws {
        let ping = try JSONDecoder().decode(
            RemotePing.self,
            from: Data(#"{"app": "KeepGreen", "api": 1, "name": "DESKTOP-ABC", "platform": "windows", "version": "2.0.0"}"#.utf8)
        )
        XCTAssertEqual(ping.app, "KeepGreen")
        XCTAssertEqual(ping.api, 1)
        XCTAssertEqual(ping.name, "DESKTOP-ABC")

        let pair = try JSONDecoder().decode(
            RemotePairResponse.self,
            from: Data(#"{"key": "3f1c9a0b5e7d42c8a1b6e0f9d3c5a7b1", "name": "DESKTOP-ABC", "platform": "windows", "version": "2.0.0"}"#.utf8)
        )
        XCTAssertEqual(pair.key, "3f1c9a0b5e7d42c8a1b6e0f9d3c5a7b1")
        XCTAssertEqual(pair.platform, "windows")

        let error = try JSONDecoder().decode(RemoteError.self, from: Data(#"{"error": "Unknown path"}"#.utf8))
        XCTAssertEqual(error.error, "Unknown path")
    }

    func testDesktopRoundTripsThroughJSON() throws {
        let desktop = RemoteDesktop(host: "192.168.1.20", port: 47321, key: vectorKey, name: "DESKTOP-ABC", platform: "windows")
        let copy = try JSONDecoder().decode(RemoteDesktop.self, from: JSONEncoder().encode(desktop))
        XCTAssertEqual(copy, desktop)
    }

    // MARK: Client against a fake desktop

    func testStatusRequestIsSigned() async throws {
        RemoteMockURLProtocol.respond(200, sampleStatusJSON)
        let before = Int(Date().timeIntervalSince1970)
        let status = try await makeClient().status()
        XCTAssertEqual(status.name, "DESKTOP-ABC")

        let request = try XCTUnwrap(RemoteMockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.20:47321/v1/status")
        XCTAssertEqual(RemoteMockURLProtocol.lastBody, Data())
        try assertSigned(request, body: "", path: "/v1/status", method: "GET", notBefore: before)
    }

    func testCommandsSendTheSpecBodiesAndSignThem() async throws {
        let client = makeClient()
        let cases: [(String, String, () async throws -> RemoteStatus)] = [
            ("/v1/enabled", #"{"enabled":true}"#, { try await client.setEnabled(true) }),
            ("/v1/enabled", #"{"enabled":false}"#, { try await client.setEnabled(false) }),
            ("/v1/boost", #"{"minutes":60}"#, { try await client.boost(minutes: 60) }),
            ("/v1/boost", #"{"minutes":720}"#, { try await client.boost(minutes: 5000) }),
            ("/v1/boost", #"{"untilEndOfWorkday":true}"#, { try await client.boostUntilEndOfWorkday() }),
            ("/v1/boost/cancel", "{}", { try await client.cancelBoost() }),
        ]
        for (path, expectedBody, call) in cases {
            RemoteMockURLProtocol.respond(200, sampleStatusJSON)
            let before = Int(Date().timeIntervalSince1970)
            _ = try await call()

            let request = try XCTUnwrap(RemoteMockURLProtocol.lastRequest)
            let body = String(decoding: try XCTUnwrap(RemoteMockURLProtocol.lastBody), as: UTF8.self)
            XCTAssertEqual(request.httpMethod, "POST", path)
            XCTAssertEqual(request.url?.path, path)
            XCTAssertEqual(body, expectedBody, path)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json", path)
            try assertSigned(request, body: body, path: path, method: "POST", notBefore: before)
        }
    }

    func testPairSendsCodeAndDeviceAndReturnsTheDesktop() async throws {
        RemoteMockURLProtocol.respond(
            200, #"{"key": "3f1c9a0b5e7d42c8a1b6e0f9d3c5a7b1", "name": "DESKTOP-ABC", "platform": "windows", "version": "2.0.0"}"#
        )
        let desktop = try await RemoteClient.pair(
            host: " 192.168.1.20 ", port: 47321, code: "123456", device: "Test iPhone", session: RemoteMockURLProtocol.session()
        )
        XCTAssertEqual(desktop.host, "192.168.1.20")
        XCTAssertEqual(desktop.port, 47321)
        XCTAssertEqual(desktop.key, "3f1c9a0b5e7d42c8a1b6e0f9d3c5a7b1")
        XCTAssertEqual(desktop.name, "DESKTOP-ABC")
        XCTAssertEqual(desktop.platform, "windows")

        let request = try XCTUnwrap(RemoteMockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/pair")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-KeepGreen-Signature"))
        let sent = try JSONDecoder().decode(RemotePairRequest.self, from: try XCTUnwrap(RemoteMockURLProtocol.lastBody))
        XCTAssertEqual(sent.code, "123456")
        XCTAssertEqual(sent.device, "Test iPhone")
    }

    func testPingChecksItIsKeepGreen() async throws {
        RemoteMockURLProtocol.respond(200, #"{"app": "KeepGreen", "api": 1, "name": "Studio", "platform": "macos", "version": "2.0.0"}"#)
        let ping = try await RemoteClient.ping(host: "192.168.1.20", port: 47321, session: RemoteMockURLProtocol.session())
        XCTAssertEqual(ping.platform, "macos")
        XCTAssertEqual(RemoteMockURLProtocol.lastRequest?.url?.path, "/v1/ping")

        RemoteMockURLProtocol.respond(200, #"{"app": "Something else", "api": 1, "name": "x", "platform": "x", "version": "1"}"#)
        await assertError("badResponse") {
            _ = try await RemoteClient.ping(host: "192.168.1.20", port: 47321, session: RemoteMockURLProtocol.session())
        }
    }

    func testErrorsMapToFriendlyCases() async {
        let session = RemoteMockURLProtocol.session()
        let client = makeClient()

        RemoteMockURLProtocol.respond(401, #"{"error": "Bad signature"}"#)
        await assertError("unauthorized") { _ = try await client.status() }

        RemoteMockURLProtocol.respond(401, #"{"error": "Wrong code"}"#)
        await assertError("wrongCode") {
            _ = try await RemoteClient.pair(host: "192.168.1.20", port: 47321, code: "111111", device: "x", session: session)
        }

        RemoteMockURLProtocol.respond(429, #"{"error": "Too many attempts"}"#)
        await assertError("lockedOut") {
            _ = try await RemoteClient.pair(host: "192.168.1.20", port: 47321, code: "111111", device: "x", session: session)
        }

        RemoteMockURLProtocol.respond(400, #"{"error": "Minutes must be 1 to 720."}"#)
        await assertError(#"server("Minutes must be 1 to 720.")"#) { _ = try await client.boost(minutes: 10) }

        RemoteMockURLProtocol.respond(500, "not json")
        await assertError("badResponse") { _ = try await client.status() }

        RemoteMockURLProtocol.respond(200, "{}")
        await assertError("badResponse") { _ = try await client.status() }

        RemoteMockURLProtocol.fail(URLError(.cannotConnectToHost))
        await assertError("unreachable") { _ = try await client.status() }

        RemoteMockURLProtocol.fail(URLError(.timedOut))
        await assertError("unreachable") { _ = try await client.status() }
    }

    func testBadInputFailsWithoutTouchingTheNetwork() async {
        let session = RemoteMockURLProtocol.session()
        await assertError("wrongCode") {
            _ = try await RemoteClient.pair(host: "192.168.1.20", port: 47321, code: "12a456", device: "x", session: session)
        }
        await assertError("invalidAddress") {
            _ = try await RemoteClient.ping(host: "my computer", port: 47321, session: session)
        }
        await assertError("invalidAddress") {
            _ = try await RemoteClient.ping(host: "192.168.1.20", port: 0, session: session)
        }
        XCTAssertNil(RemoteMockURLProtocol.lastRequest)
    }

    func testEveryErrorHasAMessage() {
        let errors: [RemoteClientError] = [.invalidAddress, .wrongCode, .lockedOut, .unauthorized, .unreachable, .badResponse, .server("")]
        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty, "\(error)")
        }
        XCTAssertEqual(RemoteClientError.wrongCode.errorDescription, "Wrong or expired pairing code.")
        XCTAssertEqual(RemoteClientError.lockedOut.errorDescription, "Too many tries. Wait a minute and get a new code.")
        XCTAssertEqual(RemoteClientError.server("Nope").errorDescription, "Nope")
    }

    // MARK: Helpers

    private func makeClient() -> RemoteClient {
        RemoteClient(
            desktop: RemoteDesktop(host: "192.168.1.20", port: 47321, key: vectorKey, name: "DESKTOP-ABC", platform: "windows"),
            session: RemoteMockURLProtocol.session()
        )
    }

    private func assertSigned(
        _ request: URLRequest, body: String, path: String, method: String, notBefore: Int, line: UInt = #line
    ) throws {
        let timeText = try XCTUnwrap(request.value(forHTTPHeaderField: "X-KeepGreen-Time"), line: line)
        let time = try XCTUnwrap(Int(timeText), "time must be whole seconds", line: line)
        XCTAssertGreaterThanOrEqual(time, notBefore, line: line)
        XCTAssertLessThanOrEqual(time, Int(Date().timeIntervalSince1970), line: line)

        let signature = try XCTUnwrap(request.value(forHTTPHeaderField: "X-KeepGreen-Signature"), line: line)
        XCTAssertEqual(signature, RemoteSignature.sign(key: vectorKey, method: method, path: path, time: time, body: body), line: line)
        XCTAssertTrue(
            RemoteSignature.isValid(signature: signature, key: vectorKey, method: method, path: path, time: time, body: body, now: time),
            line: line
        )
    }

    /// Compares the case by name, e.g. `"wrongCode"` or `server("message")`.
    private func assertError(_ expected: String, line: UInt = #line, _ work: () async throws -> Void) async {
        do {
            try await work()
            XCTFail("Expected \(expected), but the call succeeded", line: line)
        } catch let error as RemoteClientError {
            XCTAssertEqual(String(describing: error), expected, line: line)
        } catch {
            XCTFail("Expected \(expected), got \(error)", line: line)
        }
    }
}

/// Stands in for a desktop: answers every request with a canned response and remembers what it got.
private final class RemoteMockURLProtocol: URLProtocol {
    private static var reply: (status: Int, body: String)?
    private static var failure: URLError?
    private(set) static var lastRequest: URLRequest?
    private(set) static var lastBody: Data?

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func respond(_ status: Int, _ body: String) {
        reply = (status, body)
        failure = nil
    }

    static func fail(_ error: URLError) {
        reply = nil
        failure = error
    }

    static func reset() {
        reply = nil
        failure = nil
        lastRequest = nil
        lastBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        RemoteMockURLProtocol.lastRequest = request
        RemoteMockURLProtocol.lastBody = RemoteMockURLProtocol.readBody(of: request)

        if let failure = RemoteMockURLProtocol.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        guard let reply = RemoteMockURLProtocol.reply,
              let url = request.url,
              let response = HTTPURLResponse(
                  url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json", "Connection": "close"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession hands bodies to URL protocols as a stream.
    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
    }
}
