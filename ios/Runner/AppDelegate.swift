import Flutter
import AVFoundation
import AudioToolbox
import Photos
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let restNotifications = RestTimerNotifications(center: UNUserNotificationCenter.current())
  private lazy var watchBridge = PhoneWatchBridge(display: .shared, notifications: restNotifications)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    watchBridge.start()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if notification.request.identifier.hasPrefix("setkeep_rest_timer") {
      // Scheduled deadline is suppressed in foreground; Dart cancels it and
      // submits exactly one immediate OS cue. OS owns sound/focus/silent rules.
      completionHandler(notification.request.identifier.hasSuffix("_foreground") ? [.banner, .sound] : [])
      return
    }
    super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.notification.request.identifier.hasPrefix("setkeep_rest_timer") {
      completionHandler()
      return
    }
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.setkeep.app/rest_timer",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    RestCompletionFeedback.prepareSound()
    let feedback = RestCompletionFeedback()
    let notifications = restNotifications
    watchBridge.attach(channel)
    channel.setMethodCallHandler { call, result in
      #if targetEnvironment(simulator)
      if call.method == "debugStatus" {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
          center.getPendingNotificationRequests { pending in
            center.getDeliveredNotifications { delivered in
              DispatchQueue.main.async {
                result([
                  "playing": feedback.isPlaying,
                  "liveActivities": RestTimerDisplay.shared.activityCount(),
                  "authorization": settings.authorizationStatus.rawValue,
                  "applicationState": UIApplication.shared.applicationState.rawValue,
                  "pending": pending.filter { $0.identifier.hasPrefix("setkeep_rest_timer") }.map {
                    ["id": $0.identifier, "trigger": ($0.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()?.timeIntervalSince1970 ?? 0] as [String: Any]
                  },
                  "delivered": delivered.filter { $0.request.identifier.hasPrefix("setkeep_rest_timer") }.map { $0.request.identifier }
                ])
              }
            }
          }
        }
        return
      }
      #endif
      if call.method == "state" { result(RestTimerDisplay.shared.snapshot()); return }
      if call.method == "cancel" {
        let args = call.arguments as? [String: Any]
        RestTimerDisplay.shared.cancel(remaining: (args?["remainingSeconds"] as? Int) ?? 0)
      }
      if call.method == "schedule", let args = call.arguments as? [String: Any] {
        let deadline = (args["endsAtMilliseconds"] as? NSNumber).map {
          Date(timeIntervalSince1970: $0.doubleValue / 1000)
        } ?? Date().addingTimeInterval(TimeInterval(args["seconds"] as? Int ?? 1))
        RestTimerDisplay.shared.schedule(deadline: deadline, name: args["exerciseName"] as? String ?? "")
      }
      if call.method == "playCompletionFeedback" {
        notifications.presentCompletion(result: result)
        return
      }
      if call.method == "cancel" || call.method == "schedule" { feedback.stop() }
      notifications.handle(call, result: result)
    }

    let imageChannel = FlutterMethodChannel(
      name: "com.setkeep.app/workout_image",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    imageChannel.setMethodCallHandler { call, result in
      if call.method == "deviceInfo" {
        let device = UIDevice.current
        result([
          "os": "iOS \(device.systemVersion)",
          "device": device.model,
        ])
        return
      }
      guard call.method == "save" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let bytes = arguments["bytes"] as? FlutterStandardTypedData,
        let image = UIImage(data: bytes.data)
      else {
        result(FlutterError(code: "invalid_arguments", message: "Image data is required", details: nil))
        return
      }
      let saveImage = {
        PHPhotoLibrary.shared().performChanges({
          PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, error in
          DispatchQueue.main.async {
            if success {
              result(nil)
            } else {
              result(FlutterError(
                code: "image_save_failed",
                message: error?.localizedDescription ?? "Could not save image",
                details: nil
              ))
            }
          }
        }
      }
      if #available(iOS 14, *) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
          guard status == .authorized || status == .limited else {
            DispatchQueue.main.async {
              result(FlutterError(code: "photo_permission", message: "Photo access was denied", details: nil))
            }
            return
          }
          saveImage()
        }
      } else {
        PHPhotoLibrary.requestAuthorization { status in
          guard status == .authorized else {
            DispatchQueue.main.async {
              result(FlutterError(code: "photo_permission", message: "Photo access was denied", details: nil))
            }
            return
          }
          saveImage()
        }
      }
    }
  }
}

protocol RestNotificationCenter {
  func requestAuthorization(options: UNAuthorizationOptions, completionHandler: @escaping (Bool, Error?) -> Void)
  func add(_ request: UNNotificationRequest, withCompletionHandler: ((Error?) -> Void)?)
  func getPendingNotificationRequests(completionHandler: @escaping ([UNNotificationRequest]) -> Void)
  func getDeliveredNotifications(completionHandler: @escaping ([UNNotification]) -> Void)
  func removePendingNotificationRequests(withIdentifiers: [String])
  func removeDeliveredNotifications(withIdentifiers: [String])
}

extension UNUserNotificationCenter: RestNotificationCenter {}

// Kept separate from Flutter startup so delayed permission/add callbacks can be
// tested deterministically without requiring the system permission dialog.
final class RestTimerNotifications {
  private let center: RestNotificationCenter
  private var revision = 0
  private var activeIdentifier: String?
  private let prefix = "setkeep_rest_timer"

  init(center: RestNotificationCenter) { self.center = center }

