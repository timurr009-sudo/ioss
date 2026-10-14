import Combine
import Photos
import UIKit

final class RecorderModel: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var photoAccessDenied = false
    @Published private(set) var statusMessage: String?

    private var recordingStart: Date?
    private var ticker: AnyCancellable?
    private var captureObserver: NSObjectProtocol?
    private var hasStarted = false

    var progress: Double {
        min(elapsed / SharedConfig.maxDuration, 1)
    }

    deinit {
        if let captureObserver {
            NotificationCenter.default.removeObserver(captureObserver)
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        requestPhotoAccess()

        captureObserver = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }

        refresh()
        savePendingRecordings()
    }

    func appBecameActive() {
        refresh()
        checkPhotoAccess()
        savePendingRecordings()
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func refresh() {
        let captured = UIScreen.main.isCaptured
        let sharedStart = SharedConfig.sharedDefaults?.object(forKey: SharedConfig.Keys.startedAt) as? Date

        if captured {
            if let sharedStart {
                recordingStart = sharedStart
            } else if recordingStart == nil {
                recordingStart = Date()
            }
            if !isRecording {
                statusMessage = nil
            }
            isRecording = true
            elapsed = min(Date().timeIntervalSince(recordingStart ?? Date()), SharedConfig.maxDuration)
            return
        }

        if isRecording {
            statusMessage = "Запись остановлена. Сохраняем видео в «Фото»…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.showLastResult()
            }
        }
        isRecording = false
        recordingStart = nil
        elapsed = 0
    }

    private func showLastResult() {
        guard !isRecording else { return }
        let raw = SharedConfig.sharedDefaults?.string(forKey: SharedConfig.Keys.lastResult)
        switch raw.flatMap(SharedConfig.Result.init(rawValue:)) {
        case .failed:
            statusMessage = "Не удалось сохранить запись. Попробуйте ещё раз."
        case .pending:
            savePendingRecordings(ignoringAge: true)
        default:
            statusMessage = "Готово — видео сохранено в «Фото»."
        }
    }

    private func requestPhotoAccess() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            DispatchQueue.main.async {
                self?.photoAccessDenied = !(status == .authorized || status == .limited)
            }
        }
    }

    private func checkPhotoAccess() {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard status != .notDetermined else { return }
        photoAccessDenied = !(status == .authorized || status == .limited)
    }

    /// Picks up recordings the extension couldn't hand to Photos, saves them and deletes the local copy.
    private func savePendingRecordings(ignoringAge: Bool = false) {
        guard
            !UIScreen.main.isCaptured,
            let directory = SharedConfig.pendingDirectory,
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
        else { return }

        let now = Date()
        let videos = files.filter { url in
            guard url.pathExtension.lowercased() == "mp4" else { return false }
            if ignoringAge { return true }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return now.timeIntervalSince(modified ?? now) >= SharedConfig.pendingFileMinAge
        }

        for url in videos {
            PhotoSaver.saveVideo(at: url) { [weak self] saved in
                DispatchQueue.main.async {
                    if saved {
                        try? FileManager.default.removeItem(at: url)
                        SharedConfig.sharedDefaults?.set(SharedConfig.Result.savedToPhotos.rawValue, forKey: SharedConfig.Keys.lastResult)
                        self?.statusMessage = "Готово — видео сохранено в «Фото»."
                    } else {
                        self?.statusMessage = "Разрешите доступ к «Фото», чтобы сохранить запись."
                        self?.photoAccessDenied = true
                    }
                }
            }
        }
    }
}
