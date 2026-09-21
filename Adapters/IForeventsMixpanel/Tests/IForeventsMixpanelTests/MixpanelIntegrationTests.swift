import XCTest
import IForevents
import Mixpanel
@testable import IForeventsMixpanel

final class MixpanelIntegrationTests: XCTestCase {
    final class Fake: MixpanelClient {
        var calls: [String] = []
        var lastTrack: [String: MixpanelType]?
        var lastPeople: [String: MixpanelType]?
        func mpIdentify(distinctId: String) { calls.append("identify:\(distinctId)") }
        func mpSetPeople(_ properties: [String: MixpanelType]) { calls.append("people"); lastPeople = properties }
        func mpTrack(event: String, properties: [String: MixpanelType]) { calls.append("track:\(event)"); lastTrack = properties }
        func mpReset() { calls.append("reset") }
        func mpFlush() { calls.append("flush") }
    }

    func testForwarding() {
        let fake = Fake()
        let ife = Iforevents(integrations: [MixpanelIntegration(client: fake)], context: { [:] })
        ife.initialize()
        ife.identify("u", traits: ["plan": "pro", "nested": ["x": 1]])
        ife.track("buy", properties: ["total": 9.5])
        ife.page("Home", navigationType: "load")
        ife.reset()
        ife.wait()
        XCTAssertEqual(fake.calls, ["identify:u", "people", "track:buy", "track:Home", "flush", "reset"])
        XCTAssertEqual(fake.lastPeople?["plan"] as? String, "pro")
        XCTAssertEqual(fake.lastPeople?["nested_x"] as? Int, 1)
        XCTAssertEqual(fake.lastTrack?["navigation_type"] as? String, "load")
    }

    func testRealInstanceConformsAndInitializes() throws {
        let integration = MixpanelIntegration(token: "test-token")
        try integration.initialize()
        try integration.track(TrackEvent(name: "x", properties: ["n": 1]))
    }
}
