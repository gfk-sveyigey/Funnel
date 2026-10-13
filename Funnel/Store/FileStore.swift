import Foundation

/// 负责 Documents 落盘与目录管理。
/// 持久化只存相对文件名（容器路径会变），与现有约定一致。
final class FileStore {

    let documentsURL: URL
    private let fileManager = FileManager.default

    init() {
        documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var downloadsRoot: URL {
        documentsURL.appendingPathComponent("Downloads", isDirectory: true)
    }

    /// 为任务建目录，返回**绝对** URL（引擎落盘需要绝对路径）。
    func prepareDirectory(forName name: String) throws -> URL {
        let directory = downloadsRoot.appendingPathComponent(Self.sanitize(name), isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func url(forRelativePath path: String) -> URL {
        documentsURL.appendingPathComponent(path)
    }

    func relativePath(for url: URL) -> String {
        let base = documentsURL.standardizedFileURL.path
        let target = url.standardizedFileURL.path
        guard target.hasPrefix(base) else { return url.lastPathComponent }
        return String(target.dropFirst(base.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func remove(relativePath: String) throws {
        let url = self.url(forRelativePath: relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "download" : cleaned
    }
}
