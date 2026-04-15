import Foundation

/// Stores small crash-adjacent run state separately from the normal signal queue.
///
/// This path is intentionally synchronous and tiny. Normal analytics stay on the
/// nonblocking stream; lifecycle/error signals use this only as a local recovery
/// marker until `SignalBuffer` has durably persisted the corresponding signal.
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

    private struct RunState: Codable, Sendable {
        let runId: String
        let startedAt: String
        var cleanShutdown: Bool
        var lastLifecycleSignal: String?
        var lastLifecycleAt: String?
        var updatedAt: String
    }

    private let lock = NSLock()
    private let persistenceDirectory: URL?
    private let maxPendingEvents = 50

    init(persistenceDirectory: URL? = nil) {
        self.persistenceDirectory = persistenceDirectory
    }

    @discardableResult
    func startRun() -> Recovery? {
        lock.withLock {
            var pendingEvents = loadPendingEvents()
            let previousState = loadRunState()

            if let unexpectedEvent = makeUnexpectedRunEvent(from: previousState),
               !pendingEvents.contains(where: { $0.id == unexpectedEvent.id }) {
                pendingEvents.append(unexpectedEvent)
                pendingEvents = Array(pendingEvents.suffix(maxPendingEvents))
                savePendingEvents(pendingEvents)
            }

            saveRunState(
                RunState(
                    runId: UUID().uuidString,
                    startedAt: Self.nowString(),
                    cleanShutdown: false,
                    lastLifecycleSignal: nil,
                    lastLifecycleAt: nil,
                    updatedAt: Self.nowString()
                )
            )

            guard !pendingEvents.isEmpty else { return nil }
            return Recovery(pendingEvents: pendingEvents)
        }
    }

    @discardableResult
    func recordLifecycleSignalQueued(type: String) -> String? {
        lock.withLock {
            updateLifecycleState(type: type)

            let event = PendingEvent(
                id: UUID().uuidString,
                type: type,
                timestamp: Self.nowString(),
                screenName: nil,
                metadata: ["pandalytics_recovered": "true"]
            )
            var pendingEvents = loadPendingEvents()
            pendingEvents.append(event)
            savePendingEvents(Array(pendingEvents.suffix(maxPendingEvents)))
            return event.id
        }
    }

    func recordLifecycleState(type: String) {
        lock.withLock {
            updateLifecycleState(type: type)
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

    private func makeUnexpectedRunEvent(from state: RunState?) -> PendingEvent? {
        guard let state, !state.cleanShutdown else { return nil }
        if state.lastLifecycleSignal == "app_background" {
            return nil
        }

        var metadata: [String: String] = [
            "pandalytics_recovered": "true",
            "previous_run_id": state.runId,
            "previous_run_started_at": state.startedAt,
        ]
        if let lastLifecycleSignal = state.lastLifecycleSignal {
            metadata["last_lifecycle_signal"] = lastLifecycleSignal
        }
        if let lastLifecycleAt = state.lastLifecycleAt {
            metadata["last_lifecycle_at"] = lastLifecycleAt
        }

        return PendingEvent(
            id: "unexpected-\(state.runId)",
            type: "previous_run_ended_unexpectedly",
            timestamp: Self.nowString(),
            screenName: nil,
            metadata: metadata
        )
    }

    private func updateRunState(_ update: (inout RunState) -> Void) {
        guard var state = loadRunState() else { return }
        update(&state)
        saveRunState(state)
    }

    private func updateLifecycleState(type: String) {
        updateRunState { state in
            state.cleanShutdown = type == "app_close"
            state.lastLifecycleSignal = type
            state.lastLifecycleAt = Self.nowString()
            state.updatedAt = Self.nowString()
        }
    }

    private func loadRunState() -> RunState? {
        guard let url = runStateURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(RunState.self, from: data)
    }

    private func saveRunState(_ state: RunState) {
        guard let url = runStateURL() else { return }
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: .atomic)
        } catch {
            #if DEBUG
            print("[Pandalytics] Failed to persist run state: \(error.localizedDescription)")
            #endif
        }
    }

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

    private func runStateURL() -> URL? {
        persistenceURL(filename: "run_state.json")
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
