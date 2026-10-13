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

            Section("位置") {
                LabeledContent("目录", value: task.savePath)
                if model.fileStore.exists(model.fileStore.url(forRelativePath: task.savePath)) {
                    ShareLink(item: model.fileStore.url(forRelativePath: task.savePath)) {
                        Label("分享下载目录", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Text("尚未落盘")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !task.files.isEmpty {
                Section("文件") {
                    ForEach(task.files) { file in
                        fileRow(task: task, file: file)
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

    /// 单个文件行：选中开关 + 已落盘则分享、完成后仍缺失则标记。
    @ViewBuilder
    private func fileRow(task: TorrentTask, file: TorrentFile) -> some View {
        let url = model.fileStore.url(forRelativePath: task.savePath).appendingPathComponent(file.path)
        let exists = model.fileStore.exists(url)
        let finished = task.state == .completed || task.state == .seeding

        HStack {
            Button {
                model.toggleFileSelection(task, file: file)
            } label: {
                Image(systemName: file.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(file.isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.path)
                    .lineLimit(1)
                if file.isSelected && file.length > 0 {
                    ProgressView(value: file.progress)
                    Text("\(file.downloaded.formattedBytes) / \(file.length.formattedBytes)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(file.length.formattedBytes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if exists {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
            } else if finished {
                Text("缺失")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
