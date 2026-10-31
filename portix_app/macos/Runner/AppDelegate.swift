import Cocoa
import FlutterMacOS
import Sparkle

@main
class AppDelegate: FlutterAppDelegate {
  /// Sparkle 2: checks SUFeedURL (Info.plist) on its schedule and shows its
  /// own update window. Started in applicationDidFinishLaunching, and only
  /// for release builds that carry an EdDSA public key.
  let updaterController = SPUStandardUpdaterController(
    startingUpdater: false,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

  /// Whether Sparkle is running; "Check for Updates…" explains when not.
  private(set) var updaterStarted = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    #if !DEBUG
      let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
      if !key.isEmpty {
        do {
          try updaterController.updater.start()
          updaterStarted = true
        } catch {
          NSLog("Portix: Sparkle did not start: \(error)")
        }
      }
    #endif
  }

  /// The menu's "Check for Updates…": Sparkle's own check-and-update window.
  func checkForUpdates() {
    guard updaterStarted else {
      let alert = NSAlert()
      alert.messageText = "Updates are not available in this build"
      alert.informativeText =
        "Only release builds of Portix with a signing key check for updates. "
        + "Download new versions from the Portix releases page."
      alert.runModal()
      return
    }
    updaterController.checkForUpdates(nil)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
