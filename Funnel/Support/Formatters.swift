import Foundation

extension Int64 {
    /// 人类可读的字节数，如 `512 MB`。
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }

    /// 速度，如 `3.2 MB/s`。
    var formattedSpeed: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file) + "/s"
    }
}
