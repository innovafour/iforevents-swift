import Foundation
import IForevents
import Mixpanel

/// What the adapter needs from `MixpanelInstance`; a fake satisfies it in tests.
/// Method names are prefixed so they never shadow the vendor's defaulted overloads.
public protocol MixpanelClient: AnyObject {
    func mpIdentify(distinctId: String)
    func mpSetPeople(_ properties: [String: MixpanelType])
    func mpTrack(event: String, properties: [String: MixpanelType])
    func mpReset()
    func mpFlush()
}

extension MixpanelInstance: MixpanelClient {
    public func mpIdentify(distinctId: String) { identify(distinctId: distinctId, usePeople: true, completion: nil) }
    public func mpSetPeople(_ properties: [String: MixpanelType]) { people.set(properties: properties) }
    public func mpTrack(event: String, properties: [String: MixpanelType]) { track(event: event, properties: properties) }
    public func mpReset() { reset(completion: nil) }
    public func mpFlush() { flush(performFullFlush: false, completion: nil) }
}

/// Forwards calls to Mixpanel through `mixpanel-swift`. Mirrors `iforevents_mixpanel`.
public final class MixpanelIntegration: BaseIntegration {
    private let client: MixpanelClient

    /// Initializes the Mixpanel SDK with the token (automatic events off, as in the Flutter adapter).
    public convenience init(token: String, trackAutomaticEvents: Bool = false, serverURL: String? = nil, hooks: Hooks = Hooks()) {
        // MixpanelOptions is the one initializer available on every Apple platform.
        let options = MixpanelOptions(token: token, trackAutomaticEvents: trackAutomaticEvents, serverURL: serverURL)
        let instance = Mixpanel.initialize(options: options)
        self.init(client: instance, hooks: hooks)
    }

    /// Reuses an instance you already configured, or a fake in tests.
    public init(client: MixpanelClient, hooks: Hooks = Hooks()) {
        self.client = client
        super.init(name: "MixpanelIntegration", hooks: hooks)
    }

    public override func identify(_ event: IdentifyEvent) throws {
        try super.identify(event)
        client.mpIdentify(distinctId: event.customId)
        client.mpSetPeople(Self.convert(event.traits))
    }

    public override func track(_ event: TrackEvent) throws {
        try super.track(event)
        client.mpTrack(event: event.name, properties: Self.convert(event.properties))
    }

    public override func page(_ event: PageEvent) throws {
        try super.page(event)
        var props = event.properties
        if let v = event.navigationType { props["navigation_type"] = v }
        if let v = event.toRoute { props["to_route"] = v }
        if let v = event.previousRoute { props["previous_route"] = v }
        client.mpTrack(event: event.name, properties: Self.convert(props))
    }

    public override func reset() throws {
        try super.reset()
        client.mpFlush()
        client.mpReset()
    }

    public override func flush() throws {
        client.mpFlush()
    }

    /// Mixpanel accepts String, numbers, Bool, Date, URL, arrays and dictionaries of those; everything else is stringified.
    static func convert(_ properties: IForevents.Properties) -> [String: MixpanelType] {
        var out: [String: MixpanelType] = [:]
        for (k, v) in properties {
            guard let value = convertValue(v) else { continue }
            out[k] = value
        }
        return out
    }

    private static func convertValue(_ v: Any) -> MixpanelType? {
        switch v {
        case let s as String: return s
        case let b as Bool: return b
        case let i as Int: return i
        case let d as Double: return d
        case let f as Float: return f
        case let date as Date: return date
        case let url as URL: return url
        case let array as [Any]: return array.compactMap(convertValue)
        case let dict as [String: Any]: return convert(dict)
        case is NSNull: return NSNull()
        case Optional<Any>.none: return nil
        default: return String(describing: v)
        }
    }
}
