> **Moved.** This SDK now lives in [innovafour/iforevents-sdks](https://github.com/innovafour/iforevents-sdks/tree/main/swift). This repository is archived.

# IForevents SDK for Swift

The IForevents analytics SDK for iOS, macOS, tvOS and watchOS. One facade,
pluggable integrations, a first-party API integration with batching, an
offline queue in `UserDefaults`, retries and typed errors, and the public
**project key** as the only credential. Same philosophy as the Flutter package.

```swift
// Package.swift
.package(url: "https://github.com/innovafour/iforevents-swift.git", from: "0.1.0")
```

```swift
import IForevents

let analytics = Iforevents(integrations: [
    IForeventsAPIIntegration(projectKey: "pk_...") { $0.batchSize = 20 },
])
analytics.initialize()

analytics.identify("user_123", traits: ["email": "ada@example.com", "plan": "pro"])
analytics.track("purchase_completed", properties: ["total": 9.99])
analytics.screen("Checkout", previousRoute: "Cart")
analytics.reset() // logout
```

Every call runs on the SDK's serial queue and returns immediately; pass a
`completion` to observe the `[IntegrationResult]`. Call `flush()` from
`applicationDidEnterBackground` if you want the queue drained early.

> **Credentials.** The project key is a public write key: it grants event
> ingestion and nothing else, so shipping it in the app is safe. There is no
> project secret in the SDK.

## Identity

Every request carries `X-User-Id`: a generated `anon_...` id kept per
install in `UserDefaults`, replaced by your own id on `identify`. The api
creates the profile on first sight; identify only adds traits. `reset()`
switches to a fresh anonymous id.

## Adapters (separate packages under `Adapters/`)

| Package | Vendor |
|---------|--------|
| `IForeventsMixpanel` | `mixpanel-swift` |
| `IForeventsAmplitude` | `Amplitude-Swift` |
| `IForeventsFirebase` | `firebase-ios-sdk` (FirebaseAnalytics) |

```swift
import IForeventsMixpanel
let analytics = Iforevents(integrations: [api, MixpanelIntegration(token: "...")])
```

Each adapter takes a small protocol (`MixpanelClient`, `AmplitudeClient`) so
you can pass an instance you configured yourself, or a fake in tests.

## APIConfig

| Field | Default | Meaning |
|-------|---------|---------|
| `baseUrl` | `https://api.iforevents.com` | api origin (self-hosted: your host) |
| `batchSize` | `10` | events per request; 1 disables batching; max 500 |
| `flushInterval` | `5` s | how long a partial batch waits |
| `timeout` | `10` s | per request |
| `maxRetries` / `retryDelay` | `3` / `1` s | linear backoff, `Retry-After` honored |
| `requeueFailedEvents` | `true` | keep events after transient failures |
| `storage` / `persistQueue` | `UserDefaultsStorage()` / `true` | user id and queue survive restarts |
| `throwOnError` | `false` | report request errors in the `IntegrationResult` |
| `onQuotaExceeded`, `onError` | – | callbacks |

`IForeventsAPIError.kind`: `.auth` (401/403, dropped), `.quotaExceeded`
(429, dropped), `.rateLimited` (429, retried after `Retry-After`),
`.transient` (retried), `.other`.

## Development

```bash
swift test
IFOREVENTS_PROJECT_KEY=pk_... IFOREVENTS_BASE_URL=http://127.0.0.1:8000 swift test --filter SmokeTests
for a in Adapters/*; do (cd "$a" && swift test); done
```

MIT
