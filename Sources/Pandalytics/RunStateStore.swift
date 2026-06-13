import Foundation

/// Durably records critical signals (from `signalCritical` / `captureError`)
/// before they reach the buffer, so they can be recovered on the next launch if
/// the process exits before `SignalBuffer` persists them.
///
/// This path is intentionally synchronous and tiny. Normal analytics stay on the
/// nonblocking stream; only critical signals touch this store, and only as a
/// local recovery marker until `SignalBuffer` has durably persisted the signal.
final class RunStateStore: @unchecked Sendable {

    struct PendingEvent: Codable, Sendable, Equatable {
        let id: String
        let type: String
        let timestamp: String
        let screenName: String?
        let metadata: [String: String]?
    }

    struct Recovery: Sendable, Equatable {
        let pendingEvents: [PendingEvent]
    }

    private let lock = NSLock()
    private let persistenceDirectory: URL?
    private let maxPendingEvents = 50

    init(persistenceDirectory: URL? = nil) {
        self.persistenceDirectory = persistenceDirectory
    }

    /// Load any critical-signal markers left over from a previous run that exited
    /// before the signals were durably buffered. Returns `nil` when there is
    /// nothing to recover.
    @discardableResult
    func recoverPendingEvents() -> Recovery? {
        lock.withLock {
            let pendingEvents = loadPendingEvents()
            guard !pendingEvents.isEmpty else { return nil }
            return Recovery(pendingEvents: pendingEvents)
        }
    }

    @discardableResult
    func recordCriticalSignalQueued(
        type: String,
        screenName: String?,
        metadata: [String: String]?
    ) -> PendingEvent {
        lock.withLock {
            var criticalMetadata = metadata ?? [:]
            criticalMetadata["pandalytics_recovered"] = "true"

            let event = PendingEvent(
                id: UUID().uuidString,
                type: type,
                timestamp: Self.nowString(),
                screenName: screenName,
                metadata: criticalMetadata
            )
            var pendingEvents = loadPendingEvents()
            pendingEvents.append(event)
            savePendingEvents(Array(pendingEvents.suffix(maxPendingEvents)))
            return event
        }
    }

    func completePendingEvent(id: String?) {
        guard let id else { return }
        completePendingEvents(ids: [id])
    }

    func completePendingEvents(ids: [String]) {
        guard !ids.isEmpty else { return }
        lock.withLock {
            let ids = Set(ids)
            let pendingEvents = loadPendingEvents().filter { !ids.contains($0.id) }
            savePendingEvents(pendingEvents)
        }
    }

    // MARK: - Persistence

    private func loadPendingEvents() -> [PendingEvent] {
        guard let url = pendingEventsURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder().decode([PendingEvent].self, from: data)) ?? []
    }

    private func savePendingEvents(_ events: [PendingEvent]) {
        guard let url = pendingEventsURL() else { return }
        if events.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: url, options: .atomic)
        } catch {
            #if DEBUG
            print("[Pandalytics] Failed to persist pending recovery events: \(error.localizedDescription)")
            #endif
        }
    }

    private func pendingEventsURL() -> URL? {
        persistenceURL(filename: "pending_critical_events.json")
    }

    private func persistenceURL(filename: String) -> URL? {
        let dir: URL
        if let persistenceDirectory {
            dir = persistenceDirectory
        } else {
            guard let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else { return nil }
            dir = appSupport.appendingPathComponent("Pandalytics", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    private static func nowString() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
