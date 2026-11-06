import Foundation

/// Client version protocol (SPEC.md): the `X-Client-Version` value an app sends, version comparison,
/// policy evaluation, and reading the server's upgrade signal from a response.
public struct ClientVersion: Equatable, Sendable {
    public static let header = "X-Client-Version"
    public static let queryParameter = "client_version"
    public static let upgradeHeader = "X-Client-Upgrade"
    public static let upgradeURLHeader = "X-Upgrade-URL"
    public static let upgradeRequiredMessage = "This version of the app is no longer supported. Please update."

    public var app: String
    public var version: String
    public var build: String?
    public var platform: String

    public init(app: String, version: String, build: String? = nil, platform: String) {
        self.app = app
        self.version = version
        self.build = build
        self.platform = platform
    }

    /// `<app>/<version>[+<build>] (<platform>)`
    public var headerValue: String {
        "\(app)/\(version)\(build.map { "+\($0)" } ?? "") (\(platform))"
    }

    /// This app's version from its bundle (`CFBundleShortVersionString`, `CFBundleVersion`).
    public static func fromBundle(_ bundle: Bundle = .main, app: String, platform: String) -> ClientVersion {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let valid = version.flatMap { isVersion($0) ? $0 : nil } ?? "0"
        let validBuild = build.flatMap { $0.range(of: #"^[0-9A-Za-z.-]+$"#, options: .regularExpression) != nil ? $0 : nil }
        return ClientVersion(app: app, version: valid, build: validBuild, platform: platform)
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"^([a-z][a-z0-9-]*)/(\d+(?:\.\d+){0,3})(?:\+([0-9A-Za-z.-]+))?\s+\(([a-z][a-z0-9-]*)\)$"#)

    /// Parses an `X-Client-Version` value; `nil` when missing or malformed (an unknown client).
    public static func parse(_ value: String?) -> ClientVersion? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let range = NSRange(value.startIndex..., in: value)
        guard let m = pattern.firstMatch(in: value, range: range) else { return nil }
        func group(_ i: Int) -> String? {
            Range(m.range(at: i), in: value).map { String(value[$0]) }
        }
        return ClientVersion(app: group(1)!, version: group(2)!, build: group(3), platform: group(4)!)
    }

    static func isVersion(_ s: String) -> Bool {
        s.range(of: #"^\d+(?:\.\d+){0,3}$"#, options: .regularExpression) != nil
    }

    /// Numeric, component-wise comparison; missing components are 0. Returns -1, 0 or 1.
    public static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    /// True when `client` is at least `version`; an unknown client counts as current.
    public static func atLeast(_ client: ClientVersion?, _ version: String) -> Bool {
        guard let client else { return true }
        return compare(client.version, version) >= 0
    }
}

// MARK: - Policy (server side)

public enum UpgradeLevel: String, Equatable, Sendable {
    case none, recommended, required
}

public struct PolicyEntry: Equatable, Sendable {
    public var app: String
    public var platform: String
    public var minimum: String?
    public var recommended: String?
    public var upgradeURL: String?

    public init(app: String, platform: String, minimum: String? = nil, recommended: String? = nil, upgradeURL: String? = nil) {
        self.app = app
        self.platform = platform
        self.minimum = minimum
        self.recommended = recommended
        self.upgradeURL = upgradeURL
    }
}

public struct Evaluation: Equatable, Sendable {
    public var level: UpgradeLevel
    public var refuse: Bool
    public var headers: [String: String]
    /// The 426 body fields when `refuse`: error, message and (optionally) upgradeUrl.
    public var body: [String: String]?
}

public enum ClientVersionPolicy {
    private static let safeMethods: Set<String> = ["GET", "HEAD", "OPTIONS"]

    public static func level(_ policy: [PolicyEntry], _ client: ClientVersion?) -> (UpgradeLevel, PolicyEntry?) {
        guard let client,
              let entry = policy.first(where: { $0.app == client.app && $0.platform == client.platform }) else {
            return (.none, nil)
        }
        if let minimum = entry.minimum, ClientVersion.compare(client.version, minimum) < 0 { return (.required, entry) }
        if let recommended = entry.recommended, ClientVersion.compare(client.version, recommended) < 0 { return (.recommended, entry) }
        return (.none, entry)
    }

    public static func evaluate(_ policy: [PolicyEntry], clientVersion: String?, method: String) -> Evaluation {
        let (level, entry) = level(policy, ClientVersion.parse(clientVersion))
        guard level != .none else { return Evaluation(level: .none, refuse: false, headers: [:], body: nil) }
        var headers = [ClientVersion.upgradeHeader: level.rawValue]
        if let url = entry?.upgradeURL { headers[ClientVersion.upgradeURLHeader] = url }
        let refuse = level == .required && !safeMethods.contains(method.uppercased())
        guard refuse else { return Evaluation(level: level, refuse: false, headers: headers, body: nil) }
        var body = ["error": "upgrade_required", "message": ClientVersion.upgradeRequiredMessage]
        if let url = entry?.upgradeURL { body["upgradeUrl"] = url }
        return Evaluation(level: level, refuse: true, headers: headers, body: body)
    }
}

// MARK: - Upgrade signal (client side)

/// What a response says about this app's version. The latest response wins: a response without
/// `X-Client-Upgrade` is `.none` and clears an earlier nudge.
public struct UpgradeSignal: Equatable, Sendable {
    public var level: UpgradeLevel
    public var upgradeURL: URL?

    public init(level: UpgradeLevel, upgradeURL: URL? = nil) {
        self.level = level
        self.upgradeURL = upgradeURL
    }

    public static func from(_ response: HTTPURLResponse) -> UpgradeSignal {
        if response.statusCode == 426 {
            return UpgradeSignal(level: .required, upgradeURL: url(response))
        }
        let raw = response.value(forHTTPHeaderField: ClientVersion.upgradeHeader)?.lowercased()
        let level = raw.flatMap(UpgradeLevel.init(rawValue:)) ?? .none
        return UpgradeSignal(level: level, upgradeURL: level == .none ? nil : url(response))
    }

    private static func url(_ response: HTTPURLResponse) -> URL? {
        response.value(forHTTPHeaderField: ClientVersion.upgradeURLHeader).flatMap(URL.init(string:))
    }
}
