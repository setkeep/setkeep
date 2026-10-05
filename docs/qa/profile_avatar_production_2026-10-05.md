# プロフィール画像 本番反映QA — 2026-10-05

対象は通常repo `muscle_memory`、ブランチ `fix/friends-ux-local-integration`。
既存UI commit `cebd5982fd09e1ed79d94e5ed552e0d6e6fe43b8` を親に持つローカルcommitへ
今回のプロフィール画像差分だけ整理する。
承認済み実装は `a48c3a23632f1ec19fb1d46a4cb2522bbe5f3266`。

## 反映済み

- `20261004140000_friends_profile_invites.sql` と
  `20261004220000_friend_avatar_account_cleanup.sql` だけを既存SETKEEP本番へ原文一致で適用。
  SQL21・保持方針・cronは適用していない。
- delete-account Edge version 3、ACTIVE、verify_jwt=true。既存環境のみ使用し、
  他Edge・資格情報は変更していない。
- 反映中の一時停止policyを解除。friend-avatarsは非公開、PNG限定512KiB。
  元14の9 policyと22のrestrictive guard、Auth削除ガードを保持。
- SQL14は `9d7cf3f` ですでにGit追跡済み。今回の差分で重複追加や原文修正はしていない。

## 検証済み

- 本番の履歴に加わったのは14/22だけ。保存した原文MD5と11関数本体が一致。
  既存15件数・無関係な関数定義は前後で一致。
- 一時claimsの非実在UUIDで本人/他人パスの読取・書込を拒否。
  匿名と認証ロールのcleanup表への直接読取、service専用RPCの実行を拒否。
  全体をROLLBACKし、Auth/Storage fixtureは作成していない。
- Edgeの資格情報なし/無効Bearerは401。認証済みの実退会呼出しはしていない。
- 隔離DBで画像RLS32、新ライフサイクル33、既存SQL9本181、rollback6、
  二セッションの先行書込待機/ゲート後拒否を検証済み。
- Edge21テスト、通常repo認証サービスの対象11テストとDart解析成功。
- 既存9変更・UI commit・署名設定を保護。Git indexに非対象変更を含めず、
  今回のprofile source/doc/testだけをcommitする。
  Watch QA追記など他の保留差分は保持。

## 既存UIと旧インストール版

画像設定UIは `9d7cf3f` に導入済み。マイページの `_ProfileNameCard._load` は
ログイン中のprofileを取得し、`avatar_path` キーがある場合にタップを有効化する。
`FriendsRepository.setAvatar` がPNGを本人prefixへ保存し、プロフィールを更新する。
この実装を含む旧インストール版ならbackend反映後の再取得で操作可能になる構成。

IndexedStackに保持されたUIはタブ切替だけで再取得しない場合があるため、
反映前から起動中ならアプリを再起動する。プロフィール行が未作成なら
ホームのensureProfile実行後に再取得する。`30ce889` 以前には画像設定UI/setAvatarがなく、
アプリ更新が必要。端末のインストール済み版の元commitや実機操作は未確認。
今回の詳しい退会失敗案内を配布するには新しいアプリ版が必要。

## 未確認・未実施

実Storage byteアップロード/削除とowner metadata、実Auth退会、実機の写真選択/
共有範囲変更/キャッシュ/通信断/再試行は未確認。合成Authユーザー作成/削除、
実ユーザー/画像削除、新しい永続資格情報、本番の追加変更、push/配布は実施していない。
署名・ビルドは別作業と直列調整し、このプロフィールcommit整理中は
native/full Flutter buildを実行しない。

作業証跡は `task/avatar-production-evidence/deployment-result.json`、
`final-verification.json`、`normal-integration-result.json`、commit後の `commit-result.json`。
ローカルの個人データ・秘密値はこの文書やcommitに含めない。
