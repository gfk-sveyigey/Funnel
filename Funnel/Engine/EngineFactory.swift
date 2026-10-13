import Foundation

/// 引擎注入的唯一出口。
/// - M0 判定「可行」→ 换成 `SwiftyTorrentEngine`
/// - M0 判定「不可行」→ 换成 `LibTorrentEngine`（接口已预留）
/// UI / 保活 / 持久化都只依赖 `TorrentEngineProtocol`，替换时零改动。
@MainActor
enum EngineFactory {
    static func makeDefault() -> TorrentEngineProtocol {
        SimulatedTorrentEngine()
    }
}
