# Pandalytics Swift SDK

Privacy-focused analytics for Apple platforms.

## Supported Platforms

- iOS 16+
- macOS 13+
- tvOS 16+
- watchOS 9+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/PandalyticsIO/pandalytics-swift.git", from: "0.1.0")
]
```

Or in Xcode: File > Add Package Dependencies > paste the repository URL.

## Quick Start

```swift
import Pandalytics

// Configure once at app launch. Both values come from your Pandalytics dashboard;
// the ingestion key (`panda_sk_...`) is shown once when you create the app and
// can be rotated at any time.
Pandalytics.configure(
    appId: "your-app-id-from-dashboard",
    ingestionKey: "panda_sk_..."
)

// Send signals
Pandalytics.signal("purchase_completed")
Pandalytics.signal("item_added", metadata: ["category": "groceries"])

// Critical signals wait until the event is stored locally on disk.
// They do not wait for network delivery.
await Pandalytics.signalCritical("purchase_failed", metadata: ["reason": "timeout"])
await Pandalytics.captureError("DatabaseError")

// Track screens (SwiftUI)
struct HomeView: View {
    var body: some View {
        Text("Home")
            .trackScreen("HomeScreen")
    }
}
```

## What data is collected?

**Automatically collected (no code needed):**
- Signal type and timestamp
- App version and build number
- OS name and version
- Device model (e.g. "iPhone15,2")
- Locale (e.g. "en_US") and IANA timezone
- Color scheme (light/dark)
- Accessibility settings (reduce motion, bold text, reduce transparency)
- Screen resolution
- Anonymous user hash (random UUID, hashed with SHA-256)

**You provide:**
- Screen name (via `.trackScreen()`)
- Custom signal types and metadata

## Reliability model

- Normal signals are nonblocking and are queued through a single async stream.
- Signals are persisted locally before delivery, then retried if the network or server is unavailable.
- Lifecycle signals are mirrored into a small local recovery store before they enter the async stream. If the app is suspended or exits before the signal buffer writes them, the SDK recovers them on the next launch.
- `signalCritical(...)` and `captureError(...)` are opt-in async APIs for cases where local durability matters more than returning immediately. They wait for local disk persistence, not server delivery.
- If a foreground run ends without a clean shutdown marker, the next launch emits `previous_run_ended_unexpectedly` with recovery metadata. Backgrounded runs are not treated as unexpected exits.

## Privacy model

- **User identity:** Random UUID generated on first launch, stored in UserDefaults, SHA-256 hashed before sending. Deleted when the app is uninstalled. Enables retention tracking without identifying anyone.
- **No IPs, no IDFA/IDFV, no cookies, no user agent strings.**
- **Device model** (e.g. "iPhone15,2") is not personal data — millions of devices share the same model.
