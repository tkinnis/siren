import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var methodChannel: FlutterMethodChannel?
  var pendingFiles: [String] = []
  var isFlutterReady: Bool = false

  private func flushPendingFiles() {
    guard isFlutterReady, let channel = methodChannel, !pendingFiles.isEmpty else { return }
    let filesToOpen = pendingFiles
    pendingFiles.removeAll()
    for file in filesToOpen {
      channel.invokeMethod("openFile", arguments: file)
    }
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller: FlutterViewController = mainFlutterWindow?.contentViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.tonykinnis.Siren/files", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] (call, result) in
      if call.method == "flutterReady" {
        self?.isFlutterReady = true
        self?.flushPendingFiles()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    methodChannel = channel

    super.applicationDidFinishLaunching(notification)

    // Fallback in case flutterReady was already sent
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.isFlutterReady = true
      self?.flushPendingFiles()
    }
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    if isFlutterReady, let channel = methodChannel {
      channel.invokeMethod("openFile", arguments: filename)
    } else if !pendingFiles.contains(filename) {
      pendingFiles.append(filename)
    }
    return true
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      if url.isFileURL {
        let path = url.path
        if isFlutterReady, let channel = methodChannel {
          channel.invokeMethod("openFile", arguments: path)
        } else if !pendingFiles.contains(path) {
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