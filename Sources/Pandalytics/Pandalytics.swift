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
#if canImport(WatchKit)
import WatchKit
#endif

/// Pandalytics — privacy-focused mobile app analytics.
/// No personal data collected. No IPs, no cookies.
/// Installation identity is a random UUID hashed with SHA-256, deleted on app uninstall.
public actor Pandalytics {

    public static let shared = Pandalytics()

    private var appId: String?
    private let signalBuffer: SignalBuffer
    private let runStateStore: RunStateStore
    let sessionManager: SessionManager
    private var lastConfigHash: String?
    private var hasConfigured = false
    private let signalAttributeCache: SignalAttributeCache

    private let continuation: AsyncStream<SDKMessage>.Continuation

    // MARK: - Message types

    private enum LifecycleBackgroundTask: Sendable {
        case none
        #if os(iOS)
        case uiApplication(UIBackgroundTaskIdentifier)
        #endif
    }

    private enum SDKMessage: Sendable {
        case configure(appId: String, ingestionKey: String, options: PandalyticsOptions)
        case signal(type: String, screenName: String?, metadata: [String: String]?)
        case lifecycleSignal(
            type: String,
            flush: Bool,
            pendingEventID: String?,
            backgroundTask: LifecycleBackgroundTask
        )
        case trackConfig([String: String])
        case flush
    }

    // MARK: - Tracking control

    private static let trackingEnabledKey = "io.pandalytics.trackingEnabled"

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
        self.runStateStore = RunStateStore()
        self.sessionManager = SessionManager()
        self.signalAttributeCache = SignalAttributeCache()

        let (stream, continuation) = AsyncStream.makeStream(of: SDKMessage.self)
        self.continuation = continuation
        Task { 
            await processMessages(stream) 
        }
    }

    // MARK: - Public API

    /// Configure the SDK. Call this once at app launch.
    /// - Parameters:
    ///   - appId: Your app's unique ID from the Pandalytics dashboard.
    ///   - ingestionKey: Your app's ingestion key from the Pandalytics dashboard
    ///     (starts with `panda_sk_`). Required — signals won't be delivered
    ///     without a valid key.
    ///   - options: The options for configuring the SDK.
    nonisolated public static func configure(
        appId: String,
        ingestionKey: String,
        options: PandalyticsOptions = .init()
    ) {
        shared.continuation.yield(
            .configure(appId: appId, ingestionKey: ingestionKey, options: options)
        )
    }

    /// Send a signal (custom event).
    /// - Parameters:
    ///   - type: The signal type (e.g., "button_tap", "purchase_completed").
    ///   - metadata: Optional key-value pairs for additional context.
    nonisolated public static func signal(_ type: String, metadata: [String: String]? = nil) {
        shared.continuation.yield(.signal(type: type, screenName: nil, metadata: metadata))
    }

    /// Send a critical signal and wait until it is durably stored on disk.
    ///
    /// This does not wait for network delivery. It guarantees local persistence so
    /// the SDK can retry later if the server is down or the process exits.
    public static func signalCritical(_ type: String, metadata: [String: String]? = nil) async {
        await shared.handleCriticalSignal(type: type, screenName: nil, metadata: metadata)
    }

    /// Record an error as a critical signal and wait until it is durably stored on disk.
    ///
    /// The error name is caller-provided to avoid collecting exception objects or
    /// platform-specific personal data accidentally.
    public static func captureError(_ name: String, metadata: [String: String]? = nil) async {
        var allMetadata = metadata ?? [:]
        allMetadata["error_name"] = name
        await shared.handleCriticalSignal(type: "error", screenName: nil, metadata: allMetadata)
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
            case .configure(let appId, let ingestionKey, let options):
                await handleConfigure(appId: appId, ingestionKey: ingestionKey, options: options)
            case .signal(let type, let screenName, let metadata):
                await handleSignal(type: type, screenName: screenName, metadata: metadata)
            case .lifecycleSignal(let type, let flush, let pendingEventID, let backgroundTask):
                await handleLifecycleSignal(type: type, flush: flush, pendingEventID: pendingEventID)
                await Self.endBackgroundTask(backgroundTask)
            case .trackConfig(let config):
                await handleTrackConfig(config)
            case .flush:
                await signalBuffer.flush()
            }
        }
    }

    // MARK: - Message handlers

    private func handleConfigure(appId: String, ingestionKey: String, options: PandalyticsOptions) async {
        guard !hasConfigured else {
            #if DEBUG
            print("[Pandalytics] SDK already configured. Ignoring duplicate configure() call.")
            #endif
            return
        }

        self.appId = appId

        let transport = PandalyticsTransport(
            ingestionKey: ingestionKey,
            options: options
        )
        let recovery = runStateStore.startRun()
        await signalBuffer.configure(appId: appId, transport: transport)
        await handleRecovery(recovery)
        await signalBuffer.startFlushing()

        if options.trackApplicationLifecycleEvents {
            registerLifecycleObservers()
        }

        hasConfigured = true

        _ = await handleSignal(type: "app_open", screenName: nil, metadata: nil)
    }

    @discardableResult
    private func handleSignal(type: String, screenName: String?, metadata: [String: String]?) async -> Bool {
        guard Self.isTrackingEnabled else { return false }

        let signal = await makeSignal(
            type: type,
            screenName: screenName,
            metadata: metadata,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        await signalBuffer.add(signal)
        return true
    }

    private func handleCriticalSignal(type: String, screenName: String?, metadata: [String: String]?) async {
        guard Self.isTrackingEnabled else { return }

        let pendingEvent = runStateStore.recordCriticalSignalQueued(
            type: type,
            screenName: screenName,
            metadata: metadata
        )
        let signal = await makeSignal(
            type: pendingEvent.type,
            screenName: pendingEvent.screenName,
            metadata: pendingEvent.metadata,
            timestamp: pendingEvent.timestamp
        )
        await signalBuffer.add(signal)
        runStateStore.completePendingEvent(id: pendingEvent.id)
    }

    private func makeSignal(
        type: String,
        screenName: String?,
        metadata: [String: String]?,
        timestamp: String
    ) async -> Signal {
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
            timestamp: timestamp,
            screenName: screenName,
            appVersion: signalAttributeCache.appVersion,
            buildNumber: signalAttributeCache.buildNumber,
            osName: signalAttributeCache.osName,
            osVersion: signalAttributeCache.osVersion,
            deviceModel: signalAttributeCache.deviceModel,
            deviceType: signalAttributeCache.deviceType,
            locale: Locale.current.identifier,
            language: Self.language,
            region: TimeZone.current.identifier,
            installationHash: await sessionManager.installationHash(),
            metadata: allMetadata.isEmpty ? nil : allMetadata
        )

        return signal
    }

    private func handleRecovery(_ recovery: RunStateStore.Recovery?) async {
        guard let recovery else { return }
        guard Self.isTrackingEnabled else {
            runStateStore.completePendingEvents(ids: recovery.pendingEvents.map(\.id))
            return
        }
        for event in recovery.pendingEvents {
            let signal = await makeSignal(
                type: event.type,
                screenName: event.screenName,
                metadata: event.metadata,
                timestamp: event.timestamp
            )
            await signalBuffer.add(signal)
        }
        runStateStore.completePendingEvents(ids: recovery.pendingEvents.map(\.id))
    }

    private func handleTrackConfig(_ config: [String: String]) async {
        let sortedKeys = config.keys.sorted()
        let configString = sortedKeys.map { "\($0)=\(config[$0]!)" }.joined(separator: ",")
        let hash = SessionManager.sha256(configString)

        guard hash != lastConfigHash else { return }
        lastConfigHash = hash

        _ = await handleSignal(type: "config_change", screenName: nil, metadata: config)
    }

    private func handleLifecycleSignal(type: String, flush: Bool, pendingEventID: String?) async {
        _ = await handleSignal(type: type, screenName: nil, metadata: nil)
        runStateStore.completePendingEvent(id: pendingEventID)
        if flush {
            await signalBuffer.flush()
        }
    }

    // MARK: - Lifecycle observers

    private nonisolated func registerLifecycleObservers() {
        let nc = NotificationCenter.default

        #if os(iOS) || os(tvOS) || os(visionOS)
        nc.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.enqueueLifecycleSignal(type: "app_close", flush: true, requestBackgroundTime: false)
        }
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.enqueueLifecycleSignal(type: "app_background", flush: true, requestBackgroundTime: true)
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.enqueueLifecycleSignal(type: "app_foreground", flush: false, requestBackgroundTime: false)
        }
        #elseif os(macOS)
        nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.enqueueLifecycleSignal(type: "app_close", flush: true, requestBackgroundTime: false)
        }
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.enqueueLifecycleSignal(type: "app_background", flush: true, requestBackgroundTime: false)
        }
        nc.addObserver(forName: NSApplication.willBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.enqueueLifecycleSignal(type: "app_foreground", flush: false, requestBackgroundTime: false)
        }
        #elseif os(watchOS)
        nc.addObserver(forName: WKApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.enqueueLifecycleSignal(type: "app_background", flush: true, requestBackgroundTime: false)
        }
        nc.addObserver(forName: WKApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.enqueueLifecycleSignal(type: "app_foreground", flush: false, requestBackgroundTime: false)
        }
        #endif
    }

    private nonisolated func enqueueLifecycleSignal(
        type: String,
        flush: Bool,
        requestBackgroundTime: Bool
    ) {
        let pendingEventID: String?
        if Self.isTrackingEnabled {
            pendingEventID = runStateStore.recordLifecycleSignalQueued(type: type)
        } else {
            runStateStore.recordLifecycleState(type: type)
            pendingEventID = nil
        }
        let backgroundTask: LifecycleBackgroundTask
        #if os(iOS)
        if requestBackgroundTime {
            backgroundTask = .uiApplication(
                MainActor.assumeIsolated {
                    UIApplication.shared.beginBackgroundTask(withName: "PandalyticsFlush")
                }
            )
        } else {
            backgroundTask = .none
        }
        #else
        backgroundTask = .none
        #endif

        continuation.yield(
            .lifecycleSignal(
                type: type,
                flush: flush,
                pendingEventID: pendingEventID,
                backgroundTask: backgroundTask
            )
        )
    }

    private nonisolated static func endBackgroundTask(
        _ backgroundTask: LifecycleBackgroundTask
    ) async {
        #if os(iOS)
        guard case .uiApplication(let identifier) = backgroundTask else { return }
        await MainActor.run {
            UIApplication.shared.endBackgroundTask(identifier)
        }
        #endif
    }

    // MARK: - Device info (no PII)

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

            #if !os(visionOS)
            let bounds = windowScene.screen.nativeBounds
            meta["screen_resolution"] = "\(Int(bounds.width))x\(Int(bounds.height))"
            #endif
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
