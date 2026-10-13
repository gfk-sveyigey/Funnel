import Foundation
import SwiftTorrent

/// 真实引擎：warppipe/swift-torrent（纯 Swift、SwiftPM，无 C/C++ 依赖）。
/// 已 vendor 并打过补丁：支持断点续传、按文件选择。
/// 已知限制（见 docs/M0-ENGINE.md）：不提供 per-file 进度，文件行进度暂显 0。
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
    /// 最近一次推送的状态缓存，供同步的 snapshot(_:) 查询。
    private var latestStatus: [String: TorrentTaskStatus] = [:]
    /// 元数据未到位时暂存的按文件选择（磁力场景），metadata 到达后自动下发。
    private var pendingSelection: [String: Set<Int>] = [:]
    private var eventContinuation: AsyncStream<String>.Continuation?
    private var alertTask: Task<Void, Never>?

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
        latestStatus[taskID]
    }

    func eventStream() -> AsyncStream<String> {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        eventContinuation = continuation
        startAlertObservation()
        return stream
    }

    @discardableResult
    func add(magnet: String, saveDirectory: String, resumeData: Data?) async throws -> String {
        var params = try AddTorrentParams.fromMagnet(magnet, savePath: saveDirectory)
        if let resumeData, !resumeData.isEmpty {
            params.resumeData = try? ResumeData.decode(from: resumeData)
        }
        params.paused = true

        let handle = try await session.addTorrent(params)
        let infoHash = await handle.infoHash
        let taskID = Self.hex(infoHash.bytes)
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

    /// 取当前任务的续传数据：已校验完成的分片位图 + 计数器。
    func resumeData(_ taskID: String) async -> Data? {
        guard let entry = entries[taskID] else { return nil }
        let data = await entry.handle.generateResumeData()
        return data?.encode()
    }

    func remove(_ taskID: String, deleteData: Bool) async throws {
        guard let entry = entries.removeValue(forKey: taskID) else { return }
        // SwiftTorrent 的 deleteFiles 会删掉整个 savePath，粒度太粗；文件删除交给 FileStore。
        latestStatus[taskID] = nil
        pendingSelection[taskID] = nil
        let infoHash = await entry.handle.infoHash
        await session.removeTorrent(infoHash, deleteFiles: false)
        await emitAll()
    }

    func contains(_ taskID: String) -> Bool {
        entries[taskID] != nil
    }

    func selectFiles(_ taskID: String, indexes: Set<Int>) async throws {
        guard let entry = entries[taskID] else { return }
        if await entry.handle.getFiles() != nil {
            await entry.handle.setSelectedFiles(indexes)
            pendingSelection[taskID] = nil
        } else {
            // 磁力任务还没拿到元数据，先记下来，metadata 到达后再下发。
            pendingSelection[taskID] = indexes
        }
        await emitAll()
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

    private func startAlertObservation() {
        guard alertTask == nil else { return }
        alertTask = Task { [weak self] in
            guard let self else { return }
            let alerts = await self.session.alerts
            for await alert in alerts {
                if let line = Self.describe(alert) {
                    self.eventContinuation?.yield(line)
                }
            }
        }
    }

    private static func describe(_ alert: any Alert) -> String? {
        switch alert {
        case let a as TorrentAddedAlert:
            return "已加入：\(a.name)"
        case let a as TorrentRemovedAlert:
            return "已移除任务 \(a.infoHash)"
        case let a as TorrentFinishedAlert:
            return "下载完成 \(a.infoHash)"
        case let a as StateChangedAlert:
            return "状态变化 \(a.previousState.rawValue) → \(a.newState.rawValue)"
        case let a as TrackerErrorAlert:
            return "Tracker 错误 \(a.url)：\(a.message)"
        case let a as FileErrorAlert:
            return "文件错误 \(a.path)：\(a.error)"
        case let a as HashFailedAlert:
            return "分片校验失败 piece \(a.pieceIndex)"
        default:
            return nil
        }
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
            if let pending = pendingSelection[taskID], !files.isEmpty {
                await entry.handle.setSelectedFiles(pending)
                pendingSelection[taskID] = nil
            }
            let mapped = Self.makeStatus(
                status,
                taskID: taskID,
                entry: entry,
                files: files,
                seedingEnabled: seedingEnabled
            )
            latestStatus[taskID] = mapped
            continuation.yield(mapped)
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
