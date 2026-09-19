import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var notificationSettingsChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NotificationSettings") else { return }
    notificationSettingsChannel = FlutterMethodChannel(
      name: "next_episode/notification_settings", binaryMessenger: registrar.messenger())
    notificationSettingsChannel?.setMethodCallHandler { call, result in
      guard call.method == "open" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let address: String
      if #available(iOS 15.4, *) {
        address = UIApplication.openNotificationSettingsURLString
      } else {
        address = UIApplication.openSettingsURLString
      }
      guard let url = URL(string: address) else { result(false); return }
      DispatchQueue.main.async {
        UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
      }
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    // The badge indicates a new reminder, not the size of the unwatched library.
    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
    } else {
      application.applicationIconBadgeNumber = 0
    }
  }
}
