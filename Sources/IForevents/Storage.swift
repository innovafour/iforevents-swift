import Foundation

/// Keeps the user id (and the queue when persisted) across launches.
public protocol Storage: AnyObject {
    func get(_ key: String) -> String?
    func set(_ key: String, _ value: String)
    func remove(_ key: String)
}

/// Nothing survives the process; for tests and servers.
public final class MemoryStorage: Storage {
    private var data: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func get(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return data[key]
    }

    public func set(_ key: String, _ value: String) {
        lock.lock(); defer { lock.unlock() }
        data[key] = value
    }

    public func remove(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        data[key] = nil
    }
}

/// The default on Apple platforms: `UserDefaults` (optionally an app-group suite).
public final class UserDefaultsStorage: Storage {
    private let defaults: UserDefaults
    private let prefix: String

    public init(defaults: UserDefaults = .standard, prefix: String = "com.iforevents.") {
        self.defaults = defaults
        self.prefix = prefix
    }

    public func get(_ key: String) -> String? { defaults.string(forKey: prefix + key) }
    public func set(_ key: String, _ value: String) { defaults.set(value, forKey: prefix + key) }
    public func remove(_ key: String) { defaults.removeObject(forKey: prefix + key) }
}
