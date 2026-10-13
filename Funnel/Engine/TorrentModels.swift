import Foundation

/// 任务在生命周期中的阶段。
/// 注意：`metadata` 是「只有 info hash、还没有文件列表」的独立阶段，UI 需要单独表现。
enum TorrentTaskState: String, Codable, CaseIterable {
    case metadata
    case downloading
    case paused
    case seeding
    case completed
    case failed
    case stopped

    var title: String {
        switch self {
        case .metadata: return "获取元数据"
        case .downloading: return "下载中"
        case .paused: return "已暂停"
        case .seeding: return "做种中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .stopped: return "已停止"
        }
    }

    var systemImage: String {
        switch self {
        case .metadata: return "magnifyingglass"
        case .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .seeding: return "arrow.up.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .stopped: return "stop.circle.fill"
        }
    }

    /// 是否算「活跃任务」，用于保活启停判定。
    var isActive: Bool {
        switch self {
        case .metadata, .downloading, .seeding: return true
        default: return false
        }
    }
}

struct TorrentFile: Identifiable, Codable, Hashable {
    let index: Int
    var path: String
    var length: Int64
    var downloaded: Int64
    var isSelected: Bool

    var id: Int { index }
    var progress: Double { length > 0 ? Double(downloaded) / Double(length) : 0 }
}

struct TorrentTask: Identifiable, Codable, Hashable {
    let id: String
    var infoHash: String
    var magnet: String
    var name: String
    var state: TorrentTaskState
    var totalBytes: Int64
    var downloadedBytes: Int64
    var downloadSpeed: Int64
    var uploadSpeed: Int64
    var peerCount: Int
    var files: [TorrentFile]
    /// 只存相对 Documents 的路径（容器路径会变）。
    var savePath: String
    var errorMessage: String?
    /// 续传数据（引擎 ResumeData.encode() 的产物），用于重启后跳过已下载分片。
    var resumeData: Data?

    var progress: Double { totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0 }
}

extension TorrentTask {
    init(status: TorrentTaskStatus) {
        id = status.taskID
        infoHash = status.taskID
        magnet = status.magnet
        name = status.name
        state = status.state
        totalBytes = status.totalBytes
        downloadedBytes = status.downloadedBytes
        downloadSpeed = status.downloadSpeed
        uploadSpeed = status.uploadSpeed
        peerCount = status.peerCount
        files = status.files
        savePath = status.saveDirectory
        errorMessage = status.errorMessage
        resumeData = nil
    }

    mutating func apply(_ status: TorrentTaskStatus) {
        name = status.name
        state = status.state
        totalBytes = status.totalBytes
        downloadedBytes = status.downloadedBytes
        downloadSpeed = status.downloadSpeed
        uploadSpeed = status.uploadSpeed
        peerCount = status.peerCount
        files = status.files
        errorMessage = status.errorMessage
    }
}

/// 引擎 → UI 的单向状态推送载荷。
struct TorrentTaskStatus: Hashable {
    var taskID: String
    var magnet: String
    var state: TorrentTaskState
    var name: String
    var totalBytes: Int64
    var downloadedBytes: Int64
    var downloadSpeed: Int64
    var uploadSpeed: Int64
    var peerCount: Int
    var files: [TorrentFile]
    var saveDirectory: String
    var errorMessage: String?
}
