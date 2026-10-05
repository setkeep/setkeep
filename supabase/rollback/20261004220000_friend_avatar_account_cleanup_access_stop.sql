-- Run in a reviewed transaction after stopping upload UI and delete-account.
-- Preserve existing photos, account records, cleanup gates and Auth safeguards.
begin;
drop policy if exists friend_avatar_lifecycle_disabled on storage.objects;
create policy friend_avatar_lifecycle_disabled on storage.objects as restrictive for all to anon,authenticated
 using(bucket_id<>'friend-avatars') with check(bucket_id<>'friend-avatars');
revoke execute on function public.account_avatar_cleanup_begin(uuid,text,uuid),
 public.account_avatar_cleanup_check(uuid,text,uuid),public.account_avatar_cleanup_confirm(uuid,text,uuid),
 public.account_avatar_cleanup_release(uuid,text,uuid) from service_role;
commit;
