import XCTest
import IForevents
import AmplitudeSwift
@testable import IForeventsAmplitude

final class AmplitudeIntegrationTests: XCTestCase {
    final class Fake: AmplitudeClient {
        var calls: [String] = []
        var lastProps: [String: Any]?
        func ampSetUserId(_ userId: String?) { calls.append("user:\(userId ?? "nil")") }
        func ampIdentify(userProperties: [String: Any]) { calls.append("identify"); lastProps = userProperties }
        func ampTrack(eventType: String, eventProperties: [String: Any]?) { calls.append("track:\(eventType)"); lastProps = eventProperties }
        func ampReset() { calls.append("reset") }
        func ampFlush() { calls.append("flush") }
    }

    func testForwarding() {
        let fake = Fake()
        let ife = Iforevents(integrations: [AmplitudeIntegration(client: fake)], context: { [:] })
        ife.initialize()
        ife.identify("u", traits: ["tier": "gold"])
        ife.track("buy", properties: ["total": 9])
        ife.page("Home")
        ife.flush()
        ife.reset()
        ife.wait()
        XCTAssertEqual(fake.calls, ["user:u", "identify", "track:buy", "track:Home", "flush", "reset"])
    }

    func testRealClientConformsAndInitializes() throws {
        let integration = AmplitudeIntegration(apiKey: "test-key") { $0.flushQueueSize = 1000 }
        try integration.initialize()
        try integration.track(IForevents.TrackEvent(name: "x"))
    }
}
