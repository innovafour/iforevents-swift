import XCTest
@testable import IForevents

/// Conformance suite for sdks/CONTRACT.md section 8; each test names its item.
final class ConformanceTests: XCTestCase {
    private var active: [IForeventsAPIIntegration] = []
    private let anon = try! NSRegularExpression(pattern: "^anon_[0-9a-f]{32}$")

    override func setUp() {
        super.setUp()
        MockAPI.reset()
    }

    override func tearDown() {
        for i in active { try? i.shutdown() }
        active = []
        super.tearDown()
    }

    private func make(_ configure: ((inout APIConfig) -> Void)? = nil) -> IForeventsAPIIntegration {
        var cfg = APIConfig(projectKey: "pk_test")
        cfg.baseUrl = MockAPI.baseUrl
        cfg.session = MockAPI.session
        cfg.storage = MemoryStorage()
        cfg.persistQueue = false
        cfg.retryDelay = 0.01
        cfg.flushInterval = 0.06
        configure?(&cfg)
        let i = IForeventsAPIIntegration(config: cfg)
        active.append(i)
        return i
    }

    private func boot(_ api: IForeventsAPIIntegration, extra: [Integration] = []) -> Iforevents {
        let ife = Iforevents(integrations: [api] + extra, context: { ["device_platform": "test", "sdk_name": "iforevents-swift"] })
        ife.initialize()
        ife.wait()
        return ife
    }

