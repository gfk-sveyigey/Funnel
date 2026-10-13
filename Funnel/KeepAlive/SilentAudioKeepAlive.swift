import AVFoundation

/// 静音音频保活：`.playback` 会话 + 循环播放极短静音文件。
@MainActor
final class SilentAudioKeepAlive: KeepAliveStrategy {

    let name = "静音音频"
    private(set) var isActive = false
    var onInterruption: (() -> Void)?

    private var player: AVAudioPlayer?
    private var observer: NSObjectProtocol?

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)

        let player = try AVAudioPlayer(data: Self.silentWAV())
        player.numberOfLoops = -1
        player.volume = 0
        player.prepareToPlay()
        player.play()
        self.player = player
        isActive = true

        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
            Task { @MainActor in self?.onInterruption?() }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        isActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 生成一段极短的静音 WAV，避免依赖资源文件。
    static func silentWAV(sampleRate: Int = 8000, duration: Double = 0.1) -> Data {
        let frames = Int(Double(sampleRate) * duration)
        let bitsPerSample = 16
        let channels = 1
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = frames * blockAlign

        var data = Data()
        func appendUInt32(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func appendUInt16(_ value: UInt16) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func appendASCII(_ string: String) {
            data.append(contentsOf: Array(string.utf8))
        }

        appendASCII("RIFF")
        appendUInt32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(UInt16(channels))
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(byteRate))
        appendUInt16(UInt16(blockAlign))
        appendUInt16(UInt16(bitsPerSample))
        appendASCII("data")
        appendUInt32(UInt32(dataSize))
        data.append(Data(count: dataSize))
        return data
    }
}