  private func removeObsoleteNotifications() {
    center.getPendingNotificationRequests { requests in
      DispatchQueue.main.async {
        let obsolete = requests.map(\.identifier).filter {
          $0.hasPrefix(self.prefix) && $0 != self.activeIdentifier
        }
        self.center.removePendingNotificationRequests(withIdentifiers: obsolete)
      }
    }
    center.getDeliveredNotifications { notifications in
      DispatchQueue.main.async {
        let obsolete = notifications.map { $0.request.identifier }.filter {
          $0.hasPrefix(self.prefix) && $0 != self.activeIdentifier
        }
        self.center.removeDeliveredNotifications(withIdentifiers: obsolete)
      }
    }
  }

  func presentCompletion(result: @escaping FlutterResult) {
    revision += 1
    let requested = revision
    let content = UNMutableNotificationContent()
    content.title = "SETKEEP"
    content.body = "休憩終了。次のセットへ！"
    content.sound = UNNotificationSound(named: UNNotificationSoundName("rest_complete.wav"))
    let identifier = "\(prefix)_\(UUID().uuidString)_foreground"
    activeIdentifier = identifier
    center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
      DispatchQueue.main.async {
        if requested != self.revision {
          self.center.removePendingNotificationRequests(withIdentifiers: [identifier])
          self.center.removeDeliveredNotifications(withIdentifiers: [identifier])
          result(nil)
        } else if let error {
          result(FlutterError(code: "notification_feedback", message: error.localizedDescription, details: nil))
        } else { result(nil) }
      }
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      switch call.method {
      case "schedule":
        guard
          let arguments = call.arguments as? [String: Any],
          let seconds = arguments["seconds"] as? Int
        else {
          result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
          return
        }
        self.revision += 1
        let scheduledRevision = self.revision
        if let previous = self.activeIdentifier {
          self.center.removePendingNotificationRequests(withIdentifiers: [previous])
          self.center.removeDeliveredNotifications(withIdentifiers: [previous])
        }
        let identifier = "\(self.prefix)_\(UUID().uuidString)"
        self.activeIdentifier = identifier
        self.removeObsoleteNotifications()
        let deadline = (arguments["endsAtMilliseconds"] as? NSNumber).map {
          Date(timeIntervalSince1970: $0.doubleValue / 1000)
        } ?? Date().addingTimeInterval(TimeInterval(seconds))
        self.center.requestAuthorization(options: [.alert, .sound]) { granted, error in
          DispatchQueue.main.async {
            guard self.revision == scheduledRevision else {
              result(nil)
              return
            }
            if let error = error {
              result(FlutterError(code: "notification_permission", message: error.localizedDescription, details: nil))
              return
            }
            let remaining = deadline.timeIntervalSinceNow
            guard granted, remaining > 0 else {
              result(nil)
              return
            }
            let content = UNMutableNotificationContent()
            content.title = "SETKEEP"
            content.body = "休憩終了。次のセットへ！"
            content.sound = UNNotificationSound(named: UNNotificationSoundName("rest_complete.wav"))
            let request = UNNotificationRequest(
              identifier: identifier,
              content: content,
              trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(0.1, remaining), repeats: false)
            )
            self.center.add(request) { error in
              DispatchQueue.main.async {
                // Cancellation can also arrive while the notification is being added.
                if self.revision != scheduledRevision {
                  self.center.removePendingNotificationRequests(withIdentifiers: [identifier])
                  self.center.removeDeliveredNotifications(withIdentifiers: [identifier])
                  result(nil)
                } else if let error = error {
                  result(FlutterError(code: "notification_schedule", message: error.localizedDescription, details: nil))
                } else {
                  result(nil)
                }
              }
            }
          }
        }
      case "cancel":
        self.revision += 1
        if let identifier = self.activeIdentifier {
          self.center.removePendingNotificationRequests(withIdentifiers: [identifier])
          self.center.removeDeliveredNotifications(withIdentifiers: [identifier])
        }
        self.activeIdentifier = nil
        self.removeObsoleteNotifications()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
  }
}

/// Owned by the engine handler, not the countdown widget. Ambient respects silent mode.
final class RestCompletionFeedback {
  private var player: AVAudioPlayer?
  var isPlaying: Bool { player?.isPlaying == true }
  private var revision = 0
  private var vibrationTasks: [DispatchWorkItem] = []

  static var soundURL: URL {
    FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Sounds/rest_complete.wav")
  }

  static func prepareSound() {
    let key = FlutterDartProject.lookupKey(forAsset: "assets/sounds/rest_complete.wav")
    guard let source = Bundle.main.url(forResource: key, withExtension: nil) else { return }
    do {
      try FileManager.default.createDirectory(at: soundURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let data = try Data(contentsOf: source)
      try data.write(to: soundURL, options: .atomic)
    } catch { NSLog("Rest sound preparation failed: %@", error.localizedDescription) }
  }

  func play() {
    stop()
    let requested = revision
    UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
      DispatchQueue.main.async {
        guard let self, self.revision == requested,
              settings.soundSetting == .enabled,
              UIApplication.shared.applicationState == .active else { return }
        do {
          try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
          self.player = try AVAudioPlayer(contentsOf: Self.soundURL)
          self.player?.prepareToPlay()
          self.player?.play()
          for delay in [0.0, 1.25] {
            let task = DispatchWorkItem { [weak self] in
              guard let self, self.revision == requested else { return }
              AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
            self.vibrationTasks.append(task)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
          }
        } catch { NSLog("Rest feedback failed: %@", error.localizedDescription) }
      }
    }
  }

  func stop() {
    revision += 1
    player?.stop()
    player = nil
    vibrationTasks.forEach { $0.cancel() }
    vibrationTasks.removeAll()
  }
}
