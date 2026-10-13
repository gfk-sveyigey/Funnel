import Foundation

/// 引擎门面：UI / 保活 / 持久化只依赖这个协议，
/// 因此 SwiftyTorrent 不可用时可以整体替换为 libtorrent（M0 预案），UI 层零改动。
@MainActor
protocol TorrentEngineProtocol: AnyObject {
    var engineName: String { get }

    /// 添加磁力任务，返回任务 id（用 info hash）。
    /// - Parameter resumeData: 续传数据（resumeData(_:) 的产出）；nil 表示从零开始。
    @discardableResult
    func add(magnet: String, saveDirectory: String, resumeData: Data?) async throws -> String
    /// 取某任务的续传数据供持久化；引擎没有该任务时返回 nil。
    func resumeData(_ taskID: String) async -> Data?
    func pause(_ taskID: String) async throws
    func resume(_ taskID: String) async throws
    func remove(_ taskID: String, deleteData: Bool) async throws
    /// 引擎中当前是否存在该任务的运行时句柄（App 重启后为 false）。
    /// UI 用它判断「继续」是走引擎 resume，还是凭磁力重新加入。
    func contains(_ taskID: String) -> Bool
    /// 只下载选中的文件（多文件种子）。
    func selectFiles(_ taskID: String, indexes: Set<Int>) async throws
    func setDownloadLimit(bytesPerSecond: Int?)
    /// 完成后是否继续做种。
    func setSeedingEnabled(_ enabled: Bool)

    /// 全量状态流：UI 订阅后同步任务列表。
    func statusStream() -> AsyncStream<TorrentTaskStatus>
    func snapshot(_ taskID: String) -> TorrentTaskStatus?

    /// 引擎侧事件（tracker / peer / 错误）文本流，供 UI 记日志。
    func eventStream() -> AsyncStream<String>
}

@MainActor
extension TorrentEngineProtocol {
    /// 从零开始添加任务（无续传数据）。
    @discardableResult
    func add(magnet: String, saveDirectory: String) async throws -> String {
        try await add(magnet: magnet, saveDirectory: saveDirectory, resumeData: nil)
    }
}
