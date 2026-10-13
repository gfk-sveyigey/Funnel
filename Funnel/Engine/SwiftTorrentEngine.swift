import Foundation
import SwiftTorrent

/// 真实引擎：warppipe/swift-torrent（纯 Swift、SwiftPM，无 C/C++ 依赖）。
/// 已知限制（见 docs/M0-ENGINE.md）：不支持按文件选择优先级，也不提供 per-file 进度，
/// 所以 `selectFiles` 只做记录，文件进度留待其 API 支持后再补。
@MainActor
final class SwiftTorrentEngine: TorrentEngineProtocol {

    let engineName = "SwiftTorrent (纯 Swift)"

    private struct Entry {
        let handle: TorrentHandle
        let magnet: String
        let saveDirectory: String
    }

    private let session: Session
    private var settings: SessionSettings
    private var entries: [String: Entry] = [:]
    private var continuation: AsyncStream<TorrentTaskStatus>.Continuation?
    private var pollTask: Task<Void, Never>?
    private var seedingEnabled = true
    private var dhtStarted = false

    init(listenPort: UInt16 = 6881, dhtEnabled: Bool = true) {
        var settings = SessionSettings(listenPort: listenPort, dhtEnabled: dhtEnabled)
        settings.userAgent = "Funnel/1.0"
        self.settings = settings
        session = Session(settings: settings)
    }

    // MARK: - TorrentEngineProtocol

    func statusStream() -> AsyncStream<TorrentTaskStatus> {
        let (stream, continuation) = AsyncStream<TorrentTaskStatus>.makeStream()
        self.continuation = continuation
        startPollingIfNeeded()
        return stream
    }

    func snapshot(_ taskID: String) -> TorrentTaskStatus? {
        nil
    }

    @discardableResult
    func add(magnet: String, saveDirectory: String) async throws -> String {
        var params = try AddTorrentParams.fromMagnet(magnet, savePath: saveDirectory)
        params.paused = true

        let handle = try await session.addTorrent(params)
        let taskID = Self.hex(handle.infoHash.bytes)
        entries[taskID] = Entry(handle: handle, magnet: magnet, saveDirectory: saveDirectory)

        try? await handle.start()
        await startDHTIfNeeded()
        await emitAll()
        startPollingIfNeeded()
        return taskID
    }

    func pause(_ taskID: String) async throws {
        guard let entry = entries[taskID] else { return }
        await entry.handle.pause()
        await emitAll()
    }

    func resume(_ taskID: String) async throws {
        guard let entry = entries[taskID] else { return }
        try await entry.handle.resume()
        await emitAll()
    }

    func remove(_ taskID: String, deleteData: Bool) async throws {
        guard let entry = entries.removeValue(forKey: taskID) else { return }
        // SwiftTorrent 的 deleteFiles 会删掉整个 savePath，粒度太粗；文件删除交给 FileStore。
        await session.removeTorrent(entry.handle.infoHash, deleteFiles: false)
        await emitAll()
    }

    func selectFiles(_ taskID: String, indexes: Set<Int>) async throws {
        // 引擎暂不支持按文件选择；选择结果仍保存在任务模型里。
    }

    func setDownloadLimit(bytesPerSecond: Int?) {
        settings.downloadRateLimit = bytesPerSecond ?? 0
        let updated = settings
        Task { await session.updateSettings(updated) }
    }

    func setSeedingEnabled(_ enabled: Bool) {
        seedingEnabled = enabled
    }

    // MARK: - 内部

    private func startDHTIfNeeded() async {
        guard !dhtStarted, settings.dhtEnabled else { return }
        dhtStarted = true
        try? await session.startDHT()
    }

    private func startPollingIfNeeded() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.emitAll()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func emitAll() async {
        guard let continuation = self.continuation else { return }
        for taskID in Array(entries.keys) {
            guard let entry = entries[taskID] else { continue }
            let status = await entry.handle.status()
            let files = Self.mapFiles(await entry.handle.getFiles())
            continuation.yield(Self.makeStatus(
                status,
                taskID: taskID,
                entry: entry,
                files: files,
                seedingEnabled: seedingEnabled
            ))
        }
    }

    private static func makeStatus(
        _ status: TorrentStatus,
        taskID: String,
        entry: Entry,
        files: [TorrentFile],
        seedingEnabled: Bool
    ) -> TorrentTaskStatus {
        let state = mapState(status.state, seedingEnabled: seedingEnabled)
        return TorrentTaskStatus(
            taskID: taskID,
            magnet: entry.magnet,
            state: state,
            name: status.name.isEmpty ? taskID : status.name,
            totalBytes: status.totalSize,
            downloadedBytes: status.totalDownloaded,
            downloadSpeed: Int64(status.downloadRate),
            uploadSpeed: Int64(status.uploadRate),
            peerCount: status.numPeers,
            files: files,
            saveDirectory: entry.saveDirectory,
            errorMessage: state == .failed ? "下载出错" : nil
        )
    }

    private static func mapState(_ state: TorrentState, seedingEnabled: Bool) -> TorrentTaskState {
        switch state {
        case .checkingFiles: return .downloading
        case .downloadingMetadata: return .metadata
        case .downloading: return .downloading
        case .seeding: return seedingEnabled ? .seeding : .completed
        case .paused: return .paused
        case .stopped: return .stopped
        case .error: return .failed
        }
    }

    private static func mapFiles(_ raw: [TorrentInfo.FileEntry]?) -> [TorrentFile] {
        guard let raw else { return [] }
        return raw.enumerated().map { index, entry in
            TorrentFile(index: index, path: entry.path, length: entry.length, downloaded: 0, isSelected: true)
        }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
