
/// Pandalytics Options that can be set at initialization 
/// of the Pandalytics client. 
public struct PandalyticsOptions: Sendable {
    // var flushAt: Int = 20
    // var flushInterval: TimeInterval = 60
    // var maxQueueSize: Int = 1000
    var trackApplicationLifecycleEvents: Bool = false
    // var recordScreenViews: Bool = false
    var isDev: Bool? = nil

    public init() {
      #if DEBUG
      isDev = true
      #else
      isDev = false
      #endif
    }

    public init(
        // flushAt: Int = 20,
        // flushInterval: TimeInterval = 60,
        // maxQueueSize: Int = 1000,
        trackApplicationLifecycleEvents: Bool = false,
        // recordScreenViews: Bool = false,
        isDev: Bool? = nil
    ) {
        // self.flushAt = flushAt
        // self.flushInterval = flushInterval
        // self.maxQueueSize = maxQueueSize
        self.trackApplicationLifecycleEvents = trackApplicationLifecycleEvents
        // self.recordScreenViews = recordScreenViews

        if isDev == nil {
            #if DEBUG
            self.isDev = true
            #else
            self.isDev = false
            #endif
        } else {
            self.isDev = isDev
        }
    }
}