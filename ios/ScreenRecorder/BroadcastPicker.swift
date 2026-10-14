import ReplayKit
import SwiftUI

/// Holds the system broadcast picker so a custom SwiftUI button can open the iOS start/stop sheet.
final class BroadcastPickerController {
    weak var picker: RPSystemBroadcastPickerView?

    func present() {
        guard let button = picker?.subviews.compactMap({ $0 as? UIButton }).first else { return }
        button.sendActions(for: .allTouchEvents)
    }

    /// Looks up the embedded extension at runtime so re-signing tools that rename bundle IDs keep working.
    static var embeddedExtensionBundleID: String? {
        guard
            let pluginsURL = Bundle.main.builtInPlugInsURL,
            let items = try? FileManager.default.contentsOfDirectory(at: pluginsURL, includingPropertiesForKeys: nil)
        else { return nil }

        return items
            .filter { $0.pathExtension == "appex" }
            .compactMap { Bundle(url: $0)?.bundleIdentifier }
            .first
    }
}

struct BroadcastPicker: UIViewRepresentable {
    let controller: BroadcastPickerController

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = BroadcastPickerController.embeddedExtensionBundleID
        picker.showsMicrophoneButton = true
        controller.picker = picker
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        controller.picker = uiView
    }
}
