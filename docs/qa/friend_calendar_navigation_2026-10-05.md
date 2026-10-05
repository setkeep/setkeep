# フレンド月間カレンダー・下部タブ表示確認

- 対象: `fix/friends-ux-local-integration` / 基点 `b610f8f`。commit・push・DB操作・APK/IPAビルド・配布は実施しない。
- フレンド詳細のプロフィール／ヒートマップと詳細／いいね／コメントを維持。履歴タブから切り出した `WorkoutMonthCalendar` を共用し、ローカル日付の記録日マーカー、月移動、選択日のセッション一覧を表示。日付／月の変更で詳細選択をクリアし、読み込み中の変更を抑制する。
- 下部ナビゲーションは71×57の枠を全タブで共用。枠の色と角丸、icon＋labelを維持。狭い幅はタブの割当幅に収まり、内容は必要時に縮小表示。
- 関連テスト18件成功: `friend_calendar_navigation_test.dart`, `friends_mvp_test.dart`, `friends_ux_test.dart`, `friend_comment_notifications_test.dart`, `friend_calendar_preview_test.dart`。
- 最終状態の全通常Flutterテスト: SETKEEP本体67ファイル466件、TRAINER24件、計490件が全件成功（`flutter test --no-pub --concurrency=1`、本体6分54秒・TRAINER31秒）。native integration testは未実施。最終空き17GiB。
- 全体画面／完了フロー回帰94件成功: `widget_test.dart`, `workout_completion_test.dart`。関連18件と合わせて112件成功。
- `flutter analyze --no-pub`: No issues found。`git diff --check`: 成功。
- 日本語390×844の合成データ画像を実pixels確認。カレンダー・同日2件・空日表示・4タブの枠に重なり／切れなし。280px幅・文字倍率2の切り替えはwidget testで寸法一致・例外なしを確認。
- 画像: `friend_calendar_navigation_2026-10-05/`。個人データは使用しない。
- 実機／nativeビルドは今回の範囲外。既存署名・splash等の差分を保持し、avatar実装は変更しない。
