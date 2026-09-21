import Foundation

/// Configuration of the first-party API integration.
///
/// Only `projectKey` is required. It is a public write key: it grants event
/// ingestion and nothing else, so shipping it in an app is safe. There is
/// deliberately no project secret here.
public struct APIConfig {
    public var projectKey: String
    public var baseUrl: String = "https://api.iforevents.com"
    /// Events per request (1...500); 1 disables batching.
    public var batchSize: Int = 10
    /// Seconds a partial batch waits.
    public var flushInterval: TimeInterval = 5
    public var timeout: TimeInterval = 10
    public var maxRetries: Int = 3
    public var retryDelay: TimeInterval = 1
    public var requeueFailedEvents: Bool = true
    public var debug: Bool = false
    /// Report request errors through the `IntegrationResult` instead of only `onError`.
    public var throwOnError: Bool = false
    public var onQuotaExceeded: ((IForeventsAPIError) -> Void)?
    public var onError: ((IForeventsAPIError) -> Void)?
    public var storage: Storage = UserDefaultsStorage()
    /// Store the pending queue so unsent events survive a restart. Default true on Apple platforms.
    public var persistQueue: Bool = true
    public var maxQueueSize: Int = 1000
    public var userAgent: String?
    public var session: URLSession = .shared
    public var hooks = Hooks()

    public init(projectKey: String) {
        self.projectKey = projectKey
    }
}

/// Talks to the IForevents ingest api: identify, single or batched track,
/// page views, a client-owned user id in `X-User-Id`, retries with
/// `Retry-After` and typed errors. Every method runs on the caller's queue
/// (the facade uses a private serial queue). Mirrors
/// `IForeventsAPIIntegration` of the Flutter package.
public final class IForeventsAPIIntegration: BaseIntegration {
    private static let userKey = "iforevents_user_id"
    private static let identifiedKey = "iforevents_user_identified"
    private static let queueKey = "iforevents_queue"
    private static let maxBatch = 500

    public let config: APIConfig
    private let baseUrl: String
    private let userAgent: String
    private let lock = NSRecursiveLock()
    private var queue: [[String: Any]] = []
    private var timer: DispatchWorkItem?
    private let timerQueue = DispatchQueue(label: "com.iforevents.api.timer")
    private var _userId: String?
    private var _identified = false
    private var _initialized = false
    private var _quotaExceeded = false

    public init(config: APIConfig) {
        var cfg = config
        cfg.batchSize = max(1, min(IForeventsAPIIntegration.maxBatch, cfg.batchSize))
        self.config = cfg
        self.baseUrl = cfg.baseUrl.hasSuffix("/") ? String(cfg.baseUrl.dropLast()) : cfg.baseUrl
        let os = ProcessInfo.processInfo.operatingSystemVersion
        self.userAgent = cfg.userAgent ?? "\(SDK.name)/\(SDK.version) (\(os.majorVersion).\(os.minorVersion).\(os.patchVersion))"
        super.init(name: "IForeventsAPIIntegration", hooks: cfg.hooks)
    }

    public convenience init(projectKey: String, configure: ((inout APIConfig) -> Void)? = nil) {
        var cfg = APIConfig(projectKey: projectKey)
        configure?(&cfg)
        self.init(config: cfg)
    }

    // MARK: state

    public var isInitialized: Bool { lock.lock(); defer { lock.unlock() }; return _initialized }
    public var isIdentified: Bool { lock.lock(); defer { lock.unlock() }; return _identified }
    /// The id every request carries in `X-User-Id`: a generated `anon_...` id kept per install, or the customId of the last identify.
    public var userId: String? { lock.lock(); defer { lock.unlock() }; return _userId }
    public var queuedEvents: Int { lock.lock(); defer { lock.unlock() }; return queue.count }
    /// True after a `quota_exceeded` answer until the next accepted request.
    public var isQuotaExceeded: Bool { lock.lock(); defer { lock.unlock() }; return _quotaExceeded }

