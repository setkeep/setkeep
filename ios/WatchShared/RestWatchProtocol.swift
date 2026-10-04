import Foundation

/// Shared wire format only. The iPhone remains the owner of timer/notification state.
struct RestWatchState {
  static let protocolVersion = 1
  let timerID: String
  let revision: Int
  let deadlineMilliseconds: Double
  let pausedSeconds: Int
  let exerciseName: String

  init(timerID: String, revision: Int, deadlineMilliseconds: Double,
       pausedSeconds: Int, exerciseName: String) {
    self.timerID = timerID
    self.revision = revision
    self.deadlineMilliseconds = deadlineMilliseconds
    self.pausedSeconds = pausedSeconds
    self.exerciseName = exerciseName
  }

  init?(payload: [String: Any]) {
    guard payload["protocolVersion"] as? Int == Self.protocolVersion,
          let timerID = payload["timerID"] as? String,
          let revision = payload["revision"] as? Int, revision >= 0,
          let deadline = payload["endsAtMilliseconds"] as? Double,
          deadline.isFinite, deadline >= 0,
          let remaining = payload["remainingSeconds"] as? Int,
          remaining >= 0, remaining <= 86400,
          let name = payload["exerciseName"] as? String else { return nil }
    self.init(timerID: timerID, revision: revision, deadlineMilliseconds: deadline,
              pausedSeconds: remaining, exerciseName: name)
  }

  var payload: [String: Any] {
    ["protocolVersion": Self.protocolVersion, "timerID": timerID,
     "revision": revision, "endsAtMilliseconds": deadlineMilliseconds,
     "remainingSeconds": pausedSeconds, "exerciseName": exerciseName]
  }

  func remaining(at date: Date = Date()) -> Int {
    if deadlineMilliseconds > 0 {
      return Int(min(86400, max(0, ceil(deadlineMilliseconds / 1000 - date.timeIntervalSince1970))))
    }
    return pausedSeconds
  }

  func phase(at date: Date = Date()) -> String {
    guard !timerID.isEmpty, remaining(at: date) > 0 else { return "idle" }
    return deadlineMilliseconds > 0 ? "running" : "paused"
  }
}

enum RestWatchAction: String {
  case pause, resume, extend
}

/// Commands are never queued for later. A delayed command cannot change a newer timer.
struct RestWatchCommand {
  let id: String
  let timerID: String
  let revision: Int
  let action: RestWatchAction

  init?(message: [String: Any]) {
    guard message["protocolVersion"] as? Int == RestWatchState.protocolVersion,
          let id = message["commandID"] as? String, UUID(uuidString: id) != nil,
          let timerID = message["timerID"] as? String, !timerID.isEmpty,
          let revision = message["revision"] as? Int,
          let raw = message["action"] as? String,
          let action = RestWatchAction(rawValue: raw) else { return nil }
    self.id = id
    self.timerID = timerID
    self.revision = revision
    self.action = action
  }

  static func message(action: RestWatchAction, state: RestWatchState,
                      id: String = UUID().uuidString) -> [String: Any] {
    ["protocolVersion": RestWatchState.protocolVersion, "commandID": id,
     "timerID": state.timerID, "revision": state.revision, "action": action.rawValue]
  }
}

struct RestWatchCommandGate {
  private var recentIDs: [String] = []

  mutating func accept(_ message: [String: Any], state: RestWatchState,
                       now: Date = Date()) -> RestWatchAction? {
    guard let command = RestWatchCommand(message: message),
          command.timerID == state.timerID, command.revision == state.revision,
          !recentIDs.contains(command.id) else { return nil }
    let phase = state.phase(at: now)
    guard phase != "idle",
          command.action != .pause || phase == "running",
          command.action != .resume || phase == "paused" else { return nil }
    recentIDs.append(command.id)
    if recentIDs.count > 32 { recentIDs.removeFirst() }
    return command.action
  }
}
