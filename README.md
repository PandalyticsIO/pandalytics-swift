# Pandalytics Swift SDK

Privacy-focused analytics for Apple platforms.

## Supported Platforms

- iOS 15+
- macOS 12+
- tvOS 15+
- watchOS 8+

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

## Privacy model

- **User identity:** Random UUID generated on first launch, stored in UserDefaults, SHA-256 hashed before sending. Deleted when the app is uninstalled. Enables retention tracking without identifying anyone.
- **Session grouping:** Daily-rotating hash of (OS version + app version + timezone). Changes every day — no cross-day session tracking.
- **No IPs, no IDFA/IDFV, no cookies, no user agent strings.**
- **Device model** (e.g. "iPhone15,2") is not personal data — millions of devices share the same model.
