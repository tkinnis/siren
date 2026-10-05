import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var methodChannel: FlutterMethodChannel?
  var pendingFiles: [String] = []

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller: FlutterViewController = mainFlutterWindow?.contentViewController as! FlutterViewController
    methodChannel = FlutterMethodChannel(name: "com.tonykinnis.Siren/files", binaryMessenger: controller.engine.binaryMessenger)

    super.applicationDidFinishLaunching(notification)

    if !pendingFiles.isEmpty {
       // Slight delay to ensure Flutter is ready to receive
       DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
           for file in self.pendingFiles {
               self.methodChannel?.invokeMethod("openFile", arguments: file)
           }
           self.pendingFiles.removeAll()
       }
    }
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    if let channel = methodChannel {
        channel.invokeMethod("openFile", arguments: filename)
    } else {
        pendingFiles.append(filename)
    }
    return true
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
        if url.isFileURL {
            let path = url.path
            if let channel = methodChannel {
                channel.invokeMethod("openFile", arguments: path)
            } else {
                pendingFiles.append(path)
            }
        }
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}