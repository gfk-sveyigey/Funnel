import Foundation
import Observation

@Observable
final class AppSettings {

    var keepAliveMode: KeepAliveMode {
        didSet { defaults.set(keepAliveMode.rawValue, forKey: Keys.keepAliveMode) }
    }
    var seedAfterCompletion: Bool {
        didSet { defaults.set(seedAfterCompletion, forKey: Keys.seedAfterCompletion) }
    }
    var useLiquidGlass: Bool {
        didSet { defaults.set(useLiquidGlass, forKey: Keys.useLiquidGlass) }
    }
    /// 下载限速，单位 MB/s；0 表示不限速。
    var downloadLimitMBps: Int {
        didSet { defaults.set(downloadLimitMBps, forKey: Keys.downloadLimitMBps) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let keepAliveMode = "settings.keepAliveMode"
        static let seedAfterCompletion = "settings.seedAfterCompletion"
        static let useLiquidGlass = "settings.useLiquidGlass"
        static let downloadLimitMBps = "settings.downloadLimitMBps"
    }

    init() {
        let defaults = UserDefaults.standard
        let rawMode = defaults.string(forKey: Keys.keepAliveMode) ?? KeepAliveMode.silentAudio.rawValue
        keepAliveMode = KeepAliveMode(rawValue: rawMode) ?? .silentAudio
        seedAfterCompletion = defaults.object(forKey: Keys.seedAfterCompletion) as? Bool ?? false
        useLiquidGlass = defaults.object(forKey: Keys.useLiquidGlass) as? Bool ?? true
        downloadLimitMBps = defaults.object(forKey: Keys.downloadLimitMBps) as? Int ?? 0
    }
}
