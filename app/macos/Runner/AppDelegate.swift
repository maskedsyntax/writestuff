import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  // Cmd+Q and Quit from the Dock go through the window's close request, so the
  // app can ask about unsaved documents and flush recovery before exiting.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if let window = mainFlutterWindow, window.isVisible {
      window.performClose(nil)
      return .terminateCancel
    }
    return .terminateNow
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
