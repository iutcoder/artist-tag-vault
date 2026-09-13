import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private static let minimumContentSize = NSSize(width: 1280, height: 800)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = frame
    contentViewController = flutterViewController
    setFrame(windowFrame, display: true)
    RegisterGeneratedPlugins(registry: flutterViewController)

    contentMinSize = Self.minimumContentSize
    let currentSize = contentRect(forFrameRect: frame).size
    if currentSize.width < Self.minimumContentSize.width ||
        currentSize.height < Self.minimumContentSize.height {
      setContentSize(
        NSSize(
          width: max(currentSize.width, Self.minimumContentSize.width),
          height: max(currentSize.height, Self.minimumContentSize.height)
        )
      )
      center()
    }

    super.awakeFromNib()
  }
}
