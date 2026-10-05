# SETKEEP フレンド機能・2026-10-05 ローカル実装

通常チェックアウト: `/Users/macintosh/Documents/Codex/muscle_memory`、remote `setkeep/setkeep`、開始HEAD `2cb7b9abcde918bac7337b951f6f253fa783bc1b`。このフレンド更新バッチのpush・merge・本番SQL・公開・端末インストールは未実施。既存のbuild 11の暗号化申告・内部検証グループへの追加は別作業で完了しており、このローカル更新の配布を示さない。

## 実装

- 承認された最終画像に合わせ、上部の本人プロフィールと公開範囲カードを除去。ブランド色 #C7F36B の招待カード、コード入力、申請・フレンド一覧、解除確認へ整理。
- サーバー上の登録名を読み込み時に空/古い端末名で上書きしない。明示的編集とアカウントごとの名前キャッシュを分離。
- 短いコードは紛らわしい文字を除いた8文字、暗号学的乱数・衝突再試行・ユーザー別回数制限。旧UUIDを継続。無効・本人コード・制限超過は共通応答、無効試行も制限に計上。
- 本人の privacy-1.2 同意後だけ、本人の共有を承認済みフレンドへ変更。既存の非公開設定をSQLで一括変更しない。未承認者・一般第三者への公開なし。
- HTTPS招待の厳密な解析、ログインを跨ぐ保存、確認表示時には消費しない保持、成功した申請時だけ消費。同じ招待の再受信と並行受信にも対応。
- 履歴の詳細、フレンドの詳細、通知から既存の同じ記録ID・コメントスレッドを開く。閲覧のために記録を作成・公開しない。
- コメントは相手左・本人右、アバター・許可された登録名・日時・吹き出し、140 Unicode code point、改行・キーボード・safe area・空状態・失敗時の入力保持・連打防止・本人削除。アカウント変更、解除、削除された通知で表示を停止。
- コメント送信は本人・記録・本文に紐づくUUID操作IDを使用。保存後に応答を失っても同じ画面・同じ下書きの再送は元のコメントを返し、削除後の再送では復活させない。旧スキーマでは新しい送信画面を準備中にし、旧INSERTへの暗黙の退避はしない。既存アプリ用APIと閲覧・本人削除は保持。
- いいねはハート操作/件数を維持し、許可された小さなアバターだけ最大4つ表示。名前表示・一覧モーダル・DMなし。
- 記録の公開/削除同期と写真/名前の同時更新は既存ソースを保持。ホームのセット等は値ごとのWrapで読みやすく表示。

## 検証

- 通常チェックアウトと隔離候補の flutter analyze: No issues found。
- ローカルSQL: **162項目成功**（共有/招待を含む既存140、コメント冪等性22）。匿名・他人・非公開・申請中・解除済みの読取/書込拒否、衝突、旧コード、回数制限、本人だけの同意移行、写真削除中/第三者の抑制、操作IDの本文/スレッド変更拒否を確認。
- 同時発行12リクエストは同じ1コード。招待40並行試行のうち20件のみ許可。コメント12同時再送は同じIDの1コメント。ロック待ち中の解除・非公開化後は、再送の読取/書込を拒否。
- 隔離したフレンド差分候補: **Flutter 527件成功**。通常チェックアウトも **Flutter 531件成功**（2分46秒）。並行実行時には既存の休憩タイマー表示1件が失敗したが、単独再確認5件および全体の最終再実行が成功。既存のタイマー実装とテストは変更していない。通常と隔離の4件の差は別作業の既存広告/スプラッシュ追加テストによる。
- TRAINER: **24件成功**、analyze指摘なし。既存のTRAINERテスト変更を保持。
- iOS: 隔離候補で `flutter build ios --debug --no-codesign --no-pub` 成功。Watchアプリと休憩ウィジェットを含む。署名なしであり配布用ビルドではない。
- Android: 隔離候補で `flutter build apk --debug --no-pub` 成功、com.setkeep.app、debug署名と招待intent filterを確認。本番のSupabase定義や署名propertiesはコピーしていない。
- 非破壊のアクセス停止/再開SQLを合成データで実行し、プロフィール・同意・公開範囲・短コード・コメント・削除後の再送防止記録が変わらないことを確認。既存INSERT権限と閲覧経路を保持。
- 架空データで日本語390px画面を画素確認。320px/文字倍率2倍とキーボード領域も確認。コメント専用18件、失われた応答/旧スキーマのrepositoryテスト2件を含む。
- スプラッシュ、既存広告変更、通常のXcode署名/Watch設定、その他の既存変更を開始時ハッシュ/該当ソースと照合。元の署名済み成果物を含む9対象も不変。

## 分離してレビューできる成果物

`friend-release-readiness/friends-only.patch` と `files.json` は HEAD `2cb7b9abcde918bac7337b951f6f253fa783bc1b` に対する今回の差分とSHA256一覧。同じmain.dart内にある開始時の別広告hunkを除外し、通常チェックアウトの元変更は保持した。スプラッシュ・広告・Watch署名・既存TRAINERテスト・他作業のQAは含めない。

関連付けの `invite-link-work/native-association/ios-association.patch` と `android-association.patch` は別成果物で、隔離候補のみに適用してビルド。現在の通常チェックアウトにも適用可能で、Team/署名/Watch/ウィジェット設定を保持することを確認。通常のネイティブ設定は未変更。

## 本番反映に必要な承認・未確認

1. read-only preflightの後、`20261005100000_friend_mutual_sharing_invites.sql`、続いて `20261005110000_friend_comment_idempotency.sql` の追加適用。SQL14・20・22と既存MVPが前提。既存プロフィール・トレーニングを移行で変更しない。新アプリの配布前にpostflightを実行する。前回のプロフィール画像SQLの承認はこの2件の適用を含まない。
2. 切戻しは `supabase/rollback/20261005100000_friend_updates_access_stop.sql` で新規4書込入口だけを停止。追加テーブル/既存データを削除しない。stopped postflightで確認し、別途許可されたresume SQLで再開。migrationの再実行で切戻さない。
3. `invite-link-work/web-staging` の招待ページ・privacy1.2の公開/HTTP検証。招待された友達をApp Store Connect内部スタッフ検証へ誘導せず、架空のストア/TestFlight URLも掲載しない。インストール後は元の招待URLへ戻る案内。現在のアプリのHTTPS定義は未設定で準備中を表示する。
4. 公開署名済み成果物でiOSアプリ識別子 `58CC3T56JQ.com.setkeep.app` を確認し、具体的なAASA/entitlementsを準備。ただし既存署名・プロファイルにAssociated Domainsはなく、Apple外部権限登録と更新プロファイルが必要。現在の有効なTeamを維持し、HEADの古いTeamへ戻さない。
5. Android debugの証明書は確認済み。本番配布用のcom.setkeep.app証明書fingerprintは未確認。旧release APKは別packageのため使用しない。debug-only assetlinksやplaceholderの本番公開は不可。
6. 正しい本番定義・署名・新しいbuild番号を使う配布ビルド、関連付けの実URL応答、iPhone/Android実機でログイン・リンク・認可・Watch連携の確認は未実施。commit/push/端末インストールは別途承認対象。

既に本番で上書きされた登録名は本人の入力内容を安全に復元できない場合があるため、自動復元を行わない。本人の明示保存で修正可能。コメントの操作ID保持は同じ画面内で同じ下書きを再送する期間に限定し、画面離脱/再起動を跨いだ下書き保存や同一本文の永久重複禁止は行わない。既存ソースに通報機能はなかったため、架空の通報ボタン/モデレーション機能は追加していない。

証拠: `friend-release-readiness` の解析/テスト/差分、`friend-backend-batch/idempotency/result.json`、`native-readiness/summary.json`、`invite-link-work/verification.json` とpublic association検証JSON。
