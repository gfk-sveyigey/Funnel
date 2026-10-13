import SwiftUI

struct TaskListView: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if model.taskStore.tasks.isEmpty {
                ContentUnavailableView(
                    "还没有任务",
                    systemImage: "arrow.down.circle",
                    description: Text("在「浏览」里粘贴磁力链接开始下载")
                )
            } else {
                ForEach(model.taskStore.tasks) { task in
                    NavigationLink(value: task) {
                        TaskRow(task: task)
                    }
                }
            }
        }
        .navigationTitle("任务")
        .navigationDestination(for: TorrentTask.self) { task in
            TaskDetailView(taskID: task.id)
        }
    }
}

struct TaskRow: View {
    let task: TorrentTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: task.state.systemImage)
                    .foregroundStyle(.tint)
                Text(task.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(task.state.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: task.progress)

            HStack {
                Text("\(task.downloadedBytes.formattedBytes) / \(task.totalBytes.formattedBytes)")
                Spacer()
                if task.downloadSpeed > 0 {
                    Text(task.downloadSpeed.formattedSpeed)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
