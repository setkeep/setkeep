# 修正版の統合・本番依存確認

## 追加SQLの正確な範囲

未適用草案 `supabase/migrations/20261004140000_friends_profile_invites.sql` は、既存 `friend_profiles.avatar_path` nullable text列とUUID所有者パス制約1件、非公開Storage bucket `friend-avatars`（PNGのみ、512KiB上限）、Storage policy9件、RPC3件、インデックス1件。新しいpublicテーブルはない。

- 所有者のみ写真のinsert/update/delete。フレンドの写真はaccepted接続＋所有者visibility=friends＋現在のavatar_path一致が必要。匿名には拒否。
- permissive policy4件に加えrestrictive guard5件。別の広いStorage grantがあっても写真bucketの制限を維持し、他bucketにはtrueを返して既存挙動を保持する。PostgreSQLの[policy合成仕様](https://www.postgresql.org/docs/current/sql-createpolicy.html)に従う。
- `lookup_friend_invite(uuid)` はログインと相手のUUIDコードが必要。返すのは表示名と自分との接続statusのみ。写真・記録・相手UUID・他の接続を返さない。未承認者にもコードを持っていれば表示名をプレビューできる点は意図した例外。
- `latest_friend_workouts()` はsecurity invokerで既存workout RLSを維持し、他人の最新1件のみ。`friend_workouts_owner_recent` インデックス。
- `list_friend_connections_with_avatar()` は自分が当事者の接続のみ。acceptedかつ相手visibility=friendsの場合だけavatar_pathを返す。

既存visibilityのUPDATE、履歴バックフィル、通常workouts・Authユーザー・TRAINER・Premiumバックアップへの変更はない。既存非公開データは自動公開されない。写真は256×256PNGに再符号化してメタデータを除く。署名URL60秒、すでに表示／キャッシュ／発行したURLは完全に回収できない。

本番は読み取り専用のスキーマ確認だけ実施。Storage objectsのRLS有効、既存policy0件、今回bucket・列・migration履歴はいずれも存在しない。本番データ行や秘密値は表示していない。追加草案は適用していない。

ローカル認可検証は元MVP34件＋追加32件＝66件通過。広いStorage grantが存在するfixtureでも、匿名・未承認・他人・非公開の写真読取／他人への書込・所有権移動拒否、他bucket既存挙動の保持を確認した。

ロールバックは新アプリを戻した後、別途transaction内で `supabase/rollback/20261004140000_friends_profile_invites_access_stop.sql` を実行する案。新3RPCのauthenticated実行権限を取り消し、写真bucketだけrestrictive ALL denyを追加する。プロフィール・写真ファイル・元MVP・記録・他bucketを残す。実際のrollbackファイルを使った保持／拒否テスト10件通過。本番では未実行。完全削除が必要ならStorage APIで物理ファイルを削除してから専用の前進migrationでschemaを整理する。storage.objectsのSQL削除だけで済ませない。

## 追加DBなしで試す互換経路

既存のプロフィールSELECT *にavatar_path列が含まれるかで拡張schemaを判定する。列がない場合は写真変更を非表示、既存list_friend_connections RPCで接続管理、承認済み各友達に既存friend_workoutsから最新1件を取得する。招待の相手名プレビューは省き、コードの相手への申請を明示確認し、既存request_friend RPCが無効・自己・重複を拒否する。公開同意とprivate維持、既存記録同期を継続。拡張SQLは写真と申請前の相手名プレビューを有効化するときに適用判断が必要。

## コメントの現状と通知

統合前main30ce889と新UXは共に、ホームのフレンドカード→日付別の詳細→セット・いいねの下に「短いコメント」「コメント」と既存コメント本文を表示。選択中sessionが取得できること、accepted接続、記録所有者の公開同意が必要。解除／非公開／記録削除は既存RLSと再取得で読取を拒否する。初期にはホームにコメント数や説明がなく、詳細の下方まで進む必要があった。自分へのコメントを見る専用入口は両版とも欠けていた。実機で見たという確認はしていない。

最新依頼で追加した導線は、ホームcardのコメント数、右上ベル合計未読→「フレンドから」「トレーナーから」各件数→フレンド通知→自分の対象sessionのコメントまでスクロール。既存TrainerInboxPageと既読RPCを再利用し、分類画面を開くだけではトレーナー通知を既読にしない。

フレンド通知は既存friend_comments／friend_workouts／接続から取得する。自分のコメント、未承認者、他人の記録を除外し、同じcomment IDを重複表示しない。privateや解除後は一覧・件数から除外、tap前と詳細reload時にも再確認。記録削除は既存cascadeでコメントも消える。表示に成功したcommentだけ既読にする。既読IDはアカウント別の端末設定へ保存し、本文や個人データは通知キャッシュに保存しない。別端末・再インストールとの既読同期はない。通知用の追加SQL／本番変更は不要。OS push/APNs/外部メッセージ送信は行わない。

## HTTPS招待の現状と最小案

repo/configには所有確認済みアプリ公開ドメイン、HTTPS招待route、AASA、assetlinks、関連付けentitlement、公開storeリンクは確認できない。既存Supabase API hostは公開招待サイトとして使わない。カスタムscheme `setkeep://friend-invite/<UUID>` とコード共有・受信・ログイン前保持は実装済み。未設定のFRIEND_INVITE_BASE_URLには架空URLを設定しない。

最小案は所有確認済みHTTPS host上にUUIDを受ける1ページを用意し、既存schemeでアプリを開くボタン、コードコピー、未インストール時の検証済みStore/TestFlight案内を置く。公開ページからプロフィールや記録を取得しない。インストール後は元リンクの再訪またはコード入力が必要。自動deferred linkは未実装。

Universal Linksには同hostのAASAとRunner associated domains、実際に署名される新Teamのapplication identifierを一致させる必要がある（[Apple公式](https://developer.apple.com/documentation/xcode/supporting-associated-domains)）。Android App LinksにはHTTPS intentfilterとassetlinks.json、配布証明書のSHA256が必要（[Android公式](https://developer.android.com/training/app-links/verify-applinks)）。実在host/DNS/TLS/ページ公開、関連付けファイル、配布先URL、署名・provisioningの設定が外部作業。Widgetのentitlementは変更しない。公開・本番設定は未変更。

## 参照画像とUI確認の限界

Libraryから5画像を実際に取得・閲覧済み。最初の3枚はマイページカード／タブ背景／行余白のmock、残り2枚は利用者画面。個人データは転記しない。合成名・記録なしのFlutter描画からhome.png/profile.pngを生成した。実機スクリーンショットではなく、390×844のローカルwidget描画。写真選択、LINE共有、実Storage upload、2実アカウントでの操作、TestFlightでの見た目は未確認。

## 広告についてコードで確認した現状

通常版・新UX版は同じ広告実装。ホームtabの本文下／tab bar上にadaptive banner1枠、他tab・覆われたroute・背景・adFree時は表示しない。全画面は記録完了後「ホームへ戻る」、または完了から開くSNS共有画面を閉じる時に1session1回試行。編集・破棄で新規表示しない。端末ローカル日付で実表示がSDK確認された日を保存し、1日最大1回。読込失敗で日枠を消費しない。アカウント間の日上限同期や複数端末間同期はない。

Rewarded広告の実装なし。adFreeは将来の検証済み課金権限の接続口だけで、月額価格・購入／復元・ストア課金は未実装。AdsConfigのdefaultはtest、Google sample広告IDのみ。production/off/未知modeは広告IDなしで表示を止める。現状のtest広告を収益対象として数えない。収益単価の推測はしていない。

## 署名を保持した統合

通常muscle_memoryのRunner Debug/Profile/ReleaseとWidgetのTeam58CC3T56JQを確認。project.pbxprojはfeature差分に含めず、元の未コミット変更9件と未追跡QA文書をバックアップしてからUI差分だけをローカルbranchへ適用する。保護した起動・広告差分をfeature commitへ混ぜず、作業ツリーには保持する。remote push/main merge/本番migration/公開は今回行わない。旧IPA1.0.0(7)を配布しない。新UIの再署名build・TestFlight確認は署名担当へ引き継ぐ。
