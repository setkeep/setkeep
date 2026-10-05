# フレンド更新の適用・停止・再開

これらは本番未適用のローカル準備です。本番での実行は対象・変更内容の承認後に行います。接続情報やユーザーデータを出力しない既存の管理接続を使い、各SQLは `ON_ERROR_STOP=1` で実行してください。

初回適用は `verification/friend_updates_preflight.sql`、`migrations/20261005100000_friend_mutual_sharing_invites.sql`、`migrations/20261005110000_friend_comment_idempotency.sql`、`verification/friend_updates_postflight.sql` の順です。前提は既存MVP、写真SQL14、記録削除SQL20、写真削除SQL22です。事前確認には組み込みSHA256の存在確認を含みます。migrationで既存プロフィールの公開範囲を一括変更しません。新しい共有権限は各本人の `privacy-1.2` 同意後にのみ更新します。

問題発生時は新アプリの配布を停止し、`rollback/20261005100000_friend_updates_access_stop.sql` を実行してから `verification/friend_updates_stopped_postflight.sql` を実行します。新しいコード発行、v2申請、共有同意更新、冪等コメント送信の4つの実行権限だけを止めます。テーブルや列を削除せず、コード、承認済み共有、本人の同意状態、コメント、削除済み送信receiptを保持します。既存のUUID申請・承認、直接コメントINSERT、記録/コメント/いいねの読み取りは継続します。新UIでは停止したRPCに権限エラーが返るため、配布停止も必要です。既存の公開範囲を自動でprivateへ戻す処理はありません。

修正確認と再開承認後は `rollback/20261005100000_friend_updates_resume.sql` を実行し、`verification/friend_updates_postflight.sql` を再実行します。復元は4つの `GRANT EXECUTE ... TO authenticated` だけです。CREATEを含むmigrationを再適用しません。再開SQLも本人の同意や公開範囲を変更しません。

停止後確認は実行権限と既存APIの保持を検証します。実データを出力せずに全ユーザーの停止前後の一致を証明する操作は含みません。合成UTF-8 DBでは停止前後のプロフィール、コード、コメント、receiptの一致と旧INSERTの継続を確認済みです。
