# 追加修正・SNS出力・iOS build 20（2026-11-06）

## 保存元と範囲

既存の独立 checkout `/Volumes/PS2000W/SETKEEP/friend-roster-20261102`、branch `fix/friend-roster-updates-20261102`、開始時 HEAD `f74df665d39b7edb9f8d62b291b22d1825ed1392` はクリーンだった。TestFlight 19 の基準 `bbdc531` を保持した既存ブランチを継続した。広告候補、別のジムデータ修正、購入素材、Androidのネイティブ設定は混ぜていない。

GitHub main には以前から大きな履歴差があり、過去のリリース記録も全面統合を禁止している。今回のブランチを保存・pushする範囲とし、mainへのmergeや一般App Store公開は行わない。本番migrationは今回も実行しない。

## 実装

| 項目 | 最終動作 |
| --- | --- |
| Watch休憩タイマー | 「停止」（一時停止して残時間保持）と「完了」（休憩終了・通知取り消し）。iPhoneの既存状態所有・通知サービスを使い、スマホの状態変更通知とWatch最新状態配信を行う。記録全体の完了には拡張しない。 |
| フレンド一覧 | 承認済みフレンドのカード間に12pxの縦余白。従来修正の全員表示・共有記録なし・通信失敗の区別も維持。 |
| 通知 | 通知カテゴリ、いいね通知、コメント通知のカード間に12pxの余白。非公開中の機能を有効化しない。 |
| ほかの接触カード | 利用場所の「その他の場所」を1件ずつのカードへ分け、設備・対応種目・個人設備・メニュー種目並び替えにも縦余白を追加。既に区切りや余白のある画面、全体テーマは維持。 |
| ヒートマップ | 赤の濃淡に関する説明文だけを除く。見出し、筋肉名、マップと集計ロジックは残す。 |
| フレンド記録の統計 | 自分の詳細と同じ白い統計コンポーネントを再利用し、種目数・セット数・総ボリューム・時間の4列。時間が不明なら「—」として4列を保つ。 |
| 同日の複数記録 | 時計の時刻を「記録1/2」（英語はWorkout 1/2）へ変更し、各記録のIDで選択できる。日付、所要時間、いいね等は維持。 |
| 日付ずれ | 共有行の元のISO `client_id` から記録日時を復元して表示。元の時刻も内部に保持し、期間集計を変えない。旧キーが不明な行だけ実timestampのlocal表示に戻す。既存キー、保存データ、反応のリンクは変えない。 |
| 写真ありSNS | ロゴを日付の直上に置き、見えるロゴの幅を実際のフォントで測った日付幅へ揃え、左端も一致。上部23%を空け、下に横棒を加えない。写真のドラッグ位置調整は維持。 |
| 背景なしSNS | 左上ロゴを除き、中央に幅82%・opacity 0.24のロゴを描画。実記録の種目・数値は既存の正確な出力経路を使う。 |

承認画像2枚をLibraryの正式ファイル名・版0で解決し、消費側Macに取得して可読性・Library属性を確認し、両方の実画像を見た。参照画像やLibraryの私的情報をGitへ入れていない。モックの文字崩れは再現していない。

## 日付の原因と確認限界

