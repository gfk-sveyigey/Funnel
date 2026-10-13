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
            tasks.append(TorrentTask(status: status))
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
