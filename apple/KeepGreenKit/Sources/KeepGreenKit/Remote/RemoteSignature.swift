import CryptoKit
import Foundation

/// Fixed values of the KeepGreen Remote API, version 1. The contract lives in docs/remote-api.md.
public enum RemoteDefaults {
    /// The TCP port the desktop apps listen on.
    public static let port = 47321
}

/// Signs and checks remote requests.
///
/// The signature is the lowercase hex HMAC-SHA256 of `METHOD\nPATH\nTIME\nBODY`, keyed with the
/// UTF-8 bytes of the 32-character hex key string (not the 16 bytes it encodes).
public enum RemoteSignature {
    /// Returns the lowercase hex signature for one request.
    /// - Parameters:
    ///   - key: the shared key, exactly as the desktop handed it out during pairing.
    ///   - method: `GET` or `POST`.
    ///   - path: the path without a query string, e.g. `/v1/status`.
    ///   - time: Unix time in whole seconds, the exact value of the `X-KeepGreen-Time` header.
    ///   - body: the exact request body, `""` for GET.
    public static func sign(key: String, method: String, path: String, time: Int, body: String) -> String {
        let message = method.uppercased() + "\n" + path + "\n" + String(time) + "\n" + body
        let symmetricKey = SymmetricKey(data: Data(key.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: symmetricKey)
        return hex(Array(code))
    }

    /// Checks a signature in constant time, and that `time` is within `maxSkew` seconds of `now`.
    public static func isValid(
        signature: String,
        key: String,
        method: String,
        path: String,
        time: Int,
        body: String,
        now: Int,
        maxSkew: Int = 120
    ) -> Bool {
        // Overflow-safe: `time` comes straight from a request header.
        guard maxSkew >= 0 else { return false }
        let (difference, overflow) = now.subtractingReportingOverflow(time)
        guard !overflow, difference.magnitude <= UInt(maxSkew) else { return false }

        let expected = Array(sign(key: key, method: method, path: path, time: time, body: body).utf8)
        let provided = Array(signature.lowercased().utf8)
        guard expected.count == provided.count else { return false }

        var mismatch: UInt8 = 0
        for index in 0..<expected.count {
            mismatch |= expected[index] ^ provided[index]
        }
        return mismatch == 0
    }

    private static let hexDigits: [Character] = Array("0123456789abcdef")

    private static func hex(_ bytes: [UInt8]) -> String {
        var text = ""
        text.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            text.append(hexDigits[Int(byte >> 4)])
            text.append(hexDigits[Int(byte & 0x0F)])
        }
        return text
    }
}
