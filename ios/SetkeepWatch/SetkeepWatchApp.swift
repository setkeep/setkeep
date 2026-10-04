import SwiftUI

func watchText(_ japanese: String, _ english: String) -> String {
  Locale.preferredLanguages.first?.hasPrefix("ja") == true ? japanese : english
}

@main
struct SetkeepWatchApp: App {
  @StateObject private var session = WatchSessionModel()
  var body: some Scene {
    WindowGroup { RestWatchView().environmentObject(session) }
  }
}

struct RestWatchView: View {
  @EnvironmentObject private var session: WatchSessionModel
  @Environment(\.scenePhase) private var scenePhase
  private let accent = Color(red: 199 / 255, green: 243 / 255, blue: 107 / 255)

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        Text("SETKEEP").font(.caption.bold()).foregroundStyle(accent)
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let seconds = session.state?.remaining(at: context.date) ?? 0
          let phase = session.state?.phase(at: context.date) ?? "idle"
          VStack(spacing: 8) {
            Text(phase == "paused" ? watchText("一時停止中", "Paused") : watchText("休憩タイマー", "Rest timer")).font(.caption)
            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
              .font(.system(size: 42, weight: .bold, design: .rounded)).monospacedDigit()
              .minimumScaleFactor(0.6).lineLimit(1)
            if phase != "idle" {
              Text(session.state?.exerciseName ?? "").font(.caption).lineLimit(2)
              Button(phase == "running" ? watchText("一時停止", "Pause") : watchText("再開", "Resume")) {
                session.send(phase == "running" ? .pause : .resume)
              }.tint(accent)
              Button(watchText("＋30秒", "+30 seconds")) { session.send(.extend) }
            } else {
              Text(watchText("iPhoneで休憩タイマーを開始してください", "Start a rest timer on your iPhone")).font(.caption)
            }
          }
          .disabled(!session.reachable || session.sending)
        }
        if !session.reachable {
          Text(watchText("iPhoneへの接続待ち", "Waiting for iPhone")).font(.caption2).foregroundStyle(.secondary)
        }
        if !session.message.isEmpty {
          Text(session.message).font(.caption2).foregroundStyle(.secondary)
        }
        Button(watchText("更新", "Refresh")) { session.refresh() }.font(.caption)
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 6)
    }
    .onAppear { session.refresh() }
    .onChange(of: scenePhase) { _, phase in if phase == .active { session.refresh() } }
  }
}
