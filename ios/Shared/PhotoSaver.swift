import Foundation
import Photos

enum PhotoSaver {
    static func saveVideo(at url: URL, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = url.lastPathComponent
            request.addResource(with: .video, fileURL: url, options: options)
        }, completionHandler: { success, _ in
            completion(success)
        })
    }

    /// Blocking variant for the broadcast extension, which is terminated as soon as `broadcastFinished` returns.
    static func saveVideoAndWait(at url: URL, timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var saved = false
        saveVideo(at: url) { success in
            saved = success
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        return saved
    }
}
