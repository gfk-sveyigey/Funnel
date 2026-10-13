import Foundation

/// 引擎注入的唯一出口。UI / 保活 / 持久化都只依赖 `TorrentEngineProtocol`。
@MainActor
enum EngineFactory {

    enum Kind {
        /// 纯 Swift 引擎（SPM），见 docs/M0-ENGINE.md。
        case swiftTorrent
        /// 占位引擎：无网络依赖，便于 UI 开发，或在许可证未解决时回退。
        case simulated
    }

    /// 当前默认引擎。要回退到占位引擎，把这里改成 `.simulated`。
    static let kind: Kind = .swiftTorrent

    static func makeDefault() -> TorrentEngineProtocol {
        switch kind {
        case .swiftTorrent:
            return SwiftTorrentEngine()
        case .simulated:
            return SimulatedTorrentEngine()
        }
    }
}
