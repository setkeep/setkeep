import Flutter
import Foundation
import WatchConnectivity

/// General app only: no Flutter engine, Supabase credentials or record copies on Watch.
@MainActor
final class PhoneWatchBridge: NSObject, WCSessionDelegate {
  private let display: RestTimerDisplay
  private let notifications: RestTimerNotifications
  private var gate = RestWatchCommandGate()
  private var channel: FlutterMethodChannel?

  init(display: RestTimerDisplay, notifications: RestTimerNotifications) {
    self.display = display
    self.notifications = notifications
    super.init()
  }

  func start() {
    guard WCSession.isSupported() else { return }
    display.onStateChanged = { [weak self] in self?.publish() }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  func attach(_ channel: FlutterMethodChannel) {
    self.channel = channel
    publish()
  }

  private func currentState() -> RestWatchState {
    let snapshot = display.snapshot()
    return RestWatchState(timerID: snapshot["timerID"] as? String ?? "",
      revision: snapshot["watchRevision"] as? Int ?? 0,
      deadlineMilliseconds: snapshot["endsAtMilliseconds"] as? Double ?? 0,
      pausedSeconds: snapshot["remainingSeconds"] as? Int ?? 0,
      exerciseName: snapshot["exerciseName"] as? String ?? "")
  }

  private func publish() {
    let session = WCSession.default
    guard session.activationState == .activated, session.isPaired,
          session.isWatchAppInstalled else { return }
    do {
      // Latest state is delivered even when the counterpart is not reachable.
      try session.updateApplicationContext(currentState().payload)
    } catch {
      // Connectivity must never prevent recording, local notifications or startup.
    }
  }

  private func handle(_ message: [String: Any]) -> [String: Any] {
    let state = currentState()
    if message["kind"] as? String == "state" { return state.payload }
    guard let action = gate.accept(message, state: state) else {
      return ["accepted": false, "state": state.payload]
    }
    let remaining = state.remaining()
    var method = "cancel"
    var args: [String: Any] = [:]
    switch action {
    case .pause:
      display.cancel(remaining: remaining)
      args["remainingSeconds"] = remaining
    case .resume, .extend:
      let seconds = remaining + (action == .extend ? 30 : 0)
      if action == .extend && state.phase() == "paused" {
        display.cancel(remaining: seconds)
        args["remainingSeconds"] = seconds
      } else {
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        display.schedule(deadline: deadline, name: state.exerciseName, continuing: true)
        method = "schedule"
        args = ["seconds": seconds, "exerciseName": state.exerciseName,
                "endsAtMilliseconds": deadline.timeIntervalSince1970 * 1000]
      }
    }
    // Same scheduling/cancellation service as the existing iPhone timer.
    notifications.handle(FlutterMethodCall(methodName: method, arguments: args)) { _ in }
    channel?.invokeMethod("stateChanged", arguments: nil)
    return ["accepted": true, "state": currentState().payload]
  }

  nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    Task { @MainActor [weak self] in self?.publish() }
  }

  nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
  nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
  nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
    Task { @MainActor [weak self] in self?.publish() }
  }

  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                          replyHandler: @escaping ([String: Any]) -> Void) {
    Task { @MainActor [weak self] in
      guard let self else { replyHandler(["accepted": false]); return }
      replyHandler(self.handle(message))
    }
  }
}
