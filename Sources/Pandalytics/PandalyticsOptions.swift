
/// Pandalytics Options that can be set at initialization
/// of the Pandalytics client.
public struct PandalyticsOptions: Sendable {
    // var flushAt: Int = 20
    // var flushInterval: TimeInterval = 60
    // var maxQueueSize: Int = 1000
    // var recordScreenViews: Bool = false

    /// Build environment for this install. Auto-detected at init
    /// (debug → `.debug`, TestFlight → `.beta`, otherwise `.production`) unless
    /// an explicit value is supplied — e.g. to tag an externally-distributed
    /// beta as `.beta`. Sent as the `X-Pandalytics-Environment` header.
    public var environment: PandalyticsEnvironment

    public init(environment: PandalyticsEnvironment? = nil) {
        self.environment = environment ?? PandalyticsEnvironment.detect()
    }

    /// Legacy initializer. `isDev: true` maps to `.debug`, `false` to
    /// `.production`, and `nil` to auto-detection.
    @available(*, deprecated, message: "Use init(environment:) — debug builds and TestFlight are auto-detected; pass .beta/.debug to override.")
    public init(isDev: Bool?) {
        if let isDev {
            self.environment = isDev ? .debug : .production
        } else {
            self.environment = PandalyticsEnvironment.detect()
        }
    }
}
