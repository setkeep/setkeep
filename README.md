# SETKEEP

SETKEEPは、トレーニング記録を蓄積し、次のトレーニングにつなげるFlutterアプリです。

## 対応

- iOS / Android
- 日本語 / 英語対応を前提とした構成

## 主な機能

- 重量・回数・セット単位のトレーニング記録
- 前回記録の参照・反映、入力途中データの自動保存と再開
- 月間カレンダーを使った履歴確認・修正・削除・再実行
- マイメニュー、カスタム種目、トレーニング場所の管理
- セット完了チェック、トレーニング時間、休憩タイマー
- 種目別の最高重量・推定1RM・成長記録
- 期間を切り替えて確認できる3D筋肉ヒートマップ
- 種目ごとのターゲット筋・フォームを確認できる3D表示
- JSON / クリップボードを使ったバックアップと復元
- Supabase接続・アカウント・クラウド同期の基盤

READMEでは主要機能のみを扱います。個別の修正履歴や検証記録は `docs/` 以下、開発時の恒久ルールは `AGENTS.md` を参照してください。

現行の確定仕様（ブランド、B2B料金、TRAINER通知、Android休憩タイマー、3D進捗）は [現行確定仕様](docs/current_spec.md) を参照してください。

## データ保存

通常のアプリデータはローカルへ保存し、アプリ再起動後も記録を保持します。

バックアップ・復元機能に加え、Supabaseを利用したクラウド同期の基盤があります。秘密情報やSecret key、service_role keyはリポジトリへ含めないでください。

## 開発

依存関係を取得:

```sh
flutter pub get
```

静的解析:

```sh
flutter analyze
```

テスト:

```sh
flutter test
```

アプリ起動:

```sh
flutter run
```

Supabase設定を使って起動する場合:

```sh
flutter run --dart-define-from-file=supabase.json
```

`supabase.example.json` を参考にローカル用の `supabase.json` を作成してください。`supabase.json` はGit管理対象外です。

公開済みのフレンド招待ページを使うビルドでは、同じ設定ファイルに `"FRIEND_INVITE_BASE_URL": "https://boredota.com/invite"` を含めてください。Androidの `tool/build_android_beta.sh` とiOSの `flutter build ipa --release --dart-define-from-file=supabase.json` はこの設定を読み込みます。HTTPSリンクは招待ページを開き、ページの「アプリで開く」で既存の `setkeep://friend-invite/…` へ遷移します。Universal/App Linksの自動起動は別の関連付け・署名設定が必要です。招待はログインを跨いで保持し、申請成功時だけ消費します。

## 開発方針

- 既存設計・UI・命名規則を尊重する
- iOS / Android両方で動作する構成を維持する
- 3Dは共通アセット・共通実装を優先し、重複と容量増加を抑える
- 変更後は関連する解析・テスト・実機またはシミュレーター確認を行う

より詳細な開発ルールは `AGENTS.md` を参照してください。

## SETKEEPへの移行

識別子・旧データ互換性・外部サービス設定・検証結果は [ブランド移行記録](docs/setkeep_migration.md) を参照してください。

## SETKEEP TRAINER

同じSupabase Authを使う独立アプリを `apps/setkeep_trainer` に追加しています。
一般版は引き続きリポジトリ直下で開発します。[開発・実機確認ガイド](docs/setkeep_trainer.md) を参照してください。

## TRAINERとの共通データ連携

一般版ホームの「トレーナーからのメニュー・コメント」で、本人に割り当てられたSupabaseの共通データを参照します。メニューから通常のトレーニングを開始できます。[両アプリ共通の連携仕様](docs/setkeep_trainer_delivery.md) に保存構造・公開範囲・更新・RLS・migration条件を記載しています。
