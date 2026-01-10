import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var methodChannel: FlutterMethodChannel?
  var pendingFile: String?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller: FlutterViewController = mainFlutterWindow?.contentViewController as! FlutterViewController
    methodChannel = FlutterMethodChannel(name: "com.example.siren/files", binaryMessenger: controller.engine.binaryMessenger)
    
    super.applicationDidFinishLaunching(notification)
    
    if let file = pendingFile {
       // Slight delay to ensure Flutter is ready to receive
       DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
           self.methodChannel?.invokeMethod("openFile", arguments: file)
       }
       pendingFile = nil
    }
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    if let channel = methodChannel {
        channel.invokeMethod("openFile", arguments: filename)
    } else {
        pendingFile = filename
    }
    return true
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}