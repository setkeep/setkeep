# プロフィール画像の有効化と退会時の削除

2026-10-05: SQL14・22とdelete-account Edge version 3を既存SETKEEP本番へ反映済み。
非破壊検証完了。実Storageのbyte操作・実Auth退会・実機確認・push/配布は未実施。
元HEAD `b610f8f` から分離した `fix/profile-avatar-lifecycle` 専用worktreeを使用した。
保持対応 `1d27ef8` は未適用。通常repo統合は画像ライフサイクルのSQL/Edge/テスト/文書と
認証サービスの失敗案内のみ。既存9変更、UI commit `cebd598`、main.dart/friends_ui、署名設定を保護した。

## 対象と認可

既存マイページUIは `friend_profiles.avatar_path` の存在を検出して写真編集を有効にする。
写真の準備は256×256 PNGへの再エンコードで、元メタデータを引き継がない。
14のbucketは非公開・PNGのみ・512KiB上限。所有者パス制約、Storage RLS9件、
招待プレビュー/最新記録/写真付き接続一覧の3RPCとindexも含む。

新22は追加restrictive guardで、退会済みJWTと退会準備中の本人/承認済み友達の画像操作を拒否する。
他bucketの既存RLSは変更しない。全APIのJWTを失効させる変更ではない。
画像書込はAuth行のkey-share lockを取り、退会準備のupdate lockと同期する。
先行書込が完了してからゲートを閉じ、次の書込は新しい状態で拒否する。

既存コードの署名URLは60秒で発行される。公開範囲変更・解除・退会準備後でも、
発行済みURLは期限まで利用できる場合があり、受取済み画像やキャッシュは遠隔消去できない。
即時完全失効とは説明しない。再エンコードはアプリで行い、API直接アップロードまで強制しない。

## 退会と再試行

既存Auth検証・SQL18の所有者ブロック・7日receiptを維持する。
22のprepareだけが `avatar_cleanup_required:true` を返し、旧DBでは従来フローを維持する。
新規永続資格情報、cron、一括データ削除は追加しない。

1. Authで本人を確認し、prepareで組織所有者をブロックする。
2. service_role限定beginが本人のゲートと2分leaseを取得する。
   他bucketに本人所有物がある場合、または本人prefixのowner metadataが別人/不明の場合は停止する。
3. Storage APIで固定 `friend-avatars/<検証済みUUID>/` を100件ずつ取得する。
   folder・数字PNG以外・外部pathはページ全体を削除せず停止する。
4. leaseを確認し、返された本人PNGの固定prefixだけをStorage APIで削除する。
   offsetは常に0、一回の上限は10ページ/1000件。失敗・上限後は再試行で残りを処理する。
5. 空一覧とSQLの残存0・有効leaseを確認してからAuth DELETEへ進む。
   Auth triggerも残存画像/未確認ゲートを拒否し、既存Authトランザクション内で共有参照を整理する。
6. 失敗時は自分のleaseだけを解放し、ゲートは閉じたままにする。
   他の試行のleaseは奪わず、成功と返さない。成功応答消失は従来receiptで再確認する。

Storageの物理削除はDB/Authのrollbackに含まれない。画像の一部/全部が削除された後でも、
所有権競合やAuth/通信障害で退会が未完了・未確認となることがある。
認証サービスは部分処理と成功確認を分けて案内し、確認済み成功までセッションを保持する。
未完了ゲート中は写真編集も拒否される。再試行、またはlease終了後の本人による明示的取消しが必要。
`cancel_avatar_account_deletion()` は本人限定・稼働中leaseでは拒否する。画像は復元しない。
現UIに取消しボタンは追加していない。

既存のプロフィール差し替え/通常削除の旧画像removeはbest effortで、残存画像は退会時に回収する。
外部ログ/バックアップ全体や30日保証を満たす処理ではない。保持SQL21は今回の対象に含めない。

## 検証

- 元の写真/招待RLS32項目、新ライフサイクルSQL33項目成功。
- 元のSQL回帰9本181項目成功。所有者ブロック、receipt、共有記録・フレンド削除を維持。
- 二つのPostgreSQLセッションで先行書込の待機と、ゲート確立後の書込拒否を確認。
- Edgeの元11件と新10件、合計21件成功。ページ処理、偽造path、再試行、同時lease、所有権競合を含む。
- 認証サービスの限定11件成功、変更した認証サービスとテストのDart解析成功。
- 停止用rollback6項目成功。画像・pendingゲート・Auth安全性を維持。
- 合成Auth/Storage/gate/receiptは0へ戻した。保持21は画像用検証DBに存在しない。

Storageは互換スキーマ、HTTPは合成backendで検証した。
実Storage APIのbyteアップロード/削除・owner metadata・実Authの削除、実機の写真選択/キャッシュ/通信断は未確認。
全Flutter・APK/IPAのビルドは行っていない。

## 本番適用の承認対象と順序

前回READ ONLY確認では14未登録、avatar列/bucket/RLS/3RPCなし、Storage全体0件。
実施直前に再確認し、条件が変わっていれば停止する。個人pathや画像内容はログに出さない。
必要な承認対象は以下。全migrationをまとめた `db push` はしない。

1. 既存SETKEEP本番Supabaseへの **20261004140000_friends_profile_invites.sql** と
   **20261004220000_friend_avatar_account_cleanup.sql** のみの適用。
   一transactionの専用wrapperでsource・履歴・ACL/guardを確認し、schema reloadする。
   未完了の保持21を混ぜず、元18/20・workouts/TRAINERを適用し直さない。
2. **delete-account** Edge Functionの新handlerと `avatar_cleanup.mjs` の反映。
   verify_jwt=trueと既存環境のURL/ANON_KEY/SERVICE_ROLE_KEYを再利用し、新資格情報は作らない。
3. アプリ差分 **lib/services/account_auth_service.dart** の失敗案内をUI担当の変更と統合して確認する。
   main.dart/friends_uiや画像選択UIは変更しない。push・配布は別途承認対象。

途中はbucketをrestrictive停止policyで閉じたままにする。
SQL14/22とEdgeを反映し、非破壊検証を経て、承認された停止policy解除でアップロードを有効にする。
公開bucketにしない。SQLが先行し旧Edgeが残る間、画像所有者の退会はAuth guardが安全に停止する。
既存配布版では新エラーが汎用案内になる場合があり、新しい案内の統合/配布も扱う。

実Storage最終QAは許可された隔離project/合成Authを使い、本番実ユーザー削除は行わない。
登録/変更/削除、private/pending/他人/解除/退会済みJWT、他bucket保護、オフライン/再試行と実Auth退会を確認する。
本番反映済みでも実Storageのbyte操作と実機が未確認のため「実機確認済み」とは報告しない。

rollbackは画像利用と新cleanup RPCを止め、画像・未完了ゲート・Auth guardを残す。
消去済み画像は復元しない。未処理の退会は権限を持つ担当者へ引き継ぐ。

## 2026-10-05 本番反映と既存アプリの有効化

ユーザー本人の直接承認後、原文一致のSQL14・22のみを適用し、delete-accountを
version 3（ACTIVE、verify_jwt=true）へ更新した。一時停止policyは非破壊検証後に解除し、
非公開・PNG限定512KiB・承認済み10 Storage policyを保持した。
既存15件数と無関係な関数定義は前後で一致。
匿名・認証ロールの非実在UUID/他人パス拒否、cleanup表とservice専用RPCの拒否、
Edgeの未認証/無効Bearer 401拒否を確認した。
合成Authユーザー、永続資格情報、実ユーザー/画像の削除は行っていない。

正確な反映範囲、検証結果、未確認事項は
[本番反映QA](qa/profile_avatar_production_2026-10-05.md) を参照。
SQL14は既存commit `9d7cf3f` で追跡済みで、今回のcommitでも原文を変更していない。

通常repoには `9d7cf3f` 由来のマイページ画像設定UIと保存処理が既にある。
ログイン済みでプロフィール行を再取得し、`avatar_path` キーを検出すると写真選択/削除が有効になる。
この実装を含むインストール版はbackend有効化だけで使える構成だが、
有効化前から起動している場合はアプリを再起動して再取得する。
タブのIndexedStackが既存Stateを保持するため、タブ切替だけで再取得されるとは保証しない。
プロフィール行がまだない場合はホームのensureProfileが作成した後に再読み込みが必要。

`30ce889` 以前のコードには画像設定UI/setAvatarがないためbackendだけでは操作画面が増えない。
インストール済みバイナリの元commitは未確認で、実機操作ができたと断定しない。
今回追加した部分削除/退会未確認の詳しい失敗案内を旧版へ届けるにはアプリ更新が必要。
