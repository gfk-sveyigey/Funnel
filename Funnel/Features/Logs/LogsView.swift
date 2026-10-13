import SwiftUI

struct LogsView: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if model.logs.entries.isEmpty {
                ContentUnavailableView("暂无日志", systemImage: "doc.text")
            } else {
                ForEach(model.logs.entries) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: entry.level.systemImage)
                            .foregroundStyle(color(for: entry.level))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.message)
                                .font(.callout)
                            Text(entry.date.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("日志")
    }

    private func color(for level: LogStore.Level) -> Color {
        switch level {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }
}