    /// A fresh anonymous id, unrelated to anything the server derives: `anon_<uuid4 without dashes>`.
    public static func anonymousId() -> String {
        "anon_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    // MARK: Integration

    public override func initialize() throws {
        try super.initialize()
        lock.lock(); defer { lock.unlock() }
        if let stored = config.storage.get(Self.userKey), !stored.isEmpty {
            _userId = stored
            _identified = config.storage.get(Self.identifiedKey) == "true"
        } else {
            // A fresh install: attribute everything to an anonymous id we own, so the
            // api never has to fingerprint the address (which merges users behind a NAT).
            setUserLocked(Self.anonymousId(), identified: false)
        }
        if config.persistQueue, let raw = config.storage.get(Self.queueKey), let data = raw.data(using: .utf8) {
            if let events = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]], !events.isEmpty {
                queue = events + queue
                trimLocked()
                scheduleLocked()
            } else {
                config.storage.remove(Self.queueKey)
            }
        }
        _initialized = true
        debug("api integration ready base_url=\(baseUrl) batch_size=\(config.batchSize)")
    }

    public override func identify(_ event: IdentifyEvent) throws {
        try super.identify(event)
        var properties = event.traits
        var body: [String: Any] = ["custom_id": event.customId]
        for key in ["email", "name", "phone_number"] {
            if let v = properties[key] as? String, !v.isEmpty {
                body[key] = v
                properties[key] = nil
            }
        }
        body["properties"] = properties
        // Attribute from now on, even if the profile request itself fails: the
        // api creates the profile on the first event it sees for this id.
        setUser(event.customId, identified: true)
        do {
            _ = try request("/v1/events/identify", body: body)
        } catch let error as IForeventsAPIError {
            report(error)
            if config.throwOnError { throw error }
        }
    }

    public override func track(_ event: TrackEvent) throws {
        try super.track(event)
        let queued: [String: Any] = ["name": event.name, "type": event.type.rawValue, "properties": event.properties, "created_at": ISO8601.string(event.timestamp)]
        if config.batchSize <= 1 {
            do {
                _ = try request("/v1/events/track", body: ["event_name": event.name, "event_type": event.type.rawValue, "properties": event.properties])
            } catch let error as IForeventsAPIError {
                report(error)
                if config.throwOnError { throw error }
            }
            return
        }
        lock.lock()
        queue.append(queued)
        trimLocked()
        let full = queue.count >= config.batchSize
        persistLocked()
        if !full { scheduleLocked() }
        lock.unlock()
        if full { try flush() }
    }

    public override func page(_ event: PageEvent) throws {
        try super.page(event)
        var props = event.properties
        if let v = event.navigationType { props["navigation_type"] = v }
        if let v = event.toRoute { props["to_route"] = v }
        if let v = event.previousRoute { props["previous_route"] = v }
        try track(TrackEvent(name: event.name, type: .pageView, properties: props, timestamp: event.timestamp))
    }

    public override func reset() throws {
        try super.reset()
        defer {
            // Forget the person; the next events belong to a fresh anonymous id.
            setUser(Self.anonymousId(), identified: false)
        }
        try flush()
    }

    /// Sends the whole queue now, 500 events per request. Blocks until done.
    public override func flush() throws {
        cancelTimer()
        while true {
            lock.lock()
            if queue.isEmpty { lock.unlock(); return }
            let n = min(Self.maxBatch, queue.count)
            let events = Array(queue[0..<n])
            queue.removeFirst(n)
            lock.unlock()
            do {
                _ = try request("/v1/events/batch", body: ["events": events])
                lock.lock(); persistLocked(); lock.unlock()
            } catch let error as IForeventsAPIError {
                lock.lock()
                if error.isRetryable && config.requeueFailedEvents {
                    // Transient: keep these events at the front for the next flush.
                    queue.insert(contentsOf: events, at: 0)
                    scheduleLocked()
                } else if !error.isRetryable {
                    // A refused key or an exhausted quota fails the same way forever: drop everything.
                    queue.removeAll()
                }
                persistLocked()
                lock.unlock()
                report(error)
                if config.throwOnError { throw error }
                return
            }
        }
    }

    public override func shutdown() throws {
        defer { cancelTimer() }
        try flush()
    }

    // MARK: internals

    private func trimLocked() {
        let over = queue.count - config.maxQueueSize
        if over > 0 { queue.removeFirst(over) }
    }

    private func scheduleLocked() {
        guard timer == nil, !queue.isEmpty else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); self.timer = nil; self.lock.unlock()
            try? self.flush()
        }
        timer = item
        timerQueue.asyncAfter(deadline: .now() + config.flushInterval, execute: item)
    }

    private func cancelTimer() {
        lock.lock(); defer { lock.unlock() }
        timer?.cancel()
        timer = nil
    }

    private func persistLocked() {
        guard config.persistQueue else { return }
        if queue.isEmpty {
            config.storage.remove(Self.queueKey)
        } else if let data = try? JSONSerialization.data(withJSONObject: queue), let raw = String(data: data, encoding: .utf8) {
            config.storage.set(Self.queueKey, raw)
        }
    }

    private func setUser(_ id: String, identified: Bool) {
        lock.lock(); defer { lock.unlock() }
        setUserLocked(id, identified: identified)
    }

    private func setUserLocked(_ id: String, identified: Bool) {
        _userId = id
        _identified = identified
        config.storage.set(Self.userKey, id)
        config.storage.set(Self.identifiedKey, identified ? "true" : "false")
    }

    private func report(_ error: IForeventsAPIError) {
        debug("request failed: \(error)")
        config.onError?(error)
    }

    private func noteOutcome(_ error: IForeventsAPIError?) {
        lock.lock(); defer { lock.unlock() }
        if let error = error {
            if error.kind == .quotaExceeded, !_quotaExceeded {
                _quotaExceeded = true
                config.onQuotaExceeded?(error)
            }
        } else {
            _quotaExceeded = false
        }
    }

    private func debug(_ message: String) {
        if config.debug { FileHandle.standardError.write("[iforevents] \(message)\n".data(using: .utf8)!) }
    }

    /// POSTs JSON with retries; returns the decoded body.
    func request(_ path: String, body: [String: Any]) throws -> [String: Any] {
        let payload = try sanitizedJSON(body)
        let uid = userId
        var attempt = 0
        while true {
            do {
                let res = try once(path, payload: payload, userId: uid)
                noteOutcome(nil)
                return res
            } catch let error as IForeventsAPIError {
                if !error.isRetryable || attempt >= config.maxRetries {
                    noteOutcome(error)
                    throw error
                }
                var delay = config.retryDelay * Double(attempt + 1)
                if error.kind == .rateLimited, let wait = error.retryAfter, wait > 0 { delay = wait }
                debug("retrying \(path) in \(delay)s (\(attempt + 1)/\(config.maxRetries))")
                Thread.sleep(forTimeInterval: delay)
                attempt += 1
            }
        }
    }

    private func once(_ path: String, payload: Data, userId: String?) throws -> [String: Any] {
        guard let url = URL(string: baseUrl + path) else { throw IForeventsAPIError.transient("bad url \(baseUrl + path)") }
        var req = URLRequest(url: url, timeoutInterval: config.timeout)
        req.httpMethod = "POST"
        req.httpBody = payload
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.projectKey, forHTTPHeaderField: "X-Project-Key")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let uid = userId, !uid.isEmpty { req.setValue(uid, forHTTPHeaderField: "X-User-Id") }

        let semaphore = DispatchSemaphore(value: 0)
        var result: (Data?, URLResponse?, Error?) = (nil, nil, nil)
        config.session.dataTask(with: req) { data, response, error in
            result = (data, response, error)
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let error = result.2 { throw IForeventsAPIError.transient(error.localizedDescription, underlying: error) }
        guard let http = result.1 as? HTTPURLResponse else { throw IForeventsAPIError.transient("no http response") }
        debug("POST \(path) -> \(http.statusCode)")
        if (200..<300).contains(http.statusCode) {
            return (result.0.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        }
        throw IForeventsAPIError.classify(status: http.statusCode, body: result.0, retryAfterHeader: http.allHeaderFields["Retry-After"] as? String)
    }

    /// JSONSerialization rejects Date and non-JSON values; coerce them to strings.
    private func sanitizedJSON(_ body: [String: Any]) throws -> Data {
        func clean(_ value: Any) -> Any {
            switch value {
            case let dict as [String: Any]: return dict.mapValues(clean)
            case let array as [Any]: return array.map(clean)
            case let date as Date: return ISO8601.string(date)
            case let url as URL: return url.absoluteString
            case is String, is NSNumber, is NSNull: return value
            default: return String(describing: value)
            }
        }
        return try JSONSerialization.data(withJSONObject: clean(body))
    }
}
