import Foundation

/// The status object every remote endpoint returns. See docs/remote-api.md.
public struct RemoteStatus: Codable, Equatable {
    public var name: String
    /// `windows` or `macos`.
    public var platform: String
    public var version: String
    /// `Active`, `Disabled`, `OffSchedule`, `DayOff`, `Break`, `Locked`, `OnBattery`, `LowBattery` or
    /// `WaitingForApp`. Clients show values they don't know as a neutral state.
    public var state: String
    public var isActive: Bool
    public var isEnabled: Bool
    public var isBoosted: Bool
    /// `nil`, or ISO 8601 with offset, e.g. `2026-11-05T14:30:00+04:00`.
    public var boostUntil: String?
    /// The same friendly sentences the desktop dashboard shows. Phones display them as-is.
    public var headline: String
    public var detail: String
    public var idleSeconds: Int
    public var nudgesToday: Int
    public var greenSecondsToday: Int

    public init(
        name: String,
        platform: String,
        version: String,
        state: String,
        isActive: Bool,
        isEnabled: Bool,
        isBoosted: Bool,
        boostUntil: String?,
        headline: String,
        detail: String,
        idleSeconds: Int,
        nudgesToday: Int,
        greenSecondsToday: Int
    ) {
        self.name = name
        self.platform = platform
        self.version = version
        self.state = state
        self.isActive = isActive
        self.isEnabled = isEnabled
        self.isBoosted = isBoosted
        self.boostUntil = boostUntil
        self.headline = headline
        self.detail = detail
        self.idleSeconds = idleSeconds
        self.nudgesToday = nudgesToday
        self.greenSecondsToday = greenSecondsToday
    }

    private enum CodingKeys: String, CodingKey {
        case name, platform, version, state, isActive, isEnabled, isBoosted, boostUntil
        case headline, detail, idleSeconds, nudgesToday, greenSecondsToday
    }

    /// Written by hand so `boostUntil` is sent as `null` rather than left out, as the spec shows.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(platform, forKey: .platform)
        try container.encode(version, forKey: .version)
        try container.encode(state, forKey: .state)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isBoosted, forKey: .isBoosted)
        if let boostUntil = boostUntil {
            try container.encode(boostUntil, forKey: .boostUntil)
        } else {
            try container.encodeNil(forKey: .boostUntil)
        }
        try container.encode(headline, forKey: .headline)
        try container.encode(detail, forKey: .detail)
        try container.encode(idleSeconds, forKey: .idleSeconds)
        try container.encode(nudgesToday, forKey: .nudgesToday)
        try container.encode(greenSecondsToday, forKey: .greenSecondsToday)
    }
}

/// Body of `POST /v1/pair`.
public struct RemotePairRequest: Codable {
    public var code: String
    public var device: String

    public init(code: String, device: String) {
        self.code = code
        self.device = device
    }
}

/// Answer to a successful `POST /v1/pair`.
public struct RemotePairResponse: Codable {
    /// 16 random bytes as 32 lowercase hex characters. Shared by every phone paired with that desktop.
    public var key: String
    public var name: String
    public var platform: String
    public var version: String

    public init(key: String, name: String, platform: String, version: String) {
        self.key = key
        self.name = name
        self.platform = platform
        self.version = version
    }
}

/// Answer to the unsigned `GET /v1/ping` health check.
public struct RemotePing: Codable {
    /// Always `KeepGreen`.
    public var app: String
    /// The API version, `1`.
    public var api: Int
    public var name: String
    public var platform: String
    public var version: String

    public init(app: String, api: Int, name: String, platform: String, version: String) {
        self.app = app
        self.api = api
        self.name = name
        self.platform = platform
        self.version = version
    }
}

/// Body of every error answer: `{"error": "human readable message"}`.
public struct RemoteError: Codable {
    public var error: String

    public init(error: String) {
        self.error = error
    }
}

/// A desktop this phone has paired with.
public struct RemoteDesktop: Codable, Identifiable, Hashable {
    public var id: UUID
    public var host: String
    public var port: Int
    /// The shared signing key. It is a secret: whoever has it can control the desktop on its network.
    public var key: String
    public var name: String
    /// `windows` or `macos`.
    public var platform: String

    public init(id: UUID = UUID(), host: String, port: Int, key: String, name: String, platform: String) {
        self.id = id
        self.host = host
        self.port = port
        self.key = key
        self.name = name
        self.platform = platform
    }
}
