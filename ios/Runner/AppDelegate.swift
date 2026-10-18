import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Background task held while a backup runs — keeps the process alive
  /// for the system-granted grace period (~30 s) after backgrounding.
  private var keepaliveTaskId: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Keepalive channel — see lib/services/background/backup_keepalive.dart.
    let channel = FlutterMethodChannel(
      name: "enpix/keepalive",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "start":
        self?.beginKeepaliveTask()
        result(nil)
      case "stop":
        self?.endKeepaliveTask()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Begins the background task. Inert while the app is foregrounded;
  /// after backgrounding the system grants ~30 s before suspending.
  private func beginKeepaliveTask() {
    endKeepaliveTask() // never hold two tasks at once
    keepaliveTaskId = UIApplication.shared.beginBackgroundTask(withName: "backup-keepalive") {
      [weak self] in
      // Budget exhausted — the Dart grace timer normally stops the backup
      // just before this fires; ending here is the safety net.
      self?.endKeepaliveTask()
    }
  }

  private func endKeepaliveTask() {
    guard keepaliveTaskId != .invalid else { return }
    UIApplication.shared.endBackgroundTask(keepaliveTaskId)
    keepaliveTaskId = .invalid
  }
}
