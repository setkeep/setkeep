import ActivityKit
import Foundation
import UIKit

/// Persists the same deadline used by the local completion notification.
/// No second-by-second updates, background audio or background polling.
@MainActor
final class RestTimerDisplay {
  static let shared = RestTimerDisplay()
  private let store: UserDefaults
  var onStateChanged: (() -> Void)?
  private let watchRevisionKey = "rest_display_watch_revision"
  private let timerIDKey = "rest_display_timer_id"

  init(store: UserDefaults = .standard) { self.store = store }

  private func didChange() {
    let value = store.integer(forKey: watchRevisionKey)
    store.set(value < Int.max ? value + 1 : 1, forKey: watchRevisionKey)
    onStateChanged?()
  }
  private var revision = 0
  private var pending: Task<Void, Never>?
  private var expiry: Timer?
  private let deadlineKey = "rest_display_deadline"
  private let remainingKey = "rest_display_remaining"
  private let nameKey = "rest_display_exercise"

  func schedule(deadline: Date, name: String, continuing: Bool = false) {
    revision += 1
    let requested = revision
    expiry?.invalidate()
    store.set(deadline.timeIntervalSince1970 * 1000, forKey: deadlineKey)
    store.set(0, forKey: remainingKey)
    store.set(name, forKey: nameKey)
    if !continuing || store.string(forKey: timerIDKey) == nil {
      store.set(UUID().uuidString, forKey: timerIDKey)
    }
    didChange()
    expiry = Timer.scheduledTimer(withTimeInterval: max(0.1, deadline.timeIntervalSinceNow), repeats: false) { _ in
      Task { @MainActor in
        guard self.revision == requested else { return }
        self.cancel()
      }
    }
    let previous = pending
    pending = Task { @MainActor in
      await previous?.value
      guard self.revision == requested else { return }
      if #available(iOS 16.2, *) {
        for activity in Activity<RestTimerAttributes>.activities {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard self.revision == requested, deadline > Date(),
              ActivityAuthorizationInfo().areActivitiesEnabled,
              UIApplication.shared.applicationState == .active else { return }
        do {
          let state = RestTimerAttributes.ContentState(startedAt: Date(), endsAt: deadline, exerciseName: name)
          _ = try Activity.request(attributes: RestTimerAttributes(timerID: UUID().uuidString),
              content: ActivityContent(state: state, staleDate: deadline), pushType: nil)
        } catch {
          // Completion notifications and Flutter remain usable if activities are unavailable.
          NSLog("Rest Live Activity could not start: %@", error.localizedDescription)
        }
      }
    }
  }

  func cancel(remaining: Int = 0) {
    revision += 1
    expiry?.invalidate()
    expiry = nil
    store.removeObject(forKey: deadlineKey)
    store.set(max(0, remaining), forKey: remainingKey)
    if remaining <= 0 {
      store.removeObject(forKey: timerIDKey)
      store.removeObject(forKey: nameKey)
    }
    didChange()
    let previous = pending
    pending = Task { @MainActor in
      await previous?.value
      if #available(iOS 16.2, *) {
        for activity in Activity<RestTimerAttributes>.activities {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
      }
    }
  }

  /// Notification permission prompts can temporarily make the app inactive while
  /// the first timer is starting. Create its display when the app becomes active.
  func resume() {
    let state = snapshot()
    let milliseconds = state["endsAtMilliseconds"] as? Double ?? 0
    if #available(iOS 16.2, *), milliseconds > Date().timeIntervalSince1970 * 1000,
       Activity<RestTimerAttributes>.activities.isEmpty {
      schedule(deadline: Date(timeIntervalSince1970: milliseconds / 1000),
               name: store.string(forKey: nameKey) ?? "", continuing: true)
    }
  }

  func activityCount() -> Int {
    if #available(iOS 16.2, *) { return Activity<RestTimerAttributes>.activities.count }
    return 0
  }

  func snapshot() -> [String: Any] {
    let deadline = store.double(forKey: deadlineKey)
    if deadline > 0 && deadline <= Date().timeIntervalSince1970 * 1000 { cancel() }
    return ["endsAtMilliseconds": store.double(forKey: deadlineKey),
            "remainingSeconds": store.integer(forKey: remainingKey),
            "exerciseName": store.string(forKey: nameKey) ?? "",
            "timerID": store.string(forKey: timerIDKey) ?? "",
            "watchRevision": store.integer(forKey: watchRevisionKey)]
  }
}
