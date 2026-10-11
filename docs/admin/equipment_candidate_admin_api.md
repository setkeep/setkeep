# 設備報告の自動反映と管理者操作 API

ローカルmigration `20261010230000_equipment_candidate_admin_actions.sql` の契約。
**2026-10-10に本人承認後、本番適用・読み戻し検証済み。** 既存の自動判定・閾値・全体設定を維持する。D1の進捗1行とは分離し、報告・設備・正式処理履歴はSupabaseを正本とする。

## 認証と取得

Siteは本人のSupabaseログインJWTを使う。Siteが本人限定でもDB認可の代わりにはならない。service鍵は不要・クライアントへ渡さない。全APIは `is_report_admin()` による `app_admins` 登録確認が必要。未認証・非管理者は42501。

- `list_admin_equipment_candidates(page_offset integer=0) -> {rows: [...]}`: 最新順50件、候補単位。店舗/設備名、報告件数（user_report根拠数）、ユニーク支持報告者数、初回/最終日時、状態、保留情報、下記snapshot、適用情報。件数は投票数と異なる。未処理/処理済み・保留をUIで表示。大量一覧の全体集計・検索APIは今後の別拡張。
- `get_admin_equipment_candidate(target_id uuid, selected_equipment_id text=null) -> snapshot`: 個別操作前に取得。追加報告では対応させる既存設備IDを選んで、その店舗設備のsnapshotを取り直す。
- 既存 `list_admin_reports` は個別報告一覧・状態別件数に利用可能。台数列なし。候補の `proposed_value` に台数等がある。
- `gym_equipment_review_operations`: 管理者のみSELECT。候補IDでfilterしcreated_at順にページ取得。actor_id（操作担当）、action、理由を含むrequest、操作後snapshot/result、日時。利用者の報告者IDを画面へ出す必要はない。
- `gym_auto_applications`, `gym_auto_decisions`: 既存管理者RLSでSELECT可。変更前後や自動判定履歴。`gym_equipment_changes` の生ログはクライアント参照不可のまま。

snapshot主要項目: `candidate_id,store_id,equipment_id,selected_equipment_id,change_type,proposed_value,status,review_version,admin_held,admin_hold_note,first_seen_at,last_seen_at,support_score,oppose_score,unique_reporters,master_present,master_updated_at,current_data`。`current_data` はsource JSONを除く店舗設備行。proposed_valueの報告commentも除外する。報告者ID・報告コメントを新取得RPCは返さない。`review_version` は候補更新ごとに増加し、再報告も版を変える。

## 処理RPC

```
review_gym_equipment_candidate(
  target_id uuid,
  action text,                    -- apply / reject / hold / release / rollback
  expected_status text,
  expected_version bigint,
  operation_id uuid,               -- 1論理操作ごとに新しいUUID
  note text,                      -- 全操作で理由必須、trim後1〜4000文字
  expected_master_present boolean,
  expected_master_updated_at timestamptz,
  selected_equipment_id text = null,
  mapping_confirmed boolean = false
) -> 操作後snapshot
```

`expected_status`, `expected_version`, `expected_master_present`, `expected_master_updated_at` は直前snapshotをそのまま渡す。設備行なしはfalse/null。操作送信の通信結果が不明なら、**同一引数・同一operation_id**で再送する。成功済みなら保存済み結果を返し、再処理しない。同じIDで担当/引数を変更すると22023。失敗操作は保存されずtransaction全体がrollbackされる。

