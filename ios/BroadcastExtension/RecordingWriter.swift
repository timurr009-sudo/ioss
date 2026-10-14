import AVFoundation
import ReplayKit

/// Streams ReplayKit sample buffers straight to an MP4 on disk so memory stays far below
/// the ~50 MB limit iOS enforces on broadcast extensions, even for hour-long recordings.
final class RecordingWriter {
    enum AudioSource {
        case app
        case microphone
    }

    let outputURL: URL

    private let writer: AVAssetWriter
    private let appAudioInput: AVAssetWriterInput
    private let micAudioInput: AVAssetWriterInput
    private var videoInput: AVAssetWriterInput?
    private let queue = DispatchQueue(label: "screenrecorder.writer")

    private var sessionStarted = false
    private var sessionStartTime: CMTime = .invalid
    private var isFinishing = false

    var hasFailed: Bool {
        writer.status == .failed
    }

    init(outputURL: URL) throws {
        self.outputURL = outputURL
        try? FileManager.default.removeItem(at: outputURL)

        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = false

        appAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings(channels: 2))
        appAudioInput.expectsMediaDataInRealTime = true

        micAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings(channels: 1))
        micAudioInput.expectsMediaDataInRealTime = true

        if writer.canAdd(appAudioInput) { writer.add(appAudioInput) }
        if writer.canAdd(micAudioInput) { writer.add(micAudioInput) }
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        queue.sync {
            guard !isFinishing else { return }

            if videoInput == nil {
                guard !sessionStarted else { return }
                setUpVideoInput(from: sampleBuffer)
            }
            guard let videoInput else { return }

            if !sessionStarted {
                guard writer.startWriting() else { return }
                let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                writer.startSession(atSourceTime: startTime)
                sessionStartTime = startTime
                sessionStarted = true
            }

            guard writer.status == .writing, videoInput.isReadyForMoreMediaData else { return }
            videoInput.append(sampleBuffer)
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer, source: AudioSource) {
        queue.sync {
            guard !isFinishing, sessionStarted, writer.status == .writing else { return }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard CMTimeCompare(timestamp, sessionStartTime) >= 0 else { return }

            let input = source == .app ? appAudioInput : micAudioInput
            guard input.isReadyForMoreMediaData else { return }
            input.append(sampleBuffer)
        }
    }

    /// Finalizes the MP4. Returns the file URL on success, or nil if nothing usable was recorded.
    func finish(timeout: TimeInterval) -> URL? {
        let canFinish: Bool = queue.sync {
            guard !isFinishing else { return false }
            isFinishing = true
            return true
        }
        guard canFinish else { return nil }

        guard sessionStarted, writer.status == .writing else {
            if writer.status == .writing { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }

        videoInput?.markAsFinished()
        appAudioInput.markAsFinished()
        micAudioInput.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + timeout)

        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
        return outputURL
    }

    private func setUpVideoInput(from sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let width = CVPixelBufferGetWidth(imageBuffer) & ~1
        let height = CVPixelBufferGetHeight(imageBuffer) & ~1
        let bitRate = min(max(Int(Double(width * height) * 1.5), 2_500_000), 8_000_000)

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ] as [String: Any],
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        input.transform = Self.transform(for: sampleBuffer)

        guard writer.canAdd(input) else { return }
        writer.add(input)
        videoInput = input
    }

    /// ReplayKit always delivers portrait buffers and reports the device rotation as an attachment.
    private static func transform(for sampleBuffer: CMSampleBuffer) -> CGAffineTransform {
        guard
            let value = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
            let orientation = CGImagePropertyOrientation(rawValue: value.uint32Value)
        else { return .identity }

        switch orientation {
        case .left, .leftMirrored:
            return CGAffineTransform(rotationAngle: -.pi / 2)
        case .right, .rightMirrored:
            return CGAffineTransform(rotationAngle: .pi / 2)
        case .down, .downMirrored:
            return CGAffineTransform(rotationAngle: .pi)
        default:
            return .identity
        }
    }

    private static func audioSettings(channels: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels == 1 ? 64_000 : 128_000,
        ]
    }
}
