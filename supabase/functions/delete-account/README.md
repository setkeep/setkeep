# アカウント削除

Google・メール共通、Premiumに依存しない。端末のトレーニング記録・身体記録・設定は保持する。
成功応答後だけローカル認証情報を消去する。サーバー削除失敗・所有者ブロックではセッションを保持する。
端末保存の消去だけが失敗した場合は「アカウントは削除済み、端末のログイン情報を消去できない」と区別して表示する。

## サーバー契約

`POST /functions/v1/delete-account` はBearer必須。本文のユーザーID・Premium・完了フラグを無視し、
Auth `/user` が検証した本人だけをAdmin APIで完全削除する。管理キーはEdge環境だけで使用する。

1. トークンのSHA-256を計算し、Authで本人と現在の存在を検証する。
2. service_role専用 `account_deletion_prepare` で所有者を確認し、受付を記録する。
   この段階でTRAINER・フレンド・記録の参照を変更しない。
3. Admin DELETE (`should_soft_delete:false`) を呼ぶ。Auth DELETEのDBトランザクション内の
   BEFOREトリガーが参照を整理し、AFTERトリガーが受付を完了にする。
   FK・Storage等で削除が失敗するとDB処理は全てロールバックされる。
4. 完了応答が通信断で失われても、同じBearerのハッシュの完了受付をservice_roleで照合する。
   未完了受付・別のBearer・本文のIDで成功を偽装できない。同時DELETEの404も完了受付がある場合だけ成功。

DBとAuth HTTPを跨ぐ事前データ削除はしない。受付だけが未完了として残る失敗は安全に再試行できる。
アプリの同時退会呼び出しは同じFutureを共有する。失敗後は次の呼び出しで再試行できる。
HTTPの成功はAdmin APIの成功またはDB完了受付に限る。外部Auth HTTP実サービスはローカル検証対象外。

`account_deletion_requests` はRLS有効・一般ユーザーの権限無し。
保存するのはSHA-256、UUID、受付時刻・完了時刻だけ。Bearer・メール・記録・上流エラー本文は保存しない。
完了照合は7日間。次の正常なprepareで7日より古い受付を掃除する。
アクセスのない環境の物理保持期間を保証するには、運用側で次の定期削除を設定する必要がある（未設定）。

```sql
delete from public.account_deletion_requests
where coalesce(completed_at,requested_at)<now()-interval '7 days';
```

`verify_jwt=true` を維持する。同じ未失効Bearerでの再試行が対象。
JWT失効・端末のSDKによるトークン更新失敗・受付期限切れでは自動完了確認できないことがある。
その場合は管理者がAuthの有無を確認する。受付照合は削除完了の確認専用で、認証・アクセス権には使わない。

## データへの影響

- **本人のクラウド記録・フレンドデータ**: 既存のAuth FK CASCADEに従う。
  本人のフレンドプロフィール・接続・投稿・本人のいいね/コメントを削除する。
  本人の投稿に付く他者のいいね/コメントも投稿の削除連動で削除される。
  別の人の投稿・アカウント・トレーニングは保持する。
- **TRAINERクライアント**: linked_user_idを外し、revokedにし、共有・記録許可を全て無効化する。
  クライアント表示名を「退会済みユーザー」に置換する。
  組織のクライアント行・メニュー・コメントは保持する。本人所有のworkoutsは既存CASCADEで削除。
- **TRAINERスタッフ**: 担当割当→所属の順に削除する。メニュー/コメントの作成者・編集者、
  テンプレート作成者、既読者、記録の取消者をNULLにする。他者の記録の内容は削除しない。
  recorded_byは従来のSET NULL。旧TRAINERリンクの橋渡しを先に外し、legacy_trainer_idも外す。
- **招待**: 退会者が使用/作成した招待と、退会者のクライアント宛招待を無期限に失効させる。
  expires_at=-infinityを先に設定してからused_by/created_byを外し、古いトランザクション時刻でも再利用不可にする。
  終端失効トリガーが後日の再発行処理による期限の書換えも阻止する。
- **組織所有者**: billing_owner_idが残る間は409 `tenant_owner_requires_transfer`。
  クラウド/共有情報を変更せず、アプリに所有権移管・閉鎖の問い合わせが必要な理由を表示する。
  所有権や請求契約の移管・組織閉鎖をこのFunctionが自動実施することはない。
  既存TRAINERの組織管理にある「請求責任者を移譲」（tenant_mutate owner）を再利用し、
  現在の所有者から有効な所属メンバーへ移管した後に再試行する。移管先の権限・請求対応も確認する。
  この既存RPCによる移管と元所有者の退会を隔離DBで検証済み。組織閉鎖の自動処理は追加しない。
