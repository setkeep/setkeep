import Foundation

@main
struct RestWatchProtocolTests {
  static func main() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let timer = UUID().uuidString
    let running = RestWatchState(timerID: timer, revision: 4,
      deadlineMilliseconds: (now.timeIntervalSince1970 + 60) * 1000,
      pausedSeconds: 0, exerciseName: "Test exercise")
    var checks = 0
    func check(_ value: Bool, _ name: String) {
      precondition(value, name)
      checks += 1
      print("PASS: \(name)")
    }
    check(RestWatchState(payload: running.payload)?.timerID == timer, "state round trip")
    check(running.remaining(at: now) == 60, "phone deadline determines countdown")
    check(running.remaining(at: now.addingTimeInterval(0.2)) == 60, "remaining seconds round up")
    check(running.phase(at: now.addingTimeInterval(61)) == "idle", "expired timer disables actions")
    var payload = running.payload
    payload["protocolVersion"] = 2
    check(RestWatchState(payload: payload) == nil, "unknown schema rejected")
    payload = running.payload; payload["endsAtMilliseconds"] = Double.infinity
    check(RestWatchState(payload: payload) == nil, "nonfinite deadline rejected")
    payload = running.payload; payload["remainingSeconds"] = -1
    check(RestWatchState(payload: payload) == nil, "negative remaining rejected")
    payload = running.payload; payload["remainingSeconds"] = 86401
    check(RestWatchState(payload: payload) == nil, "oversized remaining rejected")
    var gate = RestWatchCommandGate()
    let pause = RestWatchCommand.message(action: .pause, state: running)
    check(gate.accept(pause, state: running, now: now) == .pause, "current pause accepted")
    check(gate.accept(pause, state: running, now: now) == nil, "duplicate command rejected")
    let paused = RestWatchState(timerID: timer, revision: 5,
      deadlineMilliseconds: 0, pausedSeconds: 60, exerciseName: running.exerciseName)
    check(gate.accept(pause, state: paused, now: now) == nil, "old revision rejected")
    check(gate.accept(RestWatchCommand.message(action: .pause, state: paused), state: paused, now: now) == nil, "cannot pause paused timer")
    check(gate.accept(RestWatchCommand.message(action: .resume, state: running), state: running, now: now) == nil, "cannot resume running timer")
    check(gate.accept(RestWatchCommand.message(action: .resume, state: paused), state: paused, now: now) == .resume, "paused timer resumes")
    check(gate.accept(RestWatchCommand.message(action: .extend, state: paused), state: paused, now: now) == .extend, "paused timer extends")
    let other = RestWatchState(timerID: UUID().uuidString, revision: 4,
      deadlineMilliseconds: running.deadlineMilliseconds, pausedSeconds: 0, exerciseName: "Other")
    check(gate.accept(RestWatchCommand.message(action: .extend, state: running), state: other, now: now) == nil, "another timer rejects delayed operation")
    check(gate.accept(RestWatchCommand.message(action: .extend, state: running), state: running, now: now.addingTimeInterval(61)) == nil, "expired timer rejects operation")
    var invalid = RestWatchCommand.message(action: .extend, state: running)
    invalid["commandID"] = "invalid"
    check(gate.accept(invalid, state: running, now: now) == nil, "malformed command rejected")
    invalid = RestWatchCommand.message(action: .extend, state: running); invalid["action"] = "finishWorkout"
    check(gate.accept(invalid, state: running, now: now) == nil, "unsupported mutation rejected")
    print("All \(checks) Watch protocol checks passed.")
  }
}
