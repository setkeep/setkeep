# 退会修正の本番反映 2026-10-04

実装コミット: `dbb30846027b2681783e98e197d0f734daf13631`。
通常の `muscle_memory` の `fix/friends-ux-local-integration` へ統合・push済み。
既存9差分を保持し、署名設定は変更しなかった。mainへの反映・アプリ配布は対象外。

## 本番バックエンド

- 対象: 既存SETKEEP Supabase `meyrtimwibqonozsewbt`。
- `20261004180000_account_deletion_offboarding.sql` のみ適用。同一トランザクションで履歴を記録。
- migration履歴に追加されたのはこの1件だけ。`20261004140000_friends_profile_invites.sql` は未適用のまま。
- 登録したmigration本文のMD5、5関数の本文MD5をローカル承認コードと照合し一致。
- Auth削除前後・招待終端失効の3トリガーが有効。著者列7項目がnullable。
- 受付表はRLS有効。一般ユーザー・anonはprepare/receiptの実行と表参照不可。service_roleのみ実行可能。
- `delete-account` のみ更新し、version 2 / ACTIVE / verify_jwt=trueを確認。
- 更新後に関数を再取得し、index.tsとhandler.mjsのSHA-256がローカルコードと完全一致。
- 他のEdge Functionのversion/statusは不変。既存delete-accountは別ディレクトリにバックアップした。

## 非破壊確認

実ユーザーのセッションもDELETEリクエストも使わなかった。
キーはメモリ上で扱い、チャット・検証結果ファイルへ保存/出力しなかった。

| 確認 | 結果 |
|---|---|
| 認証なしPOST | 401 |
| 無効トークンPOST | 401 |
| 公開anonキーによるGET | ハンドラの405 |
| 公開anonキーによるPOST | Auth検証と完了受付照合を経て401 verification_failed |
| anonによるprepare RPC | 401 |
| anonによるreceipt RPC | 401 |

反映前・SQL反映後・HTTP確認後でAuthと主要記録の集計件数は同じ。
受付表0行。個人のID・メール・記録本文は取得/表示していない。

## アプリとローカル検証

- 分離修正: Flutter435件、既存9差分併用439件、TRAINER24件、ハンドラ11件。
- 新SQL47項目と既存SQL6ファイル。失敗ロールバック、使用済招待再発行拒否、
  既存TRAINER所有権移譲RPC後の退会、他者の記録保持を確認。
- 通常チェックアウト統合後: 退会・認証15テスト成功、flutter analyze問題なし。
- 完全スキーマrollbackはNULL化済み参照があれば安全に停止する。未使用状態のrollback/reapplyは検証済み。
- 法的文面の全文は変更/公開していない。AdMob・フレンド・Watch・保持条件の文面は別途草案と照合する。

## 未確認・運用事項

実機でのGoogle/メール退会、実ユーザーのAuth削除、Storage所有物がある退会、
実通信断・再起動は未確認。不可逆なテスト削除は今回実施していない。
既存アプリ配布物を更新した扱いにはしない。

端末記録、他者の記録、組織のメニュー/コメント/テンプレート、監査、店舗報告/履歴は保持。
本文や監査の完全匿名化ではない。所有者は既存「請求責任者を移譲」後に退会する。
保存期間・監査/バックアップ方針は別途確定が必要。

完了照合は同じ未失効Bearerで7日間。JWT失効やSDKの更新失敗では運営者確認が必要な場合がある。
受付の定期物理削除は未設定（prepare時の7日超掃除のみ）。
証跡は作業領域 `auth-deletion-production/` のschema/ACL/hash/HTTP結果として保存済み。
