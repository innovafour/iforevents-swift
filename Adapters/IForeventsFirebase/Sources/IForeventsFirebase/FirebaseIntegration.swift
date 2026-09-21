import FirebaseAnalytics
import Foundation
import IForevents

/// Forwards calls to Firebase Analytics. Needs `FirebaseApp.configure()` in
/// the app. Event and parameter names are normalized to Firebase's rules
/// (letters, digits, underscores; 40 characters). Mirrors `iforevents_firebase`.
public final class FirebaseIntegration: BaseIntegration {
    public init(hooks: Hooks = Hooks()) {
        super.init(name: "FirebaseIntegration", hooks: hooks)
    }

    public override func identify(_ event: IdentifyEvent) throws {
        try super.identify(event)
        Analytics.setUserID(event.customId)
        for (k, v) in event.traits where !(v is NSNull) {
            Analytics.setUserProperty(String(String(describing: v).prefix(36)), forName: Self.sanitize(k, max: 24))
        }
    }

    public override func track(_ event: TrackEvent) throws {
        try super.track(event)
        Analytics.logEvent(Self.sanitize(event.name, max: 40), parameters: Self.parameters(event.properties))
    }

    public override func page(_ event: PageEvent) throws {
        try super.page(event)
        var params = Self.parameters(event.properties)
        params[AnalyticsParameterScreenName] = event.name
        if let v = event.navigationType { params["navigation_type"] = v }
        if let v = event.previousRoute { params["previous_route"] = v }
        Analytics.logEvent(AnalyticsEventScreenView, parameters: params)
    }

    public override func reset() throws {
        try super.reset()
        Analytics.setUserID(nil)
        Analytics.resetAnalyticsData()
    }

    static func parameters(_ properties: Properties) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in properties {
            let key = sanitize(k, max: 40)
            switch v {
            case is NSNull: continue
            case let n as NSNumber: out[key] = n
            case let s as String: out[key] = String(s.prefix(100))
            default: out[key] = String(String(describing: v).prefix(100))
            }
        }
        return out
    }

    static func sanitize(_ name: String, max: Int) -> String {
        let cleaned = name.map { $0.isLetter || $0.isNumber || $0 == "_" ? String($0) : "_" }.joined().trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let safe = cleaned.isEmpty || !(cleaned.first?.isLetter ?? false) ? "e_" + cleaned : cleaned
        return String(safe.prefix(max))
    }
}
