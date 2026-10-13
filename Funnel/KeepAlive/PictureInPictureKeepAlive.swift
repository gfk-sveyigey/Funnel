import AVFoundation
import AVKit
import UIKit

/// 画中画保活：挂一个循环占位视频，用户可见、可主动关闭。
/// 注意：iOS 没有真正的「悬浮窗权限」，PiP 是唯一可浮层形式，它只作为保活载体。
@MainActor
final class PictureInPictureKeepAlive: NSObject, KeepAliveStrategy {

    let name = "画中画 (PiP)"
    private(set) var isActive = false
    var onInterruption: (() -> Void)?

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var controller: AVPictureInPictureController?

    func start() throws {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            throw KeepAliveError.unsupported(name)
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .moviePlayback, options: [])
        try session.setActive(true)

        let item = AVPlayerItem(url: try PlaceholderVideo.url())
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        self.player = player

        let layer = AVPlayerLayer(player: player)
        layer.frame = CGRect(x: 0, y: 0, width: 16, height: 16)
        self.playerLayer = layer
        attach(layer)

        guard let controller = AVPictureInPictureController(playerLayer: layer) else {
            throw KeepAliveError.unsupported(name)
        }
        controller.delegate = self
        self.controller = controller

        player.play()
        controller.startPictureInPicture()
        isActive = true
    }

    func stop() {
        controller?.stopPictureInPicture()
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        controller = nil
        playerLayer = nil
        player = nil
        isActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func attach(_ layer: AVPlayerLayer) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })
        else { return }
        window.layer.addSublayer(layer)
    }
}

extension PictureInPictureKeepAlive: @preconcurrency AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        // 用户主动关闭 PiP → 交给协调器按降级链处理。
        Task { @MainActor in self.onInterruption?() }
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in self.onInterruption?() }
    }
}
