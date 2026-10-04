-- Not a migration; run inside a transaction only after reverting the new app.
-- Preserve profiles, photos, existing friends/workouts, and other buckets.
revoke execute on function public.lookup_friend_invite(uuid),public.latest_friend_workouts(),public.list_friend_connections_with_avatar() from authenticated;
drop policy if exists friend_avatar_disabled on storage.objects;
create policy friend_avatar_disabled on storage.objects as restrictive for all to anon,authenticated
using(bucket_id<>'friend-avatars') with check(bucket_id<>'friend-avatars');
