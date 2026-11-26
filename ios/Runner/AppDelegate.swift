import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var exportReply: FlutterResult?
  private var exportFile: URL?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Remove interrupted export scratch files from a previous process.
    let temp = FileManager.default.temporaryDirectory
    if let files = try? FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
      for file in files where file.lastPathComponent.hasPrefix("anonymoke-export-") && file.pathExtension == "json" {
        if let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]), values.isRegularFile == true, values.isSymbolicLink != true {
          try? FileManager.default.removeItem(at: file)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(name: "anonymoke/files", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { [weak self] call, reply in
      guard call.method == "saveJson" else { reply(FlutterMethodNotImplemented); return }
      guard let self = self else { reply(false); return }
      guard self.exportReply == nil else { reply(FlutterError(code: "save_busy", message: "A save is already open.", details: nil)); return }
      guard let args = call.arguments as? [String: Any], let contents = args["contents"] as? String else {
        reply(FlutterError(code: "save_invalid", message: "No export content.", details: nil)); return
      }
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      guard var presenter = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
        reply(FlutterError(code: "save_unavailable", message: "Could not open Save File.", details: nil)); return
      }
      while let visible = presenter.presentedViewController { presenter = visible }
      let file = FileManager.default.temporaryDirectory.appendingPathComponent("anonymoke-export-\(UUID().uuidString).json")
      do {
        try contents.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
        self.exportFile = file
        self.exportReply = reply
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) { picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true) }
        else { picker = UIDocumentPickerViewController(url: file, in: .exportToService) }
        picker.delegate = self
        presenter.present(picker, animated: true)
      } catch {
        try? FileManager.default.removeItem(at: file)
        reply(FlutterError(code: "save_failed", message: "Could not prepare the export file.", details: nil))
      }
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finishExport(!urls.isEmpty) }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finishExport(false) }
  private func finishExport(_ saved: Bool) {
    if let file = exportFile { try? FileManager.default.removeItem(at: file) }
    let reply = exportReply
    exportFile = nil
    exportReply = nil
    reply?(saved)
  }
}
