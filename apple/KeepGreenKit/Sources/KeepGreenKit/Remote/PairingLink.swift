import Foundation

/// The pairing link a desktop shows as a QR code:
/// `keepgreen://pair?host=192.168.1.20&port=47321&code=123456&name=Mahdhi%E2%80%99s%20PC`
public struct PairingLink: Equatable {
    public var host: String
    public var port: Int
    /// Exactly six ASCII digits.
    public var code: String
    /// The desktop's name, for display only.
    public var name: String?

    public init(host: String, port: Int, code: String, name: String?) {
        self.host = host
        self.port = port
        self.code = code
        self.name = name
    }

    /// Parses a pairing link. Returns `nil` unless it is a `keepgreen://pair` link with a host and a six-digit code.
    /// A missing port means the default, 47321.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "keepgreen",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        // keepgreen://pair?... puts "pair" in the host; keepgreen:pair?... and keepgreen:///pair?... put it in the path.
        let action = (components.host ?? "").isEmpty
            ? components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : (components.host ?? "")
        guard action.lowercased() == "pair" else { return nil }

        // Read the raw query so a "+" can mean a space (form encoding) while "%2B" stays a plus.
        let items = components.percentEncodedQueryItems ?? []
        let value: (String) -> String? = { name in
            guard let raw = items.first(where: { $0.name == name })?.value else { return nil }
            let spaced = raw.replacingOccurrences(of: "+", with: " ")
            return spaced.removingPercentEncoding ?? spaced
        }

        guard let host = value("host")?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else { return nil }

        var port = RemoteDefaults.port
        if let portText = value("port"), !portText.isEmpty {
            guard let parsed = Int(portText), (1...65535).contains(parsed) else { return nil }
            port = parsed
        }

        guard let code = value("code"), PairingLink.isValidCode(code) else { return nil }

        let name = value("name")?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.host = host
        self.port = port
        self.code = code
        self.name = (name?.isEmpty ?? true) ? nil : name
    }

    /// The link as a URL, ready for a QR code. Values are strictly percent-encoded, so names with
    /// `&`, `+` or `=` survive the round trip.
    public var url: URL {
        var pairs = [
            ("host", host),
            ("port", String(port)),
            ("code", code),
        ]
        if let name = name, !name.isEmpty {
            pairs.append(("name", name))
        }
        let query = pairs
            .map { "\($0.0)=\(PairingLink.encode($0.1))" }
            .joined(separator: "&")
        // Every character in `query` is unreserved or percent-encoded, so this cannot fail.
        return URL(string: "keepgreen://pair?" + query) ?? URL(string: "keepgreen://pair")!
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    private static func isValidCode(_ code: String) -> Bool {
        code.utf8.count == 6 && code.utf8.allSatisfy { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }
    }
}
