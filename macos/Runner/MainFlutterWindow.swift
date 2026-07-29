import Cocoa
import FlutterMacOS
import UserNotifications

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Desktop alarm banners (spec §9): a tiny channel to the native
    // notification center — no plugin, no APNs, local only.
    let notifier = FlutterMethodChannel(
      name: "io.koini.keyview/desktop_notifier",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    notifier.setMethodCallHandler { call, result in
      let center = UNUserNotificationCenter.current()
      switch call.method {
      case "init":
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
          DispatchQueue.main.async { result(granted) }
        }
      case "show":
        let args = call.arguments as? [String: Any]
        let content = UNMutableNotificationContent()
        content.title = (args?["title"] as? String) ?? "KŌINIkeyview"
        content.body = (args?["body"] as? String) ?? ""
        content.sound = .default
        let request = UNNotificationRequest(
          identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { _ in }
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
