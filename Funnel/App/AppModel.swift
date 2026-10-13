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
            try? await engine.pause(task.id)
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
                    // App 重启后引擎里的句柄已丢失，「继续」需要凭磁力重新加入。
                    // 已知限制：当前引擎不消费 resumeData，会重新校验/下载（见 docs/M0-ENGINE.md）。
                    let directory = try fileStore.prepareDirectory(relativePath: task.savePath)
                    try await engine.add(magnet: task.magnet, saveDirectory: directory.path)
                    logs.log("重启恢复：重新加入 \(task.name)", level: .warning)
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

    private func refreshKeepAlive() {
        let active = taskStore.tasks.filter(\.state.isActive).count
        keepAlive.update(activeTaskCount: active)
    }

    private func engineDisplayName(for magnet: String) -> String {
        SimulatedTorrentEngine.displayName(from: magnet)
            ?? SimulatedTorrentEngine.infoHash(from: magnet)
    }
}
