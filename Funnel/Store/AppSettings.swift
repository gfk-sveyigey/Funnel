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

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let keepAliveMode = "settings.keepAliveMode"
        static let seedAfterCompletion = "settings.seedAfterCompletion"
        static let useLiquidGlass = "settings.useLiquidGlass"
    }

    init() {
        let defaults = UserDefaults.standard
        let rawMode = defaults.string(forKey: Keys.keepAliveMode) ?? KeepAliveMode.silentAudio.rawValue
        keepAliveMode = KeepAliveMode(rawValue: rawMode) ?? .silentAudio
        seedAfterCompletion = defaults.object(forKey: Keys.seedAfterCompletion) as? Bool ?? false
        useLiquidGlass = defaults.object(forKey: Keys.useLiquidGlass) as? Bool ?? true
    }
}