- **店舗報告**: 導入済みなら店舗報告の投稿者/審査者、店舗変更履歴の担当者をNULLにする。
  報告内容・店舗マスター・変更履歴・他者の報告は保持する。設備や店舗マスターを巻き戻さない。
- **監査・保持**: tenant_auditや共有コメント本文・報告本文等の保存内容を全て匿名化する処理ではない。
  監査には過去の氏名・UUID等が残る場合がある。保存期間・バックアップ・組織側のコピーや書き出しは
  別途運用方針が必要。全データ即時完全消去と説明しない。
- **Storage/追加FK**: 未対応Storage所有物や新たなFKがあれば、安全に削除を拒否する。
  無断のStorageバケット一括削除や無関係なデータ削除は行わない。

適用だけでは既存ユーザーのデータを変更しない。著者列6個と導入済み店舗報告user_idのNOT NULLを緩和する。
RLSや一般ユーザーの書込権限は広げない。本人退会時に参照UUIDを外すための変更。
対象テナントを既存mutationと同じ順序でロックする。デッドロック/タイムアウト時もロールバックされ再試行可能。

## 反映・ロールバック

適用SQL: `supabase/migrations/20261004180000_account_deletion_offboarding.sql`
前提: 現在のTRAINER/既読/フレンドマイグレーション。店舗報告が存在する場合のみ対応する。
本番スキーマのFK・Storage所有物・Authトリガー作成権限を適用前に確認する。
SQLを先に、続いてこのFunctionを反映する。新Functionを旧DBへ反映するとprepare失敗で削除を止める。
アプリだけを先に反映しても、サーバー側の修正は有効にならない。

旧Functionへ戻す場合はDBの安全トリガーを保持するのが第一選択。
完全なスキーマ逆戻しは `supabase/rollback/20261004180000_account_deletion_offboarding.sql` を使う。
NULL化済み行があると元のNOT NULLへ戻せないため、スクリプトは変更前に停止する。
削除済みAuth・CASCADEデータ・元の参照UUIDをロールバックSQLが復元することはない。
2026-10-04: このSQLのみ本番へ適用し、delete-accountをversion 2へ更新済み（ACTIVE、verify_jwt=true）。
実ユーザー削除・定期処理の設定は未実施。非破壊の本番確認と証跡は
`docs/qa/account_deletion_production_2026-10-04.md` を参照。

## ローカル確認

```sh
node --test supabase/functions/delete-account/handler_test.mjs
flutter analyze --no-pub
flutter test --no-pub test/account_deletion_service_test.dart test/required_account_gate_test.dart
```

隔離DBで `supabase/tests/account_deletion_offboarding.sql` を実行する（合成データ、最後にROLLBACK）。
店舗テーブル導入環境では `supabase/tests/account_deletion_store_references.sql` も実行する。
TRAINER・既読・所有者記録削除・フレンドの既存SQLを回帰確認する。
旧 `trainer_foundation.sql` はtenant_foundation以前の専用テストであり、最新スキーマでは旧RPC権限が撤回済み。

本番の実機Google/メール退会・Storage所有物・通信断・再起動はまだ未確認。
Auth削除後でも発行済みJWTは失効まで有効になり得る。他APIの即時失効はこの変更で保証しない。
参考: https://supabase.com/docs/guides/auth/managing-user-data

## 法的文面の別変更提案

`lib/legal/legal_text.dart` の未承認全文は変更/公開しない。
policywriter草案と照合して別途扱う対象:

- AdMob「未導入/将来予定」を実ビルドのSDK同梱・現コードのテスト広告リクエストへ修正する。
  実通信の未検証範囲と未導入Stripeを分ける。
- フレンド共有・コメント/いいね・TRAINER既読・Watchタイマー連携の説明を補う。
- 無料の共有と準備中のPremium通常クラウドバックアップ、現在のローカル写真共有と未適用アバターを分ける。
- 上記の端末記録保持・組織記録/監査保持・所有者ブロック・失敗時再試行を削除説明へ反映する。
- 保存期間/バックアップ期間、運営者・連絡先・公開URLは確認済み方針を使い、未確認値を作らない。
- 設備報告の条件付き自動反映を現仕様に合わせる。ATT/UMP不足は文面変更だけで解決した扱いにしない。
