# サイト由来設備の本番掲載停止 — 2026-10-11

本人の「本番変更承認します」に基づき、限定migration `20261011000100_equipment_source_withdrawal.sql` を適用した。Git push・アプリ配布・新認証・管理者追加・credential作成は実施していない。

Migration SHA-256: `192a752c60de8b2888c2514ff8574d61ab5816dd13ebf356834a6cd50b58de1f`。

## 適用・直前照合

直前の2回のread-only照合で、対象4,600関係、専用マスター689、対象店舗1,533、開いている対象候補0、隔離schema/migration/community ID未作成を確認。既存関数・ACL・RLS・既定ACL・保護対象データの集約hashも一致した。

既存Supabase CLI接続を使用し、対象migrationだけを実行。全migrationのpushは行わない。単一トランザクション内でworkflow/table lock、5秒lock timeout、60秒statement timeout、直前再照合、移行、適用後assertion、schema_migrations履歴登録を行った。最初の適用は検証SQLの変数名衝突でcommit前に停止。別読み取りで全baseline/schema/ACLが一致して全体rollbackを確認し、migration本体は変えず検証SQLの変数名だけ修正して再実行した。2回目はcommit成功、別read-only接続でも検証成功。

## 本番読み戻し結果

| 項目 | 結果 |
|---|---:|
| 元関係の非公開隔離 | 4,600 |
| 専用マスターの元JSON保管・RLS遮断 | 689 |
| 隔離対象の旧候補 | 0 |
| 公開関係 | 9,515 → 4,915 |
| 元設備本体 | 2,606行をすべて保持 |
| 独立community設備追加 | 16 |
| 設備本体合計 | 2,622 |
| anon/authenticatedから見える設備本体 | 1,933 |
| トレーニング確認ルール | 105 → 209 |

隔離4,600行のJSON hashは適用前の対象関係と一致。専用689行のJSON hashも元マスターと一致。公開に残る他店舗関係4,915行、既存設備2,606行、店舗2,699行の全行hashが一致。設備報告は新規導出列を除いてhash一致、利用者登録・既存トレーニング確認・app_admins・自動ルールもhash一致。実在報告の採用は行っていない。新規店舗在庫は一括作成しない。

既存関数定義は承認された training_equipment_options 以外すべてhash一致。既存関数/テーブルACL・既存RLS・既定ACLも一致。隔離schema/tableにanon/authenticated/service_roleの権限なし。新規5関数にservice_role EXECUTEなし。公開判定boolean helper2個だけanon/authenticatedにEXECUTE、内部trigger3個は呼出し権限なし。on_site_confirmed列へのauthenticated INSERT権限なし。DB所有者/既存強権限管理者は復元操作可能。service_roleの既存public権限そのものは変更していない。

anonとauthenticatedの両ロールで直接SELECTと既存RPCを確認した。専用689設備は直接SELECT/設備参照RPCから見えず、対象店舗の旧設備関係は0。各対象チェーン/新潟赤道の代表店舗の詳細RPC・種目証拠RPCも旧設備を返さない。店舗一覧2,699行は保持。

## 復元可能性の検証

READ ONLYでは一時テーブルCREATEが許可されなかったため、隔離JSON4,600行を `jsonb_populate_record` で現行店舗設備の行型へ読み取り変換した。変換後の全行hashが適用前と一致、店舗/設備の参照先がすべて存在し、現在の公開関係と主キー衝突なしを確認。公開へ再挿入はしていない。

実際の復元はDB所有者が新しい利用者在庫との衝突を再確認し、ガード/RLS/対象候補選択を戻したうえで保管JSONから復元する。旧サイトデータで新しい利用者情報を上書きしない。実公開への復元操作・アプリ側コードの復帰は未実施。

## 旧アプリと未配布変更

本番オンラインの既存RPC契約/認証は維持。更新取得後は対象サイト設備が一覧・店舗種目判定から外れる。既存アプリの保存後トレーニング確認は同じRPCで独立community候補を受け取り、3人等の従来条件で自動公開できる。古い確認・サイト由来IDからの再公開はガードで遮断。

旧アプリの手動added報告は現地確認宣言を付けないため、対象店舗でサーバーに拒否される。補助の選択式・現地確認チェック、候補の事前選択/画像/複数選択、指定3表示撤去、v2キャッシュ移行はローカルコードのみで未配布。旧アプリではこれらの新UIはまだ表示されない。

旧v1キャッシュはサーバーから消せない。旧アプリが取得前にキャッシュを表示する一時表示、通信失敗時/オフライン時の古い設備表示は残り得る。更新版ではv1を読まず、出典と対象IDによるクライアント側除外も検証済み。配布には別途指示が必要。

完全無操作の推測送信は追加しておらず、トレーニング保存後の本人の明示確認を維持。自由種目・自重/ダンベルから特定マシンを推測しない。既存確認済み候補への再質問は従来のknown判定で抑える。

## ローカル検証の根拠

移行＋既存9SQL回帰＋隔離/ACL検証、5競合検証、画面/保存35テスト、両OSプレビュー2テスト、対象静的解析・diff check成功。実機インストール/配布ビルドは未実施。

## 作業完了後のスリープ防止解除

本人の追加指示によりPID1023を再確認。現在ユーザー所有の `/usr/bin/caffeinate -dis` で、指定された3assertion（PreventUserIdleSystemSleep / PreventUserIdleDisplaySleep / PreventSystemSleep）を持っていた。終了直前に所有/コマンドを再照合して対象だけSIGTERM終了。`pmset -g assertions` でPIDと3つのassertion IDが消えたことを確認した。恒久電源設定や他のプロセスは変更していない。
