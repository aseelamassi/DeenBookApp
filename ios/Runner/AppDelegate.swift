import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var reminderVersion: Int64 = 0
  private let reminderIds = (0...7).map { "deenbook.sync.\($0)" }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeenBookSyncReminders") else { return }
    let channel = FlutterMethodChannel(name: "deenbook/sync_reminders", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let center = UNUserNotificationCenter.current()
      switch call.method {
      case "cancel":
        self.reminderVersion = 0
        center.removePendingNotificationRequests(withIdentifiers: self.reminderIds)
        center.removeDeliveredNotifications(withIdentifiers: self.reminderIds)
        result(nil)
      case "schedule":
        guard let args = call.arguments as? [String: Any],
              let stamp = args["verified"] as? NSNumber,
              let expires = args["expires"] as? NSNumber else {
          result(FlutterError(code: "bad_date", message: "Invalid verification time", details: nil)); return
        }
        let version = stamp.int64Value
        self.reminderVersion = version
        center.removePendingNotificationRequests(withIdentifiers: self.reminderIds)
        center.removeDeliveredNotifications(withIdentifiers: self.reminderIds)
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
          DispatchQueue.main.async {
            guard granted, self.reminderVersion == version else { return }
            for day in 0...2 {
              let due = Date(timeIntervalSince1970: expires.doubleValue / 1000 - Double((2-day) * 86400))
              if due.timeIntervalSince1970 <= Double(version) / 1000 { continue }
              let seconds = due.timeIntervalSinceNow
              if seconds <= 0 { continue }
              let content = UNMutableNotificationContent()
              content.title = "دفتر دين — تذكير المزامنة"
              content.body = day == 2 ? "انتهت مدة العمل دون إنترنت. اتصل بالخادم للمزامنة. عملياتك محفوظة." : "اقترب انتهاء مدة العمل دون إنترنت. زامن بياناتك الآن."
              content.sound = .default
              center.add(UNNotificationRequest(identifier: "deenbook.sync.\(day)", content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)))
            }
          }
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}
