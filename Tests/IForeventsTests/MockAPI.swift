import Foundation
@testable import IForevents

/// Records every request the SDK makes and answers like the real api; a
/// scenario hook injects faults. Installed through `URLProtocol`, so no
/// sockets are involved.
final class MockAPI: URLProtocol {
    struct Recorded {
        let path: String
        let headers: [String: String]
        let body: [String: Any]
        func header(_ name: String) -> String? { headers.first { $0.key.lowercased() == name.lowercased() }?.value }
    }

    typealias Scenario = (Recorded) -> (status: Int, body: [String: Any], headers: [String: String])?

    static let lock = NSLock()
    static var requests: [Recorded] = []
    static var scenario: Scenario?
    static let baseUrl = "http://mock.iforevents.test"

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        requests = []
        scenario = nil
    }

    static func byPath(_ path: String) -> [Recorded] {
        lock.lock(); defer { lock.unlock() }
        return requests.filter { $0.path == path }
    }

    static var session: URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockAPI.self]
        return URLSession(configuration: cfg)
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "mock.iforevents.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let bodyData = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
            stream.open(); defer { stream.close() }
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let n = stream.read(buffer, maxLength: 4096)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            return data
        } ?? Data()
        let body = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:]
        let rec = Recorded(path: request.url?.path ?? "", headers: request.allHTTPHeaderFields ?? [:], body: body)
        MockAPI.lock.lock()
        MockAPI.requests.append(rec)
        let scenario = MockAPI.scenario
        MockAPI.lock.unlock()

        let answer: (status: Int, body: [String: Any], headers: [String: String])
        if let injected = scenario?(rec) {
            answer = injected
        } else if rec.header("X-Project-Key") != "pk_test" {
            answer = (401, ["error": "invalid project key"], [:])
        } else {
            switch rec.path {
            case "/v1/events/identify": answer = (201, ["user": ["uuid": "11111111-1111-4111-8111-111111111111"]], [:])
            case "/v1/events/track": answer = (201, ["status": "ok", "user_uuid": "22222222-2222-4222-8222-222222222222"], [:])
            case "/v1/events/batch": answer = (202, ["status": "queued", "user_uuid": "33333333-3333-4333-8333-333333333333"], [:])
            default: answer = (404, ["error": "not found"], [:])
            }
        }
        var headers = answer.headers
        headers["Content-Type"] = "application/json"
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: answer.body))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
