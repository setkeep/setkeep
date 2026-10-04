# Apple Watch / iPhone連携 — 2026-10-04

対象: 通常の `/Users/macintosh/Documents/Codex/muscle_memory`、ブランチ `fix/friends-ux-local-integration`、開始時HEAD `9d7cf3f`。

## 実装済み

- SwiftUIの `SetkeepWatch` target、共有scheme、RunnerへのWatch同梱・依存関係を追加。watchOS 10以降。bundle IDは `com.setkeep.app.watchkitapp`、companionは既存 `com.setkeep.app`。
- 通常チェックアウトにあったWatch準備コードを再利用。WatchConnectivityでiPhone所有の休憩タイマーを表示し、一時停止、再開、30秒延長、手動更新に対応。既存の通知・Live Activity・Flutterのタイマー状態更新経路を使用する。
- Watchは期限から残り時間を表示する。接続がない間は操作を無効にし、操作コマンドを遅れて再送するキューは持たない。タイマーID、revision、command UUIDで別タイマー、古い状態、重複コマンドを拒否する。
- 日本語・英語のWatch UI、既存ブランド色 `#C7F36B` とアイコンを使用。タイマー終了・キャンセル時に種目名も消去する。
- Workoutのセット・重量・回数編集や保存、独立したWatchワークアウト記録、HealthKit連携は今回のネイティブWatch画面には含まれない。WatchはSupabase資格情報やトレーニング履歴を持たない。以前の別作業場所にあるフル記録同期ドラフトは通常チェックアウトへ混在させていない。

## 既存変更の保護

開始時の未コミット変更を作業領域 `task/backups/apple-watch-authorized/` にパッチ・ファイル・SHA-256で退避。広告、スプラッシュ、main.dart、既存テスト、仕様書を含む保護対象8ファイルは終了時も同じSHA-256。開始時のRunner、Widget、RunnerTestsを含む全既存XCBuildConfigurationは追加後も辞書として一致する。新Watch targetは現在の既存署名Teamを使用し、既存Team、証明書、provisioning profile、entitlements、Appleアカウント設定は変更しない。

変更は通常チェックアウトの未コミット差分として保持する。他の保留中変更も保持し、remote push、merge、デプロイ、DB変更、TestFlightアップロードはこの作業では行わない。

## 検証

- `flutter analyze`: No issues found。
- `./tool/test_apple_watch.sh`: 19項目成功。期限からの残時間、期限切れ、schema不一致、不正値、重複、古いrevision、別タイマー、一時停止/再開の状態制約、未対応操作を検証。
- `xcodebuild ... -scheme SetkeepWatch -sdk watchos ... CODE_SIGNING_ALLOWED=NO build`: 成功。実機向けarm64/arm64_32。
- `xcodebuild ... -scheme SetkeepWatch -sdk watchsimulator ... CODE_SIGNING_ALLOWED=NO build`: 成功。
- `flutter build ios --debug --no-codesign --no-pub`: 成功。`build/ios/iphoneos/Runner.app/Watch/SETKEEP Watch.app` にWatchバイナリ同梱を確認。既存RestTimerWidgetも同梱。
- 生成したiPhone / Watch / Widgetのversionはすべて `1.0.0 (7)`。元の設定を維持したもので、次回配布用の番号をこの作業では変更していない。
- `flutter test --no-pub`: 全436テスト成功。既存の記録、同期、タイマー、広告、スプラッシュ、フレンド機能の回帰テストを含む。
- `git diff --check`: 成功。

ビルド・テストログは作業領域 `task/apple-watch-rest-integration/` の `watch-build.log`、`watch-simulator-build.log`、`iphone-build.log`、`flutter-analyze.log`、`protocol-repo-tests.log`、`flutter-test.log`。WatchConnectivityの仕様は [Apple公式ドキュメント](https://developer.apple.com/documentation/watchconnectivity) を参照。

## 実機未確認 / 配布引継ぎ

Watch Simulator SDKでのビルドは成功したが、このMacのインストール済みSimulator runtimeはiOSのみで、Watch画面の起動・ペア通信テストは実施していない。ペアリング済み実機でも未確認。

配布担当は上記ブランチの**未コミット変更を含む通常チェックアウト**を使用すること。署名無しDebug成果物はそのままTestFlightへ配布できない。現在のTeamでWatch bundle IDの配布用provisioningが利用できることを確認し、配布用version/buildを揃えた署名済みRelease archiveを作成してから配布検証する。

実機で確認する項目:

1. iPhoneのセット完了または手動休憩開始がWatchへ反映される。
2. Watchの一時停止・再開・30秒延長がiPhone画面、通知期限、Live Activityに一致する。
3. 接続断中の操作は無効。再接続時に最新状態を受信し、前のタイマーの操作が新タイマーへ適用されない。
4. iPhone/Watchのバックグラウンド復帰、タイマー終了、手動停止、ワークアウト終了、ログアウト後に古いタイマー操作や種目表示が残らない。
5. 通知許可の許可/拒否、Watch未装着、iPhoneの通知設定ごとの完了表示・音・振動と、通常の記録保存・同期を確認する。

本作業の自動テストは通信プロトコルと既存Flutter回帰テストであり、実機のWCSession輸送、通知、音・振動の成功を証明するものではない。
