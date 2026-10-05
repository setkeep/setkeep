# 一般版TRAINER未公開導線

現在のGalaxy配布とは別の変更。検証時点でcommit/push/配布/DB変更/フルnative buildは未実施。

- マイページのTRAINER連携は「準備中」/英語「Coming soon」でdisabled、onTapなし、遷移矢印なし。
- 通知のTRAINER項目を非表示。ホームの通知バッジはフレンド未読だけを集計し、TRAINER unreadCountは呼び出さない。非表示項目の通信失敗によるエラー表示も出さない。
- `lib/config/trainer_release.dart` の `SETKEEP_TRAINER_PUBLIC`（default false）に導線の公開判定を集約。将来公開時は同じ判定で連携・通知入口を戻せる。通知UIの明示的なopt-inテストで従来経路も保持。
- 既存連携、代理記録の同期、保存記録、コメント、TRAINER本体、未読状態の保存は変更しない。一般版でTRAINER通知を読んだ扱いにはしない。
- フレンド通知だけを注入したヘッダーでも初回取得・定期取得が動作するようにし、TRAINERリポジトリの有無へ依存しない。
- 関連・回帰117件成功（公開ゲート3件、フレンド通知、TRAINER配信/共有/同期、既存widget画面、home/profileプレビュー）。最終波括弧修正後の通知5件再検証成功。新規通知プレビュー1件成功。
- TRAINER本体の全通常テスト24件成功。上記117件＋新規通知プレビュー1件＋TRAINER24件＝142件成功（最終通知5件の重複再実行は別）。全体解析成功後の空き12GiB。
- `flutter analyze --no-pub`: No issues found。`git diff --check`: 成功。
- 390×844の日本語合成画面画像を実pixels確認。準備中の連携項目と、フレンドのみの通知項目を確認。画像は `trainer_public_gate_2026-10-05/`。
- 新規プレビューは独立ファイル。自動レビューが当初の生成コマンドを既存テスト上書きの危険として拒否したため、既存テストを参照しない新規テストに変更して成功した。残る拒否ブロックはない。
- 前回からの広告・署名・splash等9変更とApple Watch QAを保持。`main.dart`は広告差分と混在するのでcommit時は部分ステージが必要。
