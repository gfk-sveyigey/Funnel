import SwiftUI

struct SettingsView: View {

    @Environment(AppModel.self) private var model
    @State private var exportedLog: URL?

    var body: some View {
        @Bindable var settings = model.settings

        Form {
            Section("保活") {
                Picker("保活方式", selection: Binding(
                    get: { model.settings.keepAliveMode },
                    set: { model.setKeepAliveMode($0) }
                )) {
                    ForEach(KeepAliveMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Text(model.settings.keepAliveMode.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(model.keepAlive.activeMode == .off
                     ? "当前未保活"
                     : "当前保活：\(model.keepAlive.activeMode.title)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let error = model.keepAlive.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("外观") {
                Toggle("液态玻璃效果", isOn: $settings.useLiquidGlass)
                Text("关闭或系统开启「降低透明度」时，自动回退为毛玻璃。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("下载") {
                Toggle("完成后继续做种", isOn: $settings.seedAfterCompletion)
                    .onChange(of: settings.seedAfterCompletion) { _, newValue in
                        model.setSeedingEnabled(newValue)
                    }

                Picker("下载限速", selection: $settings.downloadLimitMBps) {
                    Text("不限").tag(0)
                    Text("1 MB/s").tag(1)
                    Text("2 MB/s").tag(2)
                    Text("5 MB/s").tag(5)
                    Text("10 MB/s").tag(10)
                }
                .onChange(of: settings.downloadLimitMBps) { _, newValue in
                    model.setDownloadLimitMBps(newValue)
                }
            }

            Section("日志") {
                Button("导出日志") {
                    exportedLog = try? model.logs.exportURL()
                }
                Text("共 \(model.logs.entries.count) 条")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .sheet(isPresented: Binding(
            get: { exportedLog != nil },
            set: { if !$0 { exportedLog = nil } }
        )) {
            if let exportedLog {
                ShareLink(item: exportedLog) {
                    Label("分享日志文件", systemImage: "square.and.arrow.up")
                }
                .padding()
            }
        }
    }
}
