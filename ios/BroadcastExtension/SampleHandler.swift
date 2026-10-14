import Foundation
import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private enum StopReason {
        case timeLimit
        case lowStorage
        case writeFailed

        func error(saved: Bool) -> NSError {
            let savedNote = saved
                ? "Видео сохранено в «Фото»."
                : "Откройте приложение «Запись экрана», чтобы сохранить видео."
            let message: String
            switch self {
            case .timeLimit:
                message = "Прошёл 1 час — запись остановлена автоматически. \(savedNote)"
            case .lowStorage:
                message = "На iPhone заканчивается память — запись остановлена. \(savedNote)"
            case .writeFailed:
                message = "Не удалось записать видео. Попробуйте ещё раз."
            }
            return NSError(domain: "ScreenRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private var writer: RecordingWriter?
    private var watchdog: DispatchSourceTimer?
    private var startDate = Date()
    private let finalizeLock = NSLock()
    private var didFinalize = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard SharedConfig.freeDiskSpace() >= SharedConfig.minFreeBytesToStart else {
            finishBroadcastWithError(NSError(
                domain: "ScreenRecorder",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Недостаточно свободной памяти на iPhone для записи. Освободите хотя бы 500 МБ."]
            ))
            return
        }

        do {
            writer = try RecordingWriter(outputURL: Self.makeOutputURL())
        } catch {
            finishBroadcastWithError(error)
            return
        }

        startDate = Date()
        SharedConfig.sharedDefaults?.set(startDate, forKey: SharedConfig.Keys.startedAt)
        startWatchdog()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard let writer, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        switch sampleBufferType {
        case .video:
            writer.appendVideo(sampleBuffer)
        case .audioApp:
            writer.appendAudio(sampleBuffer, source: .app)
        case .audioMic:
            writer.appendAudio(sampleBuffer, source: .microphone)
        @unknown default:
            break
        }
    }

    override func broadcastFinished() {
        _ = finalizeRecording()
    }

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.checkLimits()
        }
        timer.resume()
        watchdog = timer
    }

    private func checkLimits() {
        if Date().timeIntervalSince(startDate) >= SharedConfig.maxDuration {
            stop(reason: .timeLimit)
        } else if SharedConfig.freeDiskSpace() < SharedConfig.minFreeBytesWhileRecording {
            stop(reason: .lowStorage)
        } else if writer?.hasFailed == true {
            stop(reason: .writeFailed)
        }
    }

    private func stop(reason: StopReason) {
        guard let saved = finalizeRecording() else { return }
        finishBroadcastWithError(reason.error(saved: saved))
    }

    /// Finalizes the file and moves it into Photos. Returns nil if already finalized,
    /// otherwise whether the video reached the Photos library.
    private func finalizeRecording() -> Bool? {
        finalizeLock.lock()
        defer { finalizeLock.unlock() }

        guard !didFinalize else { return nil }
        didFinalize = true

        watchdog?.cancel()
        watchdog = nil
        defer { SharedConfig.sharedDefaults?.removeObject(forKey: SharedConfig.Keys.startedAt) }

        guard let fileURL = writer?.finish(timeout: 20) else {
            SharedConfig.sharedDefaults?.set(SharedConfig.Result.failed.rawValue, forKey: SharedConfig.Keys.lastResult)
            return false
        }

        if PhotoSaver.saveVideoAndWait(at: fileURL, timeout: 25) {
            try? FileManager.default.removeItem(at: fileURL)
            SharedConfig.sharedDefaults?.set(SharedConfig.Result.savedToPhotos.rawValue, forKey: SharedConfig.Keys.lastResult)
            return true
        }

        SharedConfig.sharedDefaults?.set(SharedConfig.Result.pending.rawValue, forKey: SharedConfig.Keys.lastResult)
        return false
    }

    private static func makeOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "ScreenRecording_\(formatter.string(from: Date())).mp4"
        let directory = SharedConfig.pendingDirectory ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent(name)
    }
}
