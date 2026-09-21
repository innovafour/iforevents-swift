import Foundation

/// Implemented by every destination. Subclass `BaseIntegration` for defaults and hooks.
public protocol Integration: AnyObject {
    var name: String { get }
    func initialize() throws
    func identify(_ event: IdentifyEvent) throws
    func track(_ event: TrackEvent) throws
    func page(_ event: PageEvent) throws
    func reset() throws
    /// Sends anything buffered.
    func flush() throws
    /// Flushes and releases resources.
    func shutdown() throws
}

/// Optional callbacks fired before an integration handles a call.
public struct Hooks {
    public var onInit: (() -> Void)?
    public var onIdentify: ((IdentifyEvent) -> Void)?
    public var onTrack: ((TrackEvent) -> Void)?
    public var onPage: ((PageEvent) -> Void)?
    public var onReset: (() -> Void)?

    public init(onInit: (() -> Void)? = nil, onIdentify: ((IdentifyEvent) -> Void)? = nil, onTrack: ((TrackEvent) -> Void)? = nil, onPage: ((PageEvent) -> Void)? = nil, onReset: (() -> Void)? = nil) {
        self.onInit = onInit
        self.onIdentify = onIdentify
        self.onTrack = onTrack
        self.onPage = onPage
        self.onReset = onReset
    }
}

/// Defaults and hooks; mirrors the Flutter `Integration` base. Call `super` first in overrides.
open class BaseIntegration: Integration {
    public let name: String
    public let hooks: Hooks

    public init(name: String, hooks: Hooks = Hooks()) {
        self.name = name
        self.hooks = hooks
    }

    open func initialize() throws { hooks.onInit?() }
    open func identify(_ event: IdentifyEvent) throws { hooks.onIdentify?(event) }
    open func track(_ event: TrackEvent) throws { hooks.onTrack?(event) }
    open func page(_ event: PageEvent) throws { hooks.onPage?(event) }
    open func reset() throws { hooks.onReset?() }
    open func flush() throws {}
    open func shutdown() throws {}
}

/// Runs one integration call in isolation and reports the outcome.
public func safeExecute(_ integration: Integration, _ action: () throws -> Void) -> IntegrationResult {
    do {
        try action()
        return IntegrationResult(integration: integration.name, success: true, error: nil)
    } catch {
        return IntegrationResult(integration: integration.name, success: false, error: error)
    }
}
