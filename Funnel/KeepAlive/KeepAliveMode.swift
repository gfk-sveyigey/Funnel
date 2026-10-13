import Foundation

/// 保活方式，设置项可选。
enum KeepAliveMode: String, CaseIterable, Identifiable, Codable {
    case off
    case silentAudio
    case pictureInPicture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "关闭"
        case .silentAudio: return "静音音频"
        case .pictureInPicture: return "画中画 (PiP)"
        }
    }

    var detail: String {
        switch self {
        case .off: return "不保活，切后台可能被系统挂起。"
        case .silentAudio: return "循环播放极短静音，无界面侵入、最稳。"
        case .pictureInPicture: return "挂循环占位视频，用户可见、可主动关闭。"
        }
    }
}
