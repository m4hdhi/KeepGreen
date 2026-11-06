import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Darwin
import Security
import SystemConfiguration

/// Who this Mac is, as the phone remote reports it.
enum MacInfo {
    /// The name people gave this Mac, e.g. "Mahdhi's MacBook Pro". Looked up once.
    static let computerName: String = {
        // The same name Host.current().localizedName returns, without Host's slow address lookups.
        if let configured = SCDynamicStoreCopyComputerName(nil, nil) {
            let name = configured as String
            if !name.isEmpty {
                return name
            }
        }
        return Host.current().localizedName ?? "Mac"
    }()

    static let version: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0"

    static let platform = "macos"
}

enum NetworkInfo {
    /// The Mac's IPv4 addresses on interfaces that are up, skipping loopback. Wi-Fi and Ethernet ("en…") first.
    static func localIPv4Addresses() -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let head = first else { return [] }
        defer { freeifaddrs(first) }

        var found: [(name: String, address: String)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }

            let flags = Int32(truncatingIfNeeded: entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET)
            else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }

            let text = host.withUnsafeBufferPointer { buffer in String(cString: buffer.baseAddress!) }
            // Self-assigned 169.254.x.x addresses can't be reached from a phone.
            guard !text.isEmpty, !text.hasPrefix("169.254.") else { continue }

            let name = String(cString: entry.pointee.ifa_name)
            if !found.contains(where: { $0.address == text }) {
                found.append((name, text))
            }
        }

        let preferred = found.filter { $0.name.hasPrefix("en") }
        let others = found.filter { !$0.name.hasPrefix("en") }
        return (preferred + others).map { $0.address }
    }
}

enum RemoteKeyMaker {
    /// 16 random bytes as 32 lowercase hex characters.
    static func makeKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return bytes.map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0" + hex : hex
        }.joined()
    }

    /// A 6-digit pairing code, e.g. "042917".
    static func makePairingCode() -> String {
        let number = Int.random(in: 0...999_999)
        let digits = String(number)
        return String(repeating: "0", count: 6 - digits.count) + digits
    }
}

enum RemoteTime {
    /// ISO 8601 with the local offset, e.g. "2026-11-05T14:30:00+04:00".
    static func iso8601(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        return formatter.string(from: date)
    }
}

enum QRCode {
    /// A crisp black-on-white QR code, one point per module. Scale it up with `.interpolation(.none)`.
    static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}
