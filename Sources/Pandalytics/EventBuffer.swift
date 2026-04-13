import Foundation

/// Buffers signals in memory and on disk, sends them in batches via a `SignalTransport`.
///
/// - Signals are persisted to disk on every `add()` so they survive app crashes.
/// - A cap of 1000 signals prevents unbounded growth (oldest dropped).
/// - Flush sends the current batch through the transport. On failure, signals stay
///   in place (memory + disk) and are retried on the next flush cycle.
/// - Signals can be added before `configure()` — they accumulate until a transport is provided.
actor SignalBuffer {

    private var signals: [Signal] = []
    private var appId: String?
    private var transport: (any SignalTransport)?
    private var isSending = false
    private var flushTask: Task<Void, Never>?

    private let flushThreshold = 20
    private let maxSignalCap = 1000
    private let flushInterval: TimeInterval = 30

    private let persistenceDirectory: URL?

    /// - Parameter persistenceDirectory: Custom directory for the persistence file.
    ///   Pass `nil` (default) to use `Application Support/Pandalytics/`.
    ///   Tests should pass a temp directory to avoid polluting the real storage.
    init(persistenceDirectory: URL? = nil) {
        self.persistenceDirectory = persistenceDirectory
    }

    /// Wire up the transport and load any persisted signals from a previous session.
    func configure(appId: String, transport: any SignalTransport) {
        self.appId = appId
        self.transport = transport
        loadFromDisk()
    }

    /// Add a signal to the buffer. Persisted to disk immediately.
    /// Works before `configure()` — signals accumulate until a transport is available.
    func add(_ signal: Signal) {
        signals.append(signal)
        enforceCapacity()
        saveToDisk()
        if signals.count >= flushThreshold {
            Task { await flush() }
        }
    }

    /// Start the periodic flush timer (every 30 seconds).
    func startFlushing() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.flushInterval ?? 30))
                await self?.flush()
            }
        }
    }

    /// Send all buffered signals through the transport.
    /// On success, sent signals are removed from memory and disk.
    /// On failure, signals remain in place for retry.
    func flush() async {
        guard !signals.isEmpty, !isSending else { return }
        guard let appId, let transport else { return }

        let batch = signals
        isSending = true

        let payload = SignalBatch(appId: appId, signals: batch)
        let result = await transport.send(batch: payload)

        switch result {
        case .success:
            signals = Array(signals.dropFirst(batch.count))
            saveToDisk()
        case .rateLimited:
            signals = Array(signals.dropFirst(batch.count))
            saveToDisk()
            #if DEBUG
            print("[Pandalytics] Rate limited or over quota. Signals dropped.")
            #endif
        case .serverError:
            #if DEBUG
            print("[Pandalytics] Server error. Will retry.")
            #endif
        case .networkError:
            #if DEBUG
            print("[Pandalytics] Network error. Will retry.")
            #endif
        }

        isSending = false
    }

    /// Returns the number of buffered signals (for testing).
    var bufferedCount: Int {
        signals.count
    }

    // MARK: - Persistence

    private func persistenceURL() -> URL? {
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
        return dir.appendingPathComponent("signals.json")
    }

    private func saveToDisk() {
        guard let url = persistenceURL() else { return }
        if signals.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            let data = try JSONEncoder().encode(signals)
            try data.write(to: url, options: .atomic)
        } catch {
            #if DEBUG
            print("[Pandalytics] Failed to persist signals: \(error.localizedDescription)")
            #endif
        }
    }

    private func loadFromDisk() {
        guard let url = persistenceURL(),
              FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder().decode([Signal].self, from: data)
            // Disk is the source of truth — add() always persists, so the disk file
            // already contains any signals added before configure() in this session.
            // Replace the in-memory array to avoid duplication.
            signals = loaded
            enforceCapacity()
        } catch {
            #if DEBUG
            print("[Pandalytics] Failed to load persisted signals: \(error.localizedDescription)")
            #endif
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func enforceCapacity() {
        if signals.count > maxSignalCap {
            signals = Array(signals.suffix(maxSignalCap))
        }
    }
}
