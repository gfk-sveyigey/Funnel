import Foundation
import Observation

@Observable
final class LogStore {

    enum Level: String {
        case info
        case warning
        case error

        var systemImage: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            }
        }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let level: Level
        let message: String

        var line: String {
            "[\(Self.formatter.string(from: date))] [\(level.rawValue.uppercased())] \(message)"
        }

        private static let formatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
    }

    private(set) var entries: [Entry] = []
    private let limit = 500

    func log(_ message: String, level: Level = .info) {
        entries.append(Entry(date: Date(), level: level, message: message))
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    /// 导出为 Documents/funnel.log，供「文件」App 或分享面板取用。
    func exportURL() throws -> URL {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("funnel.log")
        let text = entries.map(\.line).joined(separator: "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
