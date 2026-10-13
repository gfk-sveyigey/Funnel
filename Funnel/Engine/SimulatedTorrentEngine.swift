import Foundation

/// 占位引擎：在 M0 结论出来之前，用纯 Swift 模拟「获取元数据 → 下载 → 做种」，
/// 让 UI、保活、持久化可以端到端跑通。M0 若判定可行，用 `SwiftyTorrentEngine` 替换。
@MainActor
final class SimulatedTorrentEngine: TorrentEngineProtocol {

    let engineName = "Simulated（占位）"

    private struct Session {
        var status: TorrentTaskStatus
        var elapsed: TimeInterval
        var speed: Int64
    }

    private var sessions: [String: Session] = [:]
    private var continuation: AsyncStream<TorrentTaskStatus>.Continuation?
    private var ticker: Timer?
    private var downloadLimit: Int64?
    private var seedingEnabled = true

    private let tickInterval: TimeInterval = 0.5
    private let metadataDelay: TimeInterval = 1.5

    func statusStream() -> AsyncStream<TorrentTaskStatus> {
        let (stream, continuation) = AsyncStream<TorrentTaskStatus>.makeStream()
        self.continuation = continuation
        for session in sessions.values {
            continuation.yield(session.status)
        }
        return stream
    }

    func snapshot(_ taskID: String) -> TorrentTaskStatus? {
        sessions[taskID]?.status
    }

    func eventStream() -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }

    @discardableResult
    func add(magnet: String, saveDirectory: String) async throws -> String {
        let infoHash = Self.infoHash(from: magnet)
        let name = Self.displayName(from: magnet) ?? "Magnet \(infoHash.prefix(8))"

        let status = TorrentTaskStatus(
            taskID: infoHash,
            magnet: magnet,
            state: .metadata,
            name: name,
            totalBytes: 0,
            downloadedBytes: 0,
            downloadSpeed: 0,
            uploadSpeed: 0,
            peerCount: 0,
            files: [],
            saveDirectory: saveDirectory,
            errorMessage: nil
        )
        sessions[infoHash] = Session(status: status, elapsed: 0, speed: Self.randomSpeed())
        emit(status)
        startTickerIfNeeded()
        return infoHash
    }

    func pause(_ taskID: String) async throws {
        guard var session = sessions[taskID] else { return }
        session.status.state = .paused
        session.status.downloadSpeed = 0
        session.status.uploadSpeed = 0
        sessions[taskID] = session
        emit(session.status)
    }

    func resume(_ taskID: String) async throws {
        guard var session = sessions[taskID] else { return }
        guard session.status.state == .paused || session.status.state == .stopped else { return }
        session.status.state = .downloading
        session.elapsed = 0
        sessions[taskID] = session
        emit(session.status)
        startTickerIfNeeded()
    }

    func remove(_ taskID: String, deleteData: Bool) async throws {
        sessions[taskID] = nil
    }

    func selectFiles(_ taskID: String, indexes: Set<Int>) async throws {
        guard var session = sessions[taskID] else { return }
        for index in session.status.files.indices {
            session.status.files[index].isSelected = indexes.contains(session.status.files[index].index)
        }
        session.status.totalBytes = session.status.files.filter { $0.isSelected }.reduce(0) { $0 + $1.length }
        sessions[taskID] = session
        emit(session.status)
    }

    func setDownloadLimit(bytesPerSecond: Int?) {
        downloadLimit = bytesPerSecond.map(Int64.init)
    }

    func setSeedingEnabled(_ enabled: Bool) {
        seedingEnabled = enabled
    }

    // MARK: - 模拟引擎内部

    private func startTickerIfNeeded() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        var anyRunning = false
        for id in Array(sessions.keys) {
            guard var session = sessions[id] else { continue }
            session.elapsed += tickInterval

            switch session.status.state {
            case .metadata:
                anyRunning = true
                if session.elapsed >= metadataDelay {
                    session.elapsed = 0
                    session.status.files = Self.placeholderFiles(for: session.status.name)
                    session.status.totalBytes = session.status.files.filter { $0.isSelected }.reduce(0) { $0 + $1.length }
                    session.status.peerCount = Int.random(in: 4...40)
                    session.status.state = .downloading
                }

            case .downloading:
                anyRunning = true
                let speed = min(session.speed, downloadLimit ?? session.speed)
                let increment = Int64(Double(speed) * tickInterval)
                session.status.downloadedBytes = min(session.status.totalBytes, session.status.downloadedBytes + increment)
                session.status.downloadSpeed = speed
                session.status.uploadSpeed = speed / 8
                session.status.peerCount = max(1, session.status.peerCount + Int.random(in: -1...1))
                Self.distributeProgress(&session.status)
                if session.status.downloadedBytes >= session.status.totalBytes {
                    session.status.state = seedingEnabled ? .seeding : .completed
                    session.status.downloadSpeed = 0
                }

            default:
                break
            }

            sessions[id] = session
            emit(session.status)
        }

        if !anyRunning {
            stopTicker()
        }
    }

    private func emit(_ status: TorrentTaskStatus) {
        continuation?.yield(status)
    }

    private static func distributeProgress(_ status: inout TorrentTaskStatus) {
        var remaining = status.downloadedBytes
        for index in status.files.indices where status.files[index].isSelected {
            let length = status.files[index].length
            let filled = min(length, remaining)
            status.files[index].downloaded = filled
            remaining -= filled
        }
    }

    private static func placeholderFiles(for name: String) -> [TorrentFile] {
        let entries: [(String, Int64, Bool)] = [
            ("\(name).mp4", 512 * 1024 * 1024, true),
            ("\(name).srt", 180 * 1024 * 1024, true),
            ("readme.txt", 24 * 1024 * 1024, false)
        ]
        return entries.enumerated().map { index, entry in
            TorrentFile(index: index, path: entry.0, length: entry.1, downloaded: 0, isSelected: entry.2)
        }
    }

    private static func randomSpeed() -> Int64 {
        Int64.random(in: 2_000_000...12_000_000)
    }

    static func infoHash(from magnet: String) -> String {
        if let range = magnet.range(of: "btih:") {
            let hash = magnet[range.upperBound...].prefix { $0 != "&" }
            if !hash.isEmpty { return String(hash).uppercased() }
        }
        return String(UInt64(bitPattern: Int64(magnet.hashValue)), radix: 16).uppercased()
    }

    static func displayName(from magnet: String) -> String? {
        guard let range = magnet.range(of: "dn=") else { return nil }
        let raw = magnet[range.upperBound...].prefix { $0 != "&" }
        guard !raw.isEmpty else { return nil }
        return raw.removingPercentEncoding ?? String(raw)
    }
}
