import AmplitudeSwift
import Foundation
import IForevents

/// What the adapter needs from `Amplitude`; a fake satisfies it in tests.
public protocol AmplitudeClient: AnyObject {
    func ampSetUserId(_ userId: String?)
    func ampIdentify(userProperties: [String: Any])
    func ampTrack(eventType: String, eventProperties: [String: Any]?)
    func ampReset()
    func ampFlush()
}

extension Amplitude: AmplitudeClient {
    public func ampSetUserId(_ userId: String?) { _ = setUserId(userId: userId) }
    public func ampIdentify(userProperties: [String: Any]) { _ = identify(userProperties: userProperties, options: nil) }
    public func ampTrack(eventType: String, eventProperties: [String: Any]?) { _ = track(eventType: eventType, eventProperties: eventProperties, options: nil) }
    public func ampReset() { _ = reset() }
    public func ampFlush() { _ = flush() }
}

/// Forwards calls to Amplitude through `Amplitude-Swift`. Mirrors `iforevents_amplitude`.
public final class AmplitudeIntegration: BaseIntegration {
    private let client: AmplitudeClient

    /// Initializes the Amplitude SDK with the api key; autocapture stays off unless configured.
    public convenience init(apiKey: String, configure: ((Configuration) -> Void)? = nil, hooks: Hooks = Hooks()) {
        let configuration = Configuration(apiKey: apiKey)
        configure?(configuration)
        self.init(client: Amplitude(configuration: configuration), hooks: hooks)
    }

    /// Reuses an instance you already configured, or a fake in tests.
    public init(client: AmplitudeClient, hooks: Hooks = Hooks()) {
        self.client = client
        super.init(name: "AmplitudeIntegration", hooks: hooks)
    }

    public override func identify(_ event: IForevents.IdentifyEvent) throws {
        try super.identify(event)
        client.ampSetUserId(event.customId)
        client.ampIdentify(userProperties: Self.scalarize(event.traits))
    }

    public override func track(_ event: IForevents.TrackEvent) throws {
        try super.track(event)
        client.ampTrack(eventType: event.name, eventProperties: Self.scalarize(event.properties))
    }

    public override func page(_ event: IForevents.PageEvent) throws {
        try super.page(event)
        var props = event.properties
        if let v = event.navigationType { props["navigation_type"] = v }
        if let v = event.toRoute { props["to_route"] = v }
        if let v = event.previousRoute { props["previous_route"] = v }
        client.ampTrack(eventType: event.name, eventProperties: Self.scalarize(props))
    }

    public override func reset() throws {
        try super.reset()
        client.ampReset()
    }

    public override func flush() throws {
        client.ampFlush()
    }

    static func scalarize(_ properties: IForevents.Properties) -> [String: Any] {
        properties.filter { !($0.value is NSNull) }
    }
}
