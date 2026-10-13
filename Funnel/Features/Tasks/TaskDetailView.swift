import SwiftUI

struct TaskDetailView: View {

    @Environment(AppModel.self) private var model
    let taskID: String

    private var task: TorrentTask? {
        model.taskStore.task(withID: taskID)
    }

    var body: some View {
        Group {
            if let task {
                content(for: task)
            } else {
                ContentUnavailableView("任务不存在", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(task?.name ?? "任务")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(for task: TorrentTask) -> some View {
        List {
            Section("概览") {
                LabeledContent("状态", value: task.state.title)
                LabeledContent("进度", value: task.progress.formatted(.percent.precision(.fractionLength(1))))
                LabeledContent("已下载", value: "\(task.downloadedBytes.formattedBytes) / \(task.totalBytes.formattedBytes)")
                LabeledContent("速度", value: task.downloadSpeed > 0 ? task.downloadSpeed.formattedSpeed : "—")
                LabeledContent("节点", value: "\(task.peerCount)")
            }

            if !task.files.isEmpty {
                Section("文件") {
                    ForEach(task.files) { file in
                        Button {
                            model.toggleFileSelection(task, file: file)
                        } label: {
                            HStack {
                                Image(systemName: file.isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(file.isSelected ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.path)
                                        .lineLimit(1)
                                    Text(file.length.formattedBytes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Button("暂停") { model.pause(task) }
                Button("继续") { model.resume(task) }
                Button("移除任务", role: .destructive) { model.remove(task, deleteData: false) }
                Button("移除任务与文件", role: .destructive) { model.remove(task, deleteData: true) }
            }
        }
    }
}
