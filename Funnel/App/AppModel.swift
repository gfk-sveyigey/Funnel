import Foundation
import Observation
import SwiftUI

/// 组合根：持有引擎、任务存储、文件与日志、设置、保活协调器。
@MainActor
@Observable
final class AppModel {

    let engine: TorrentEngineProtocol
    let taskStore: TorrentTaskStore
    let fileStore: FileStore
    let keepAlive: KeepAliveCoordinator
    let logs: LogStore
    let settings: AppSettings

    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var resumeTask: Task<Void, Never>?

    init() {
        let logs = LogStore()
        let fileStore = FileStore()
        let settings = AppSettings()
        let engine = EngineFactory.makeDefault()

        self.logs = logs
        self.fileStore = fileStore
        self.settings = settings
        self.engine = engine
        taskStore = TorrentTaskStore(fileStore: fileStore)
        keepAlive = KeepAliveCoordinator()
        keepAlive.preferredMode = settings.keepAliveMode

        engine.setDownloadLimit(bytesPerSecond: settings.downloadLimitMBps > 0 ? settings.downloadLimitMBps * 1_048_576 : nil)
        engine.setSeedingEnabled(settings.seedAfterCompletion)

        logs.log("Funnel 启动，引擎：\(engine.engineName)")
        let interrupted = taskStore.reconcileInterruptedTasks()
        if interrupted > 0 {
            logs.log("上次退出时有 \(interrupted) 个任务被中断，已置为暂停", level: .warning)
        }
        startStatusObservation()
        startEventObservation()
        startResumePersistence()
    }

    // MARK: - 操作

    func addMagnet(_ raw: String) {
        let magnet = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard magnet.lowercased().hasPrefix("magnet:") else {
            logs.log("不是有效的磁力链接", level: .error)
            return
        }
        Task {
            do {
                let directory = try fileStore.prepareDirectory(forName: engineDisplayName(for: magnet))
                let id = try await engine.add(magnet: magnet, saveDirectory: directory.path)
                logs.log("已添加任务 \(id)")
                refreshKeepAlive()
            } catch {
                logs.log("添加失败：\(error.localizedDescription)", level: .error)
            }
        }
    }

    func pause(_ task: TorrentTask) {
        Task {
            let data = await engine.resumeData(task.id)
            try? await engine.pause(task.id)
            taskStore.setResumeData(data, for: task.id)
            logs.log("暂停 \(task.name)")
            refreshKeepAlive()
        }
    }

    func resume(_ task: TorrentTask) {
        Task {
            do {
                if engine.contains(task.id) {
                    try await engine.resume(task.id)
                    logs.log("继续 \(task.name)")
                } else {
                    // App 重启后引擎里的句柄已丢失：凭磁力 + 续传数据重新加入，
                    // 引擎会哈希校验磁盘上已存在的分片，只补下缺失部分。
                    let directory = try fileStore.prepareDirectory(relativePath: task.savePath)
                    let resumeData = taskStore.resumeData(for: task.id)
                    try await engine.add(
                        magnet: task.magnet,
                        saveDirectory: directory.path,
                        resumeData: resumeData
                    )
                    // 还原之前的按文件选择（全部选中则不必下发）。
                    let selected = Set(task.files.filter(\.isSelected).map(\.index))
                    if !selected.isEmpty, selected.count < task.files.count {
                        try? await engine.selectFiles(task.id, indexes: selected)
                    }
                    logs.log("重启恢复：重新加入 \(task.name)（校验后继续）")
                }
                refreshKeepAlive()
            } catch {
                logs.log("继续失败：\(error.localizedDescription)", level: .error)
            }
        }
    }

    func remove(_ task: TorrentTask, deleteData: Bool) {
        Task {
            try? await engine.remove(task.id, deleteData: deleteData)
            taskStore.remove(id: task.id, deleteData: deleteData)
            logs.log(deleteData ? "删除任务与文件 \(task.name)" : "移除任务 \(task.name)")
            refreshKeepAlive()
        }
    }

    func toggleFileSelection(_ task: TorrentTask, file: TorrentFile) {
        var selected = Set(task.files.filter(\.isSelected).map(\.index))
        if selected.contains(file.index) {
            selected.remove(file.index)
        } else {
            selected.insert(file.index)
        }
        Task {
            try? await engine.selectFiles(task.id, indexes: selected)
        }
    }

    func setKeepAliveMode(_ mode: KeepAliveMode) {
        settings.keepAliveMode = mode
        keepAlive.preferredMode = mode
        logs.log("保活模式切换为 \(mode.title)")
        refreshKeepAlive()
    }

    func setDownloadLimitMBps(_ mbps: Int) {
        settings.downloadLimitMBps = mbps
        engine.setDownloadLimit(bytesPerSecond: mbps > 0 ? mbps * 1_048_576 : nil)
        logs.log(mbps > 0 ? "下载限速：\(mbps) MB/s" : "下载限速：不限")
    }

    func setSeedingEnabled(_ enabled: Bool) {
        settings.seedAfterCompletion = enabled
        engine.setSeedingEnabled(enabled)
        logs.log(enabled ? "完成后继续做种：开" : "完成后继续做种：关")
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        keepAlive.scenePhase = phase
        refreshKeepAlive()
        if phase != .active {
            persistResumeData()
        }
    }

    // MARK: - 内部

    private func startStatusObservation() {
        statusTask?.cancel()
        statusTask = Task { [engine, taskStore, weak self] in
            for await status in engine.statusStream() {
                taskStore.upsert(status)
                self?.refreshKeepAlive()
            }
        }
        refreshKeepAlive()
    }

    private func startEventObservation() {
        eventTask?.cancel()
        eventTask = Task { [engine, logs] in
            for await line in engine.eventStream() {
                logs.log(line)
            }
        }
    }

    /// 定期把任务的续传数据写盘，尽量减小被系统强杀时的进度损失。
    private func startResumePersistence() {
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, !Task.isCancelled else { break }
                self.persistResumeData()
            }
        }
    }

    /// 抓取「进行中或已完成」任务的续传数据并持久化。
    private func persistResumeData() {
        let ids = taskStore.tasks
            .filter { $0.state.isActive || $0.state == .completed }
            .map { $0.id }
        guard !ids.isEmpty else { return }
        Task { [engine, taskStore] in
            for id in ids {
                if let data = await engine.resumeData(id) {
                    taskStore.setResumeData(data, for: id)
                }
            }
        }
    }

    private func refreshKeepAlive() {
        let active = taskStore.tasks.filter(\.state.isActive).count
        keepAlive.update(activeTaskCount: active)
    }

    private func engineDisplayName(for magnet: String) -> String {
        SimulatedTorrentEngine.displayName(from: magnet)
            ?? SimulatedTorrentEngine.infoHash(from: magnet)
    }
}
