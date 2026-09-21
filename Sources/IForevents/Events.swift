import Foundation

/// Free-form event or trait properties. Nested dictionaries are flattened with `_`.
public typealias Properties = [String: Any]

/// Event types the api distinguishes.
public enum EventType: String {
    case track
    case pageView = "page_view"
}

/// The app's own user id plus traits (context merged in, nested maps flattened).
public struct IdentifyEvent {
    public let customId: String
    public let traits: Properties

    public init(customId: String, traits: Properties = [:]) {
        self.customId = customId
        self.traits = traits
    }
}

/// A tracked event ready for every integration.
public struct TrackEvent {
    public let name: String
    public let type: EventType
    public let properties: Properties
    /// When the event was queued; sent as `created_at`.
    public let timestamp: Date

    public init(name: String, type: EventType = .track, properties: Properties = [:], timestamp: Date = Date()) {
        self.name = name
        self.type = type
        self.properties = properties
        self.timestamp = timestamp
    }
}

/// A page (web) or screen (mobile) view.
public struct PageEvent {
    public let name: String
    public let properties: Properties
    public let navigationType: String?
    public let toRoute: String?
    public let previousRoute: String?
    public let timestamp: Date

    public init(name: String = "page_view", properties: Properties = [:], navigationType: String? = nil, toRoute: String? = nil, previousRoute: String? = nil, timestamp: Date = Date()) {
        self.name = name.isEmpty ? "page_view" : name
        self.properties = properties
        self.navigationType = navigationType
        self.toRoute = toRoute
        self.previousRoute = previousRoute
        self.timestamp = timestamp
    }
}

/// Outcome of one integration call; the facade never throws for these.
public struct IntegrationResult {
    public let integration: String
    public let success: Bool
    public let error: Error?
    public let timestamp = Date()
}

/// Flattens nested dictionaries with `_`: `["a": ["b": 1]]` becomes `["a_b": 1]`.
public func flatten(_ input: Properties, prefix: String = "") -> Properties {
    var out: Properties = [:]
    for (key, value) in input {
        let name = prefix.isEmpty ? key : "\(prefix)_\(key)"
        if let nested = value as? Properties {
            out.merge(flatten(nested, prefix: name)) { _, new in new }
        } else {
            out[name] = value
        }
    }
    return out
}

/// RFC 3339 UTC with milliseconds.
enum ISO8601 {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func string(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