- `apply`: `added/removed/not_present/quantity_changed/temporarily_unavailable/available_again` のみ。候補は未解決・保留解除済みが必要。総台数・一部利用不可数はDBで再検証する。名称訂正/otherは設備マスター別確認が必要で、このRPCでは採用不可。
- `added`: `selected_equipment_id` の明示と `mapping_confirmed=true` を必須にする。既存の `equipment` にある `needs_review=false` のIDだけ受理し、新マスターは作らない。自動照合された候補でも、手動採用時には対応確認が必要。
- `not_present`: 本人採用時のみ店舗設備を `presence_status=removed, available=false` にする。候補種別はnot_presentのまま、適用履歴のchange_typeはremoved。
- `reject`: 候補を却下し、関連する未確認/確認中の報告も却下。理由を記録。解決後の新報告は新候補として扱われ得る。
- `hold`: 候補の `admin_held=true` を設定。候補statusは維持し、既存のopen集約キーも維持する。同内容の再報告/公式根拠/トレーニング確認は同候補に入り、保留を解除しない。保留中は再評価・自動適用をスキップする。票数表示は保留時点から更新されず、根拠・報告件数は増える。
- `release`: 明示解除して通常の再評価・適用を再開。**条件を満たせば解除RPC内で自動反映される**。Siteは解除の確認文にこれを表示する。
- `rollback`: auto_applied/admin_appliedの両方。適用後のマスターが適用時after_dataと完全一致する場合だけ復元。別更新があれば拒否。追加で新設した店舗設備行なら削除、既存行なら出典を含め正確に戻す。報告は既存の差し戻し仕様に従いappliedのまま、候補と履歴でrolled_backを示す。追加候補のrollbackで別設備IDを指定してはならない。

採用は設備更新、関連報告のapplied、適用前後履歴、候補admin_applied、操作担当/理由の保存を同transactionで行う。自動反映は従来どおりauto_applied。

## 競合と権限差分

全設備workflowは最初に共通transaction advisory lockを取り、その後に既存の集約キー/候補/設備ロックを取得する。粗い共通ロックで別候補が同じ設備へ反映する場合やtrigger再入時の順序逆転を避ける。ロックは短いDBtransactionのみ保持し、クライアント確認待ちはtransaction外に置く。大量処理時の性能負荷は本番投入前に評価する。

設備報告の直接UPDATE(status,admin_note)をauthenticatedから外し、既存 `update_admin_report` を管理者検証付きSECURITY DEFINER入口へ変更する。既存Flutterは既にRPC経由。報告行ロック前にworkflowロックを取ることで手動採用とのdeadlockを防ぐ。一般ユーザーINSERT/自分のSELECT、既存管理者SELECTのRLSは維持する。内部旧関数はPUBLIC/anon/authenticatedから実行不可。新規管理RPC3本・補助関数2本・新規履歴tableはservice_roleの既定付与を明示撤回。既存自動処理入口のservice_role権限とschema既定ACLは維持する。

Site表示: 40001は「最新情報を読み直してください」、22023は入力/対応確認/保留状態エラー、42501は権限エラー。既存rollbackのmaster不一致はP0001で拒否されるため再読込して別更新を確認。成功時は返却snapshotに加え一覧・履歴を再取得する。

## ローカル検証

PostgreSQL 17のinitdb/pg_ctl/psql、Python3を使う。

```
python3 tool/equipment_review/run_local_qa.py
```

runnerは毎回一時ディレクトリにsocket専用DBを新設し、合成auth/usersと参照seedのFKスタブで既存設備migrationを再現。scheduler migration031は外部拡張依存のため対象外。Supabase CLI、本番接続、環境credentialを使わず、終了時にDB停止・一時ディレクトリ削除。

検証: 新migration初回適用、管理者/非管理者認可・監査RLS、直接UPDATE拒否、採用/見送り/保留/解除、冪等性、版/master競合、設備ID対応確認、台数制約とtransaction rollback、手動適用者、admin rollbackと後続master変更拒否、保留中再報告・解除後自動再開。既存SQL回帰8本と複数接続競合5ケース。

対象migrationの本番適用は本人承認後に完了。app_admins登録、Siteの本人認証・credential設定、実在報告処理、公開/pushは行っていない。検証証跡は `docs/qa/equipment_admin_production_2026-10-10.md` を参照。
