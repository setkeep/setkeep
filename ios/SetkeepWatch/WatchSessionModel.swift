import Combine
import Foundation
import WatchConnectivity

@MainActor
final class WatchSessionModel: NSObject, ObservableObject, WCSessionDelegate {
  @Published private(set) var state: RestWatchState?
  @Published private(set) var reachable = false
  @Published private(set) var sending = false
  @Published private(set) var message = watchText("iPhoneのSETKEEPを開いてください", "Open SETKEEP on your iPhone")
  private var pendingID: UUID?

  override init() {
    super.init()
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  private func receive(_ payload: [String: Any]) {
    guard let received = RestWatchState(payload: payload) else { return }
    guard state == nil || received.revision >= state!.revision else { return }
    state = received
    message = ""
  }

  func refresh() {
    let session = WCSession.default
    reachable = session.activationState == .activated && session.isReachable
    if let cached = RestWatchState(payload: session.receivedApplicationContext) {
      receive(cached.payload)
    }
    guard reachable else { return }
    session.sendMessage(["kind": "state"], replyHandler: { [weak self] reply in
      Task { @MainActor in self?.receive(reply) }
    }, errorHandler: { [weak self] _ in
      Task { @MainActor in self?.reachable = false }
    })
  }

  func send(_ action: RestWatchAction) {
    guard !sending, reachable, let state, state.phase() != "idle" else { return }
    let id = UUID()
    pendingID = id
    sending = true
    message = ""
    WCSession.default.sendMessage(RestWatchCommand.message(action: action, state: state), replyHandler: { [weak self] reply in
      Task { @MainActor in
        guard let self, self.pendingID == id else { return }
        self.pendingID = nil
        self.sending = false
        if let payload = reply["state"] as? [String: Any] { self.receive(payload) }
        if reply["accepted"] as? Bool != true {
          self.message = watchText("状態が更新されました。もう一度お試しください", "The timer changed. Please try again.")
        }
      }
    }, errorHandler: { [weak self] _ in
      Task { @MainActor in
        guard let self, self.pendingID == id else { return }
        self.pendingID = nil
        self.sending = false
        self.message = watchText("接続できません。iPhoneを確認してください", "Cannot connect. Check your iPhone.")
      }
    })
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      guard let self, self.pendingID == id else { return }
      self.pendingID = nil
      self.sending = false
      self.message = watchText("応答を確認できません。iPhoneを確認してください", "No response yet. Check your iPhone.")
      self.refresh()
    }
  }

  nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    Task { @MainActor [weak self] in self?.refresh() }
  }
  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    Task { @MainActor [weak self] in self?.refresh() }
  }
  nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    Task { @MainActor [weak self] in self?.receive(applicationContext) }
  }
}