端末の `WorkoutRecord.toJson()` はローカルDateTimeを `toIso8601String()` で保存する。この形式はUTC以外ではタイムゾーンの付かない文字列になる（[Dart公式](https://api.dart.dev/dart-core/DateTime/toIso8601String.html)）。共有生成はその文字列をdateとして送信し、既存RPCは同じ文字列をclient_idへ保持する一方、performed_atには `::timestamptz` でキャストする。従来の共有表示はperformed_atを `.toLocal()` にしていた。

TCP無効・所有者限定の新規隔離PostgreSQLで、実際の旧キャストを合成値だけで再現した。UTCセッションで `2026-11-06T23:30:00.000` をキャストすると、日本表示は `2026-11-07 08:30:00` になる。一方、明示的な+09:00付きなら元の日付のまま。サーバーは停止済み。

現在の本番セッションのTimeZone設定や、報告された特定記録の内容は取得していない。したがって、この変換経路が翌日化を生むことは再現済みだが、個別の本番記録の原因確定とは区別する。今回の修正はサーバーのタイムゾーンを仮定せず、元の記録キーの日時を表示する。9時間を一律に引く処理、既存行の更新・削除・再発行、公開範囲変更はない。

## 検証

- 最終の固定したアプリソースで通常回帰743件成功、失敗0件（104テストファイル）。既存QA画像を上書きする16個の出力専用preview/visualファイルだけは除外し、一覧をSSDのregression-scope.jsonへ保存した。
- 最終静的解析はNo issues found。Watchの純Swiftプロトコル26件成功。再送、完了済み、別タイマー、古いrevision、再接続相当、バックグラウンド経過後の期限切れ操作拒否を含む。
- 日付・同日複数選択・共有詳細・写真ドラッグ・SNS実データの関連30件成功。通常幅390pxと320px/文字2倍で通知・場所・フレンド詳細を検査し、実フォントの画像を保存・目視確認した。SNS2種類も書き出して確認した。
- 最初の広範実行では旧ロゴ寸法84x52を固定した既存テストが失敗した。承認デザインに合わせて更新した。途中のソース更新中の実行も成功扱いにせず、最終的にソースを固定した一式の743件で成功を確認した。
- Watch実機向けReleaseビルド成功。RunnerのRelease ArchiveとApp Store用IPA exportも成功し、本体・Widget・Watchの全3バンドルが `1.0.0 (20)`、既存配布署名と一致、get-task-allow=false。IPAのdeep/strict署名検証も成功。
- アプリのソースfingerprintがArchive作成時から一致し、素材240点は元の配布元とのSHA-256一致を確認。Archive内の素材も全240点一致。接続設定とtest広告モードは19の既存設定を再利用し、非Git・所有者限定で保持。
- Simulator一覧取得はCoreSimulator接続・ログアクセス制約で失敗したため再試行しなかった。実機ペア通信・実通知・復帰のE2Eは未確認であり、プロトコル試験やビルド成功をその代わりとは主張しない。Android/Galaxyへのインストール・更新は行っていない。

## 配布成果と引継ぎ

- Archive: `/Volumes/PS2000W/SETKEEP/feedback-20261106-validation/SETKEEP-1.0.0-20.xcarchive`
- IPA: `/Volumes/PS2000W/SETKEEP/feedback-20261106-validation/export-20/SETKEEP.ipa`
- IPA SHA-256: `c087ab6b51d529aa4b77b0938bac9e41aee40910ac4e0af26de073577fc0d8b6`
- IPAサイズ: 494,342,906 bytes。
- 証拠: 同validationフォルダの `archive-verification.json`、`ipa-verification.json`、`app-source-fingerprint.json`、`regression-frozen-result.json`、`date-cast-repro/result.csv`、`ui/`。ログは私的な接続・配布情報を含む可能性があるためGitへ入れない。

このタスクはアップロードを一度も開始していない。親が指定した配布担当だけが、直前に既存TestFlight一覧で20未受信を確認し、既存のxcodebuild exportArchive/upload手順で上記Archiveを送る。19で使ったUploadOptions（destination=upload、manageAppVersionAndBuildNumber=false、method=app-store-connect、signingStyle=automatic、uploadSymbols=false、既存Team）を再利用できる。allowProvisioningUpdates/新規認証情報/新契約は含めない。応答が不明なら先に受信状態を読み戻し、重複アップロードしない。

Apple処理完了、暗号化等の必要事項、既存「SETKEEP 内部検証」「SETKEEP 日本向け外部テスト」の利用可能状態を配布担当が確認するまで、TestFlight反映完了とはしない。暗号化申告は本タスク未操作で、Info.plistにも新しい申告値を追加していない。19の承認済み申告の履歴は既存の `bulk_exercise_reports_2026-11-01.md` にある。新規・未確認の質問は回答しない。

前回の更新順DB候補 `20261102090000_friend_workout_updates.sql` はSHA-256 `c7445b2e612d57a6b34fd955541b00039e3ea17dea617f0133e529a9d5890496` のままで、今回も適用・再試行していない。前回は実行前拒否・未適用読み戻し済み。新UIはそのDBがない場合も全員表示するが、正確な共有更新順は有効にならない。この制限は今回のUI修正完了とは別である。
