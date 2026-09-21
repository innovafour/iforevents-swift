import XCTest
import IForevents

/// Real-api smoke: runs only with IFOREVENTS_PROJECT_KEY (and optionally IFOREVENTS_BASE_URL) set.
final class SmokeTests: XCTestCase {
    func testIngestsIntoRealApi() throws {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["IFOREVENTS_PROJECT_KEY"], !key.isEmpty else { throw XCTSkip("IFOREVENTS_PROJECT_KEY not set") }
        var errors: [IForeventsAPIError] = []
        let api = IForeventsAPIIntegration(projectKey: key) {
            $0.baseUrl = env["IFOREVENTS_BASE_URL"] ?? "https://api.iforevents.com"
            $0.batchSize = 2
            $0.storage = MemoryStorage()
            $0.onError = { errors.append($0) }
        }
        let ife = Iforevents(integrations: [api])
        ife.initialize()
        var identify: [IntegrationResult] = []
        ife.identify("smoke_swift_\(Int(Date().timeIntervalSince1970))", traits: ["email": "smoke@example.com", "plan": "free", "nested": ["deep": true]]) { identify = $0 }
        ife.track("smoke_track", properties: ["n": 1])
        ife.page("/smoke")
        ife.shutdown()
        ife.wait()
        print("smoke: identify=\(identify.first?.success ?? false) user_id=\(api.userId ?? "nil") queued=\(api.queuedEvents) errors=\(errors)")
        XCTAssertTrue(identify.first?.success == true)
        XCTAssertTrue(errors.isEmpty, "\(errors)")
        XCTAssertEqual(api.queuedEvents, 0)
        XCTAssertTrue(api.userId?.hasPrefix("smoke_swift_") == true)
    }
}
