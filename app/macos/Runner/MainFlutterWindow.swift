import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 1050, height: 740))
    self.center()

    // Let the sidebar run under the traffic lights.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = false

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
