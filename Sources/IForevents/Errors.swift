import Foundation

/// A request failed after retries. Every api failure body is
/// `{"error": <code or message>, "message"?: ...}`. `.auth` and
/// `.quotaExceeded` are permanent: their events are dropped, not re-queued.
public struct IForeventsAPIError: Error, CustomStringConvertible {
    public enum Kind {
        /// Network failure, timeout or 5xx: retried.
        case transient
        /// Project key unknown, rotated or project disabled (401/403).
        case auth
        /// Monthly plan quota exhausted (429 `quota_exceeded`).
        case quotaExceeded
        /// Too many requests in a short window (429 without a quota code); retried after `retryAfter`.
        case rateLimited
        /// Any other 4xx.
        case other
    }

    public let kind: Kind
    public let status: Int
    public let code: String?
    public let message: String
    public let details: [String: Any]?
    public let underlying: Error?
    /// Server-suggested wait for `.rateLimited`.
    public let retryAfter: TimeInterval?
    /// Plan limit, events used and organization for `.quotaExceeded`.
    public let limit: Int?
    public let used: Int?
    public let organizationUuid: String?

    public var isRetryable: Bool {
        switch kind {
        case .transient, .rateLimited: return true
        case .auth, .quotaExceeded, .other: return false
        }
    }

    public var description: String { "IForeventsAPIError(\(kind), status \(status)): \(message)" }

    static func transient(_ message: String, underlying: Error? = nil) -> IForeventsAPIError {
        IForeventsAPIError(kind: .transient, status: 0, code: nil, message: message, details: nil, underlying: underlying, retryAfter: nil, limit: nil, used: nil, organizationUuid: nil)
    }

    static func classify(status: Int, body: Data?, retryAfterHeader: String?) -> IForeventsAPIError {
        let details = body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let code = details?["error"] as? String
        let message = (details?["message"] as? String) ?? code ?? "request failed with status \(status)"
        if status == 429 && code == "quota_exceeded" {
            return IForeventsAPIError(kind: .quotaExceeded, status: status, code: code, message: message, details: details, underlying: nil, retryAfter: nil, limit: asInt(details?["limit"]), used: asInt(details?["used"]), organizationUuid: details?["org_uuid"] as? String)
        }
        if status == 429 {
            var wait = retryAfterHeader.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if wait == nil, let seconds = asInt(details?["retry_after_seconds"]) { wait = Double(seconds) }
            return IForeventsAPIError(kind: .rateLimited, status: status, code: code, message: message, details: details, underlying: nil, retryAfter: wait, limit: nil, used: nil, organizationUuid: nil)
        }
        if status == 401 || status == 403 {
            return IForeventsAPIError(kind: .auth, status: status, code: code, message: message, details: details, underlying: nil, retryAfter: nil, limit: nil, used: nil, organizationUuid: nil)
        }
        return IForeventsAPIError(kind: status >= 500 ? .transient : .other, status: status, code: code, message: message, details: details, underlying: nil, retryAfter: nil, limit: nil, used: nil, organizationUuid: nil)
    }

    private static func asInt(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String { return Int(s) }
        return nil
    }
}
