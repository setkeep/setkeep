# 本番事前確認・復旧用バックアップの実行記録

2026-11-02 13:35 UTC 時点。これは初回準備記録の後に追加された実状態であり、未実行と記した初回記録とは時点が異なる。

ユーザーの具体的なサーバー変更・バックアップ承認は親から受領した。ただし、対象版の本番実行ボタンは自動承認審査で拒否された。拒否後は再試行も別経路適用も行っていない。読み取り専用SQLで再確認した結果、対象migration履歴、新RPC、追加2列はいずれも未存在だった。13:35:04 UTCの読み戻しで本番未適用が確定している。

## 完了

- 配布中19の接続先と一致する既存Supabase管理画面を使用し、PG17.6、関連migration履歴、既存RLS/ACL/関数、対象2表のサイズ・ロックを読み取り専用で確認した。対象版は未適用、対象ロックは観測時0。対象表は約80KiBと200KiBで、候補は短いDDL枠を前提にできる規模だが、将来のロック競合を保証するものではない。
- 既存の5フレンド表のRLSは有効で、friend_workoutsのauthenticated権限はSELECTのみ。新RPCはその同じRLSで見える行だけを返すinvokerとして準備されている。既存同期・公開・プロフィール・接続関数は変更していない。
- 既存管理バックアップ欄は「No backups」。新契約・プラン変更は行わず、承認された復旧用途として対象5表（friend_profiles / friend_connections / friend_workouts / friend_likes / friend_comments）の整合する単一SELECTスナップショットを取得した。Auth利用者表や他のトレーニング表・ストレージ実体は含まないため、全DB/PITRバックアップではない。
- バックアップ取得時刻は2026-11-02 13:20:25.504481 UTC。CSVファイルSHA-256は c924637304b3b25e7d97e48a6ee6e764173206160fe71858ebb4511ac9703b18。サーバー生成payloadのSHA-256、5表の構造、型、主キー重複、参照整合性をローカルのプログラムで検証した。実レコードをチャット・Git・Libraryへ転記していない。
- 本番データとcatalog出力はワークスペース内の非Gitディレクトリ private-production-backup に所有者限定（0700/0600）で保管。元のCSVダウンロードもユーザーの所有者限定Downloadsに存在する。FileVault状態は確認できず、暗号化済みとは主張しない。新しい暗号化鍵や資格情報は作成していない。
- 対象1件だけを実行する生成SQLをワークスペースvalidationに用意し、hashを読み戻した。原本migrationのSHA-256は c7445b2e612d57a6b34fd955541b00039e3ea17dea617f0133e529a9d5890496 のまま。生成適用SQLのSHA-256は 8a5e62ef42d8cddd7f62a22bfe58eb265408bf99d1688f8ddd8c963738f33448。原本MD5は82700c455b56b970c90ed33b16618f6cで、対象版の履歴へ原本全文を保存する構成。

## 停止条件

本番の実行ボタンの自動審査理由は次のとおり：

> Clicking Run would execute a production schema migration with persistent database changes, but no trusted user approval for this exact production execution is present.

実行前に拒否された。対象はSupabaseプロジェクト meyrtimwibqonozsewbt に対する 20261102090000 の本番DDL実行で、同じ操作を再試行していない。入力済みDDLは読み取り専用の未適用確認SQLへ置き換えた。古い承認カードの有効性は不明であり、承認済みとは推定していない。再開には、この具体的な本番実行を認める正規の承認審査が必要。旧CLIの ~/.supabase/telemetry.json.tmp.* EPERM は別の停止条件として維持しており、そのCLI経路は再実行していない。

App Store Connectは既存Apple Accountのログイン画面となっている。通常ログインを進めたが、既存保存情報でサインインは完了しなかった。新しい資格情報は発行しておらず、ユーザーによるサインイン完了を依頼した。リモートの現在ビルド・空き番号は未確認のため、新しい署名Archiveもアップロードもまだ開始していない。有効な署名IDと本体/Widget/Watchの3プロファイル、baseline19のtest広告設定の利用可能性は既存準備結果のとおり。

## 再開の順序

1. 本番実行について正規承認が確認できた後も、最初に履歴・列・RPCを読み戻して重複を防ぐ。今回の原本だけを2秒lock_timeout/60秒statement_timeoutの1transactionで適用する。全pending migrationのpushは行わない。
2. 既存RLS/ACL/旧関数と保存catalogを比較し、対象追加と正確な履歴hash、API schema cache反映を確認する。通常セッションの実API正テストができなければ、その未確認を区別する。匿名拒否や隔離93アサーションだけを実アカウント検証の代替としない。
3. ログイン後のApp Store Connect実状態から次ビルド番号を確定し、baseline19の接続設定とtest広告方針でフレンド変更だけを署名する。既存グループだけへ配布し、処理・グループ状態を読み戻す。一般公開・Android配布は行わない。

今回の追加作業は運用記録のみ。アプリ実装、migration、rollback、テスト、既存ビルド成果は変更していない。Macの既存caffeinateは継続稼働を確認した。
