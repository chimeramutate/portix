import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The Flutter menu bar's "Check for Updates…" reaches Sparkle here.
    FlutterMethodChannel(
      name: "portix/updater",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setMethodCallHandler { call, result in
      guard call.method == "checkForUpdates",
        let app = NSApp.delegate as? AppDelegate
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      app.checkForUpdates()
      result(nil)
    }

    super.awakeFromNib()
  }
}
