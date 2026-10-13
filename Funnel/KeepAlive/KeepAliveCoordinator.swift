import Foundation
import Observation
import SwiftUI

/// 保活调度：有活跃任务时启动、全部暂停 / 完成时停止，失败时按降级链回退。
@MainActor
@Observable
final class KeepAliveCoordinator {

    private(set) var activeMode: KeepAliveMode = .off
    private(set) var lastError: String?

    var preferredMode: KeepAliveMode = .silentAudio
    var scenePhase: ScenePhase = .active

    private let silentAudio = SilentAudioKeepAlive()
    private let pictureInPicture = PictureInPictureKeepAlive()
    private var hasActiveTasks = false

    init() {
        silentAudio.onInterruption = { [weak self] in self?.handleInterruption() }
        pictureInPicture.onInterruption = { [weak self] in self?.handleInterruption() }
    }

    func update(activeTaskCount: Int) {
        hasActiveTasks = activeTaskCount > 0
        reconcile()
    }

    // MARK: - 内部

    private func reconcile() {
        guard hasActiveTasks, preferredMode != .off else {
            deactivate()
            return
        }
        activate(preferredMode)
    }

    private func activate(_ mode: KeepAliveMode) {
        guard activeMode != mode else { return }
        stopAll()
        do {
            switch mode {
            case .off:
                break
            case .silentAudio:
                try silentAudio.start()
            case .pictureInPicture:
                try pictureInPicture.start()
            }
            activeMode = mode
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            // 降级链：PiP 失败 → 静音音频；静音音频失败 → 关闭。
            if mode == .pictureInPicture {
                activeMode = .off
                activate(.silentAudio)
            } else {
                activeMode = .off
            }
        }
    }

    private func deactivate() {
        stopAll()
        activeMode = .off
    }

    private func stopAll() {
        if silentAudio.isActive { silentAudio.stop() }
        if pictureInPicture.isActive { pictureInPicture.stop() }
    }

    private func handleInterruption() {
        guard hasActiveTasks, preferredMode != .off else { return }
        if activeMode == .pictureInPicture {
            // PiP 被关闭 / 启动失败 → 降级到静音音频。
            activeMode = .off
            activate(.silentAudio)
        } else {
            stopAll()
            activeMode = .off
            reconcile()
        }
    }
}
