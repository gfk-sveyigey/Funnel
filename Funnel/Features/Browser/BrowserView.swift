import SwiftUI
import UIKit

/// 粘贴 / 接收磁力链接。
struct BrowserView: View {

    @Environment(AppModel.self) private var model
    @State private var magnet = ""

    private var trimmed: String {
        magnet.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GlassGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("粘贴磁力链接", systemImage: "link")
                            .font(.headline)
                        TextEditor(text: $magnet)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(minHeight: 140)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .glassCard(cornerRadius: 14, useGlass: model.settings.useLiquidGlass)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Button {
                        if let clip = UIPasteboard.general.string, !clip.isEmpty {
                            magnet = clip
                        }
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)

                    Button {
                        model.addMagnet(magnet)
                        magnet = ""
                    } label: {
                        Label("添加任务", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(trimmed.isEmpty)
                }

                if !model.taskStore.tasks.isEmpty {
                    Text("最近任务")
                        .font(.headline)
                        .padding(.top, 8)
                    ForEach(model.taskStore.tasks.prefix(3)) { task in
                        TaskRow(task: task)
                            .glassCard(useGlass: model.settings.useLiquidGlass)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("浏览")
    }
}
