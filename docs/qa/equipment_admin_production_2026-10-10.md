# 設備報告管理 migration 本番適用

2026-10-10、本人の本番DB変更承認に基づき `20261010230000_equipment_candidate_admin_actions.sql` だけを既存linked接続で適用した。アプリ設定hostとlinked projectが一致することを確認。対象既存関数13本の本文MD5は適用前のローカル定義と一致。

## 権限の限定

本番public schemaの既定ACLによる新規service_role付与を事前検出し、その時点では適用を停止。新規管理RPC3本・補助関数2本・新規履歴tableだけからservice_roleの権限を明示撤回する限定修正を行った。既存自動処理入口のservice_role EXECUTE、schema既定ACLは維持。

本番同等の既定ACLを再現した使い捨てローカルDBで、初回migration適用、管理操作SQLテスト、既存SQL回帰8本、複数接続競合5ケースが全成功。

## 適用と読み戻し

Supabase CLI `db query --linked --file` で、対象migrationと `supabase_migrations.schema_migrations` の履歴登録を同transactionで実行。全migration一括pushはしない。5秒lock timeout・60秒statement timeout、事前関数hash/ACL/設定/データhash照合と適用後assertionを付加した。commit後の別read-only接続で次を確認。

- migration履歴 `20261010230000 / equipment_candidate_admin_actions` 登録済み。
- 設備報告・店舗設備・適用履歴・既存候補（追加列を除く）の全行aggregate hashが適用前後で一致。
- 既存RLSと自動ルール設定は不変。既存候補は保留されず、review_version=1。新規操作履歴0件。
- 新管理RPC3本: authenticated EXECUTEあり、anon/service_role EXECUTEなし。管理者判定を関数内で実施。
- 新補助関数2本: anon/authenticated/service_role EXECUTEなし。
- 新履歴table: authenticated SELECTのみ、管理者条件RLS。anon/service_roleのSELECT・書込なし。
- 既存報告INSERT/SELECT、update_admin_reportとconfirm_training_equipmentのauthenticated EXECUTE維持。status/admin_noteの直接UPDATEは撤回。
- 未認証のauthenticatedロールで新3RPCが42501拒否。実報告のIDを使わず、read-only transactionで確認。
- 既存アプリの公開publishable接続情報をプロセス内だけで使い、PostgRESTの新3RPC公開入口が全てHTTP401 / 42501でanonを拒否することを確認。キーを出力・転送せず、設定変更なし。

migrationファイルSHA256: `c653afa437c5e23f4e3db00fc4db93477943909da585b94cd777210e6d56b66a`。

## 範囲と残作業

実在報告の採用/見送り/保留/解除/rollback、本番合成データ作成、管理者追加、新規credential作成・設定、Site公開、push/deployは行っていない。既存の無関係なローカル変更は保全。

Site担当の残作業は本人Supabaseログインと既存管理者認可、一覧・履歴の読取接続確認。管理者JWTでのSite操作E2Eは未実施。保留解除で条件が満たされれば、その解除RPC内で自動反映される旨を確認文に含める。実在報告の処理は別操作として本人が実行する。

契約: `docs/admin/equipment_candidate_admin_api.md`。
再現QA: `python3 tool/equipment_review/run_local_qa.py`。

## Site Googleログインの戻り先追加

同日、本人の1URL追加承認後に、Supabase Auth additional_redirect_urlsへ
`https://setkeep-work-dashboard.go10go104649.chatgpt.site/reports`
だけを追加した。直前のremote設定と再読み取りに差異がないことを確認。一時configではauth.additional_redirect_urlsだけを宣言し、CLI diffで同項目だけがdeclared update、他はundeclared remote_onlyであることを確認して既存CLI認証で適用。

追加後の独立read-backが、既存3URL（musclemory/setkeep/setkeep-trainerのlogin-callback）＋承認URL1件と完全一致。他のremote config差分は追加前と一致し、site_url、Google provider/scope/credentialは変更していない。wildcard追加なし。ローカル既存config全体のpushや新規credential作成は行っていない。本人によるGoogleログインE2Eは別途確認が必要。
