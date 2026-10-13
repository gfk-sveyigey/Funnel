import Foundation
import Observation

/// 任务模型持久化与状态同步。
@MainActor
@Observable
final class TorrentTaskStore {

    private(set) var tasks: [TorrentTask] = []

    private let fileStore: FileStore
    private let persistenceURL: URL

    init(fileStore: FileStore) {
        self.fileStore = fileStore
        persistenceURL = fileStore.documentsURL.appendingPathComponent("tasks.json")
        load()
    }

    func task(withID id: String) -> TorrentTask? {
        tasks.first { $0.id == id }
    }

    func upsert(_ status: TorrentTaskStatus) {
        if let index = tasks.firstIndex(where: { $0.id == status.taskID }) {
            tasks[index].apply(status)
        } else {
            // 引擎给的是绝对路径，持久化只存相对 Documents 的路径（容器路径会变）。
            var task = TorrentTask(status: status)
            task.savePath = fileStore.relativePath(for: URL(fileURLWithPath: status.saveDirectory))
            tasks.append(task)
        }
        save()
    }

    func remove(id: String, deleteData: Bool) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        tasks.removeAll { $0.id == id }
        if deleteData {
            try? fileStore.remove(relativePath: task.savePath)
        }
        save()
    }

    /// 引擎状态没有持久化，重启后「下载中 / 获取元数据 / 做种中」都是过期状态。
    /// 先把它们置为「已暂停」，避免 UI 显示假进度，等用户手动继续。
    @discardableResult
    func reconcileInterruptedTasks() -> Int {
        var count = 0
        for index in tasks.indices where tasks[index].state.isActive {
            tasks[index].state = .paused
            tasks[index].downloadSpeed = 0
            tasks[index].uploadSpeed = 0
            count += 1
        }
        if count > 0 { save() }
        return count
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            // 持久化失败不应影响下载，忽略。
        }
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: persistenceURL),
            let decoded = try? JSONDecoder().decode([TorrentTask].self, from: data)
        else { return }
        tasks = decoded
    }
}