    private func isAnon(_ s: String?) -> Bool {
        guard let s = s else { return false }
        return anon.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private func names(_ r: MockAPI.Recorded) -> [String] {
        ((r.body["events"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
    }

    func test01_identifyLiftsFieldsSwitchesUserId() {
        let api = make()
        let ife = boot(api)
        ife.identify("user_1", traits: ["email": "ada@example.com", "name": "Ada", "phone_number": "+1", "plan": "pro", "nested": ["a": 1]])
        ife.wait()
        let req = MockAPI.byPath("/v1/events/identify")[0]
        XCTAssertEqual(req.header("X-Project-Key"), "pk_test")
        XCTAssertEqual(req.header("Content-Type"), "application/json")
        XCTAssertTrue(req.header("User-Agent")?.hasPrefix("iforevents-swift/") == true)
        XCTAssertEqual(req.header("X-User-Id"), "user_1")
        XCTAssertEqual(req.body["custom_id"] as? String, "user_1")
        XCTAssertEqual(req.body["email"] as? String, "ada@example.com")
        XCTAssertEqual(req.body["name"] as? String, "Ada")
        XCTAssertEqual(req.body["phone_number"] as? String, "+1")
        let props = req.body["properties"] as? [String: Any]
        XCTAssertEqual(props?["plan"] as? String, "pro")
        XCTAssertEqual(props?["nested_a"] as? Int, 1)
        XCTAssertEqual(props?["device_platform"] as? String, "test")
        XCTAssertNil(props?["email"])
        XCTAssertEqual(api.userId, "user_1")
        XCTAssertTrue(api.isIdentified)
    }

    func test02_trackAfterIdentifyCarriesUserIdAndTraits() {
        let ife = boot(make { $0.batchSize = 1 })
        ife.identify("user_1", traits: ["plan": "pro"])
        ife.track("clicked", properties: ["button": "buy", "plan": "override"])
        ife.wait()
        let req = MockAPI.byPath("/v1/events/track")[0]
        XCTAssertEqual(req.header("X-User-Id"), "user_1")
        XCTAssertEqual(req.body["event_name"] as? String, "clicked")
        XCTAssertEqual(req.body["event_type"] as? String, "track")
        let props = req.body["properties"] as? [String: Any]
        XCTAssertEqual(props?["plan"] as? String, "override")
        XCTAssertEqual(props?["button"] as? String, "buy")
        XCTAssertEqual(props?["device_platform"] as? String, "test")
    }

    func test03_batchSizeNSendsOnNth() {
        let ife = boot(make { $0.batchSize = 3; $0.flushInterval = 10 })
        ife.track("a"); ife.track("b"); ife.wait()
        XCTAssertEqual(MockAPI.requests.count, 0)
        ife.track("c"); ife.wait()
        let batches = MockAPI.byPath("/v1/events/batch")
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(names(batches[0]), ["a", "b", "c"])
        let first = (batches[0].body["events"] as? [[String: Any]])?.first
        XCTAssertEqual(first?["type"] as? String, "track")
        XCTAssertTrue((first?["created_at"] as? String)?.hasSuffix("Z") == true)
    }

    func test04_flushIntervalSendsPartialQueue() {
        let ife = boot(make { $0.batchSize = 50; $0.flushInterval = 0.05 })
        ife.track("only"); ife.wait()
        XCTAssertEqual(MockAPI.requests.count, 0)
        let exp = expectation(description: "timer flush")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(MockAPI.byPath("/v1/events/batch").count, 1)
    }

    func test05_batchSize1PostsTrack() {
        let ife = boot(make { $0.batchSize = 1 })
        ife.track("solo", properties: ["n": 1]); ife.wait()
        let req = MockAPI.byPath("/v1/events/track")[0]
        XCTAssertEqual(req.body["event_name"] as? String, "solo")
        XCTAssertEqual(req.body["event_type"] as? String, "track")
    }

    func test06_pageViewTypeAndNavigation() {
        let ife = boot(make { $0.batchSize = 1 })
        ife.page("/pricing", properties: ["title": "Pricing"], navigationType: "push", previousRoute: "/"); ife.wait()
        let req = MockAPI.byPath("/v1/events/track")[0]
        XCTAssertEqual(req.body["event_name"] as? String, "/pricing")
        XCTAssertEqual(req.body["event_type"] as? String, "page_view")
        let props = req.body["properties"] as? [String: Any]
        XCTAssertEqual(props?["title"] as? String, "Pricing")
        XCTAssertEqual(props?["navigation_type"] as? String, "push")
        XCTAssertEqual(props?["previous_route"] as? String, "/")
    }

    func test07_anonymousIdGeneratedPersistedReused() {
        let storage = MemoryStorage()
        let api = make { $0.batchSize = 1; $0.storage = storage }
        let ife = boot(api)
        ife.track("first"); ife.track("second"); ife.wait()
        let reqs = MockAPI.byPath("/v1/events/track")
        let anonId = reqs[0].header("X-User-Id")
        XCTAssertTrue(isAnon(anonId), anonId ?? "nil")
        XCTAssertEqual(reqs[1].header("X-User-Id"), anonId)
        XCTAssertEqual(api.userId, anonId)
        XCTAssertFalse(api.isIdentified)
        XCTAssertEqual(storage.get("iforevents_user_id"), anonId)
        XCTAssertEqual(storage.get("iforevents_user_identified"), "false")
        let again = make { $0.storage = storage }
        try? again.initialize()
        XCTAssertEqual(again.userId, anonId)
        let other = make()
        try? other.initialize()
        XCTAssertTrue(isAnon(other.userId))
        XCTAssertNotEqual(other.userId, anonId)
    }

    func test08_resetFlushesThenFreshAnonymousId() {
        let storage = MemoryStorage()
        let api = make { $0.batchSize = 10; $0.flushInterval = 10; $0.storage = storage }
        let ife = boot(api)
        ife.identify("user_1"); ife.track("before_logout"); ife.reset(); ife.wait()
        let batches = MockAPI.byPath("/v1/events/batch")
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches[0].header("X-User-Id"), "user_1")
        XCTAssertTrue(isAnon(api.userId))
        XCTAssertFalse(api.isIdentified)
        XCTAssertEqual(storage.get("iforevents_user_id"), api.userId)
        XCTAssertTrue(ife.currentTraits.isEmpty)
        ife.track("after_logout"); ife.flush(); ife.wait()
        let after = MockAPI.byPath("/v1/events/batch")[1].header("X-User-Id")
        XCTAssertEqual(after, api.userId)
        XCTAssertNotEqual(after, "user_1")
    }

    func test09_500Then200RetriesSameEventsOnce() {
        var failures = 0
        MockAPI.scenario = { req in
            if req.path == "/v1/events/batch" && failures < 1 { failures += 1; return (500, ["error": "boom"], [:]) }
            return nil
        }
        let ife = boot(make { $0.batchSize = 2; $0.maxRetries = 2 })
        ife.track("x"); ife.track("y"); ife.flush(); ife.wait()
        let batches = MockAPI.byPath("/v1/events/batch")
        XCTAssertEqual(batches.count, 2)
        XCTAssertEqual(names(batches[1]), ["x", "y"])
    }

    func test10_quotaExceededNoRetryDropCallbackOnce() {
        var refuse = true
        MockAPI.scenario = { req in
            if req.path == "/v1/events/batch" && refuse {
                return (429, ["error": "quota_exceeded", "message": "plan quota exhausted", "limit": 5_000_000, "used": 5_000_001, "org_uuid": "org-1"], [:])
            }
            return nil
        }
        var seen: [IForeventsAPIError] = []
        let api = make { $0.batchSize = 500; $0.onQuotaExceeded = { seen.append($0) } }
        let ife = boot(api)
        ife.track("a"); ife.flush(); ife.track("b"); ife.flush(); ife.wait()
        XCTAssertEqual(MockAPI.byPath("/v1/events/batch").count, 2)
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.limit, 5_000_000)
        XCTAssertEqual(seen.first?.used, 5_000_001)
        XCTAssertEqual(seen.first?.organizationUuid, "org-1")
        XCTAssertTrue(api.isQuotaExceeded)
        XCTAssertEqual(api.queuedEvents, 0)
        refuse = false
        ife.track("c"); ife.flush(); ife.wait()
        XCTAssertFalse(api.isQuotaExceeded)
        XCTAssertEqual(names(MockAPI.byPath("/v1/events/batch").last!), ["c"])
    }

    func test11_rateLimitRetryAfterHonored() {
        var limited = true
        MockAPI.scenario = { req in
            if req.path == "/v1/events/batch" && limited { limited = false; return (429, ["error": "ingest_rate_limit_exceeded", "retry_after_seconds": 1], ["Retry-After": "1"]) }
            return nil
        }
        var errors: [IForeventsAPIError] = []
        let ife = boot(make { $0.batchSize = 500; $0.onError = { errors.append($0) } })
        ife.track("r")
        let started = Date()
        ife.flush(); ife.wait()
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.95)
        XCTAssertEqual(MockAPI.byPath("/v1/events/batch").count, 2)
        XCTAssertTrue(errors.isEmpty)
    }

    func test11b_rateLimitErrorTypedWhenRetriesExhausted() {
        MockAPI.scenario = { req in req.path == "/v1/events/identify" ? (429, ["error": "ingest_rate_limit_exceeded"], ["Retry-After": "0"]) : nil }
        var errors: [IForeventsAPIError] = []
        let ife = boot(make { $0.maxRetries = 1; $0.onError = { errors.append($0) } })
        ife.identify("u"); ife.wait()
        XCTAssertEqual(MockAPI.byPath("/v1/events/identify").count, 2)
        XCTAssertEqual(errors.first?.kind, .rateLimited)
    }

    func test12_401NoRetryDropAuthError() {
        var errors: [IForeventsAPIError] = []
        let api = make { $0.projectKey = "pk_wrong"; $0.batchSize = 500; $0.onError = { errors.append($0) } }
        let ife = Iforevents(integrations: [api])
        ife.initialize()
        ife.track("a"); ife.flush(); ife.wait()
        XCTAssertEqual(MockAPI.byPath("/v1/events/batch").count, 1)
        XCTAssertEqual(api.queuedEvents, 0)
        XCTAssertEqual(errors.first?.kind, .auth)
        XCTAssertEqual(errors.first?.status, 401)
    }

    func test13_throwingIntegrationDoesNotStopApi() {
        final class Broken: BaseIntegration {
            struct Down: Error {}
            init() { super.init(name: "Broken") }
            override func track(_ event: TrackEvent) throws { try super.track(event); throw Down() }
        }
        let api = make { $0.batchSize = 1 }
        let ife = Iforevents(integrations: [Broken(), api])
        ife.initialize()
        var results: [IntegrationResult] = []
        ife.track("still_delivered") { results = $0 }
        ife.wait()
        XCTAssertEqual(results.map { $0.integration }, ["Broken", "IForeventsAPIIntegration"])
        XCTAssertEqual(results.map { $0.success }, [false, true])
        XCTAssertEqual(MockAPI.byPath("/v1/events/track").count, 1)
    }

    func test14_noSecretAnywhere() {
        let ife = boot(make { $0.batchSize = 1 })
        ife.identify("u", traits: ["plan": "pro"]); ife.track("t"); ife.page("/p"); ife.wait()
        for r in MockAPI.requests {
            XCTAssertFalse(String(describing: r.body).lowercased().contains("secret"))
            XCTAssertFalse(r.headers.keys.joined(separator: ",").lowercased().contains("secret"))
        }
    }

    func test15_flatten() {
        let flat = flatten(["a": ["b": ["c": 1]], "list": [1, 2], "plain": "x"])
        XCTAssertEqual(flat["a_b_c"] as? Int, 1)
        XCTAssertEqual(flat["list"] as? [Int], [1, 2])
        XCTAssertEqual(flat["plain"] as? String, "x")
        XCTAssertNil(flat["a"])
    }

    func testQueuePersistsAcrossRestarts() throws {
        let storage = MemoryStorage()
        let first = make { $0.batchSize = 100; $0.flushInterval = 10; $0.storage = storage; $0.persistQueue = true }
        try first.initialize()
        try first.track(TrackEvent(name: "offline"))
        XCTAssertTrue(storage.get("iforevents_queue")?.contains("offline") == true)
        let second = make { $0.batchSize = 100; $0.flushInterval = 10; $0.storage = storage; $0.persistQueue = true }
        try second.initialize()
        XCTAssertEqual(second.queuedEvents, 1)
        try second.flush()
        XCTAssertEqual(MockAPI.byPath("/v1/events/batch").count, 1)
        XCTAssertNil(storage.get("iforevents_queue"))
    }

    func testCallsBeforeInitializeIgnored() {
        let ife = Iforevents(integrations: [make()])
        var results: [IntegrationResult] = [IntegrationResult(integration: "x", success: true, error: nil)]
        ife.track("early") { results = $0 }
        ife.wait()
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(MockAPI.requests.count, 0)
    }

    func testIdentifyAttributesEvenWhenProfileRequestFails() {
        MockAPI.scenario = { req in req.path == "/v1/events/identify" ? (500, ["error": "down"], [:]) : nil }
        let api = make { $0.batchSize = 1; $0.maxRetries = 0 }
        let ife = boot(api)
        ife.identify("user_x"); ife.track("still_attributed"); ife.wait()
        XCTAssertEqual(api.userId, "user_x")
        XCTAssertEqual(MockAPI.byPath("/v1/events/track")[0].header("X-User-Id"), "user_x")
    }

    func testThrowOnErrorSurfacesInResultsAndRecovers() throws {
        MockAPI.scenario = { _ in (500, ["error": "down"], [:]) }
        let api = make { $0.maxRetries = 0; $0.throwOnError = true; $0.batchSize = 500 }
        let ife = boot(api)
        var results: [IntegrationResult] = []
        ife.identify("u") { results = $0 }
        ife.wait()
        XCTAssertFalse(results[0].success)
        XCTAssertEqual((results[0].error as? IForeventsAPIError)?.message, "down")
        ife.track("x"); ife.wait()
        XCTAssertThrowsError(try api.flush())
        MockAPI.scenario = nil
        try api.flush()
        XCTAssertEqual(names(MockAPI.byPath("/v1/events/batch").last!).count, 1)
    }

    func testConcurrentTracksAllDelivered() {
        let api = make { $0.batchSize = 7; $0.flushInterval = 10 }
        let ife = boot(api)
        DispatchQueue.concurrentPerform(iterations: 8) { i in
            for n in 0..<20 { ife.track("t", properties: ["i": i, "n": n]) }
        }
        ife.flush(); ife.wait()
        let total = MockAPI.byPath("/v1/events/batch").reduce(0) { $0 + names($1).count }
        XCTAssertEqual(total, 160)
        XCTAssertEqual(api.queuedEvents, 0)
    }

    func testDeviceContextHasContractKeys() {
        let ctx = DeviceContext.collect(extra: ["app": "demo"])
        for key in ["sdk_name", "sdk_version", "runtime", "device_platform", "device_brand", "device_model", "device_os_version", "device_app_version"] {
            XCTAssertNotNil(ctx[key], key)
        }
        XCTAssertEqual(ctx["app"] as? String, "demo")
    }
}
