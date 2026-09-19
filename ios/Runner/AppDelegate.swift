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
      if call.method == "setBadge" {
        guard let count = call.arguments as? Int, count >= 0 else {
          result(FlutterError(code: "invalid_badge", message: "Invalid badge count", details: nil))
          return
        }
        DispatchQueue.main.async {
          if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count) { error in
              DispatchQueue.main.async {
                if let error = error {
                  result(FlutterError(code: "badge_failed", message: error.localizedDescription, details: nil))
                } else { result(true) }
              }
            }
          } else {
            UIApplication.shared.applicationIconBadgeNumber = count
            result(true)
          }
        }
        return
      }
      guard call.method == "open" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let address: String
      if #available(iOS 16.0, *) {
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

}
