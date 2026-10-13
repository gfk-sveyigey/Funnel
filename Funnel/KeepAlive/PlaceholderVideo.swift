import AVFoundation
import Foundation

/// 运行时生成一段极短的深色静音视频，供 PiP 保活循环播放，避免依赖二进制资源。
enum PlaceholderVideo {

    static func url() throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent("funnel-pip-placeholder.mp4")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let size = CGSize(width: 16, height: 16)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height)
            ]
        )
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )

        guard writer.canAdd(input) else { throw KeepAliveError.unsupported("占位视频") }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps: Int32 = 24
        let frameCount = 48
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let pixelBuffer = buffer else { break }

            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                memset(base, 0x1A, bytesPerRow * height)
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

            let time = CMTime(value: CMTimeValue(frame), timescale: fps)
            adaptor.append(pixelBuffer, withPresentationTime: time)
        }
        input.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()

        guard writer.status == .completed else { throw KeepAliveError.unsupported("占位视频") }
        return url
    }
}
