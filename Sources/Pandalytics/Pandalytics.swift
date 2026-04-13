import Foundation
import CryptoKit
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Pandalytics — privacy-focused mobile app analytics.
/// No personal data collected. No IPs, no cookies.
/// Installation identity is a random UUID hashed with SHA-256, deleted on app uninstall.
public actor Pandalytics {

    public static let shared = Pandalytics()

    private var appId: String?
    private var isDev: Bool
    private let signalBuffer: SignalBuffer
    let sessionManager: SessionManager
    private var lastConfigHash: String?
    private var hasConfigured = false

    private let continuation: AsyncStream<SDKMessage>.Continuation

    // MARK: - Message types

    private enum SDKMessage: Sendable {
        case configure(appId: String, isDev: Bool?)
        case signal(type: String, screenName: String?, metadata: [String: String]?)
        case trackConfig([String: String])
        case flush
    }

    // MARK: - Tracking control

    private static let trackingEnabledKey = "com.pandalytics.trackingEnabled"

    /// Enable or disable tracking. Persisted across app launches.
    /// When disabled, signals are silently dropped (not buffered).
    /// Default: enabled.
    nonisolated public static func setTrackingEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: trackingEnabledKey)
    }

    /// Returns whether tracking is currently enabled.
    nonisolated public static var isTrackingEnabled: Bool {
        if UserDefaults.standard.object(forKey: trackingEnabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: trackingEnabledKey)
    }

    // MARK: - Initialization

    private init() {
        self.signalBuffer = SignalBuffer()
        self.sessionManager = SessionManager()
        #if DEBUG
        self.isDev = true
        #else
        self.isDev = false
        #endif

        let (stream, continuation) = AsyncStream.makeStream(of: SDKMessage.self)
        self.continuation = continuation
        Task { await processMessages(stream) }
    }

    // MARK: - Public API

    /// Configure the SDK. Call this once at app launch.
    /// - Parameters:
    ///   - appId: Your app's unique ID from the Pandalytics dashboard.
    ///   - isDev: Override dev detection. If nil, uses #if DEBUG (defaults to true for debug builds).
    nonisolated public static func configure(appId: String, isDev: Bool? = nil) {
        shared.continuation.yield(.configure(appId: appId, isDev: isDev))
    }

    /// Send a signal (custom event).
    /// - Parameters:
    ///   - type: The signal type (e.g., "button_tap", "purchase_completed").
    ///   - metadata: Optional key-value pairs for additional context.
    nonisolated public static func signal(_ type: String, metadata: [String: String]? = nil) {
        shared.continuation.yield(.signal(type: type, screenName: nil, metadata: metadata))
    }

    /// Track a screen view.
    /// - Parameter name: The screen name (e.g., "HomeScreen", "SettingsScreen").
    nonisolated public static func trackScreen(_ name: String) {
        shared.continuation.yield(.signal(type: "screen_view", screenName: name, metadata: nil))
    }

    /// Track a configuration snapshot. Only sends if the config has changed since the last call.
    /// Config is sent as a signal with type "config_change" and the config pairs in metadata.
    nonisolated public static func trackConfig(_ config: [String: String]) {
        shared.continuation.yield(.trackConfig(config))
    }

    // MARK: - Message processing loop

    private func processMessages(_ stream: AsyncStream<SDKMessage>) async {
        for await message in stream {
            switch message {
            case .configure(let appId, let isDev):
                await handleConfigure(appId: appId, isDev: isDev)
            case .signal(let type, let screenName, let metadata):
                await handleSignal(type: type, screenName: screenName, metadata: metadata)
            case .trackConfig(let config):
                await handleTrackConfig(config)
            case .flush:
                await signalBuffer.flush()
            }
        }
    }

    // MARK: - Message handlers

    private func handleConfigure(appId: String, isDev: Bool?) async {
        guard !hasConfigured else {
            #if DEBUG
            print("[Pandalytics] SDK already configured. Ignoring duplicate configure() call.")
            #endif
            return
        }

        self.appId = appId
        if let isDev { self.isDev = isDev }

        let transport = URLSessionTransport(isDev: self.isDev)
        await signalBuffer.configure(appId: appId, transport: transport)
        await signalBuffer.startFlushing()
        registerLifecycleObservers()

        hasConfigured = true

        await handleSignal(type: "app_open", screenName: nil, metadata: nil)
    }

    private func handleSignal(type: String, screenName: String?, metadata: [String: String]?) async {
        guard Self.isTrackingEnabled else { return }

        var allMetadata = metadata ?? [:]
        let defaults = await Self.collectDefaultMetadata()
        for (key, value) in defaults {
            if allMetadata[key] == nil {
                allMetadata[key] = value
            }
        }

        #if targetEnvironment(simulator)
        allMetadata["simulator"] = "true"
        #endif

        let signal = Signal(
            signalType: type,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            screenName: screenName,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            osName: Self.osName,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: Self.deviceModel,
            deviceType: Self.deviceType,
            locale: Locale.current.identifier,
            language: Self.language,
            region: TimeZone.current.identifier,
            userHash: await sessionManager.installationHash(),
            isDev: isDev,
            metadata: allMetadata.isEmpty ? nil : allMetadata
        )

        await signalBuffer.add(signal)
    }

    private func handleTrackConfig(_ config: [String: String]) async {
        let sortedKeys = config.keys.sorted()
        let configString = sortedKeys.map { "\($0)=\(config[$0]!)" }.joined(separator: ",")
        let hash = SessionManager.sha256(configString)

        guard hash != lastConfigHash else { return }
        lastConfigHash = hash

        await handleSignal(type: "config_change", screenName: nil, metadata: config)
    }

    // MARK: - Lifecycle observers

    private nonisolated func registerLifecycleObservers() {
        let nc = NotificationCenter.default

        #if os(iOS) || os(tvOS)
        nc.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.continuation.yield(.signal(type: "app_close", screenName: nil, metadata: nil))
            self.continuation.yield(.flush)
        }
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.continuation.yield(.signal(type: "app_background", screenName: nil, metadata: nil))
            self.continuation.yield(.flush)
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.continuation.yield(.signal(type: "app_foreground", screenName: nil, metadata: nil))
        }
        #elseif os(macOS)
        nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.continuation.yield(.signal(type: "app_close", screenName: nil, metadata: nil))
            self.continuation.yield(.flush)
        }
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.continuation.yield(.signal(type: "app_background", screenName: nil, metadata: nil))
            self.continuation.yield(.flush)
        }
        nc.addObserver(forName: NSApplication.willBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.continuation.yield(.signal(type: "app_foreground", screenName: nil, metadata: nil))
        }
        #endif
    }

    // MARK: - Device info (no PII)

    private nonisolated static var osName: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(watchOS)
        return "watchOS"
        #else
        return "unknown"
        #endif
    }

    private nonisolated static var deviceModel: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        if let nullIndex = machine.firstIndex(of: 0) {
            machine = Array(machine[..<nullIndex])
        }
        return String(decoding: machine.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private nonisolated static var deviceType: String {
        #if os(iOS)
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: return "phone"
        case .pad: return "tablet"
        case .tv: return "tv"
        default: return "unknown"
        }
        #elseif os(macOS)
        return "desktop"
        #elseif os(watchOS)
        return "watch"
        #elseif os(tvOS)
        return "tv"
        #elseif os(visionOS)
        return "headset"
        #else
        return "unknown"
        #endif
    }

    private nonisolated static var language: String {
        Locale.current.language.languageCode?.identifier ?? "unknown"
    }

    @MainActor
    private static func collectDefaultMetadata() -> [String: String] {
        var meta: [String: String] = [:]

        #if canImport(UIKit) && !os(watchOS)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            switch windowScene.traitCollection.userInterfaceStyle {
            case .dark: meta["color_scheme"] = "dark"
            case .light: meta["color_scheme"] = "light"
            default: meta["color_scheme"] = "unknown"
            }

            let bounds = windowScene.screen.nativeBounds
            meta["screen_resolution"] = "\(Int(bounds.width))x\(Int(bounds.height))"
        }

        meta["accessibility_reduce_motion"] = UIAccessibility.isReduceMotionEnabled ? "true" : "false"
        meta["accessibility_bold_text"] = UIAccessibility.isBoldTextEnabled ? "true" : "false"
        meta["accessibility_reduce_transparency"] = UIAccessibility.isReduceTransparencyEnabled ? "true" : "false"
        #endif

        return meta
    }
}

// MARK: - SwiftUI View Modifier

#if canImport(SwiftUI)
public extension View {
    /// Track when this screen appears.
    /// Usage: `.trackScreen("HomeScreen")`
    func trackScreen(_ name: String) -> some View {
        self.onAppear {
            Pandalytics.trackScreen(name)
        }
    }
}
#endif
