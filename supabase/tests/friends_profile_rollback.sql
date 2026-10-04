begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',label; end if; raise notice 'PASS: %',label; end $$;
insert into auth.users(id) values('81000000-0000-0000-0000-000000000001');
insert into public.friend_profiles(user_id,display_name,visibility,avatar_path)
values('81000000-0000-0000-0000-000000000001','Rollback fixture','private','81000000-0000-0000-0000-000000000001/1.png');
insert into storage.objects(bucket_id,name) values('friend-avatars','81000000-0000-0000-0000-000000000001/1.png');
insert into storage.buckets(id,name,public) values('fixture-rollback-other','fixture-rollback-other',false);
insert into storage.objects(bucket_id,name) values('fixture-rollback-other','unrelated.png');
create policy fixture_rollback_broad on storage.objects for select to anon,authenticated using(true);
\ir ../rollback/20261004140000_friends_profile_invites_access_stop.sql
select pg_temp.ok(not has_function_privilege('authenticated','public.lookup_friend_invite(uuid)','EXECUTE'),'rollback disables preview');
select pg_temp.ok(not has_function_privilege('authenticated','public.latest_friend_workouts()','EXECUTE'),'rollback disables new feed');
select pg_temp.ok(not has_function_privilege('authenticated','public.list_friend_connections_with_avatar()','EXECUTE'),'rollback disables new connections RPC');
select pg_temp.ok(has_function_privilege('authenticated','public.request_friend(uuid)','EXECUTE') and has_function_privilege('authenticated','public.list_friend_connections()','EXECUTE'),'rollback preserves original MVP RPC permissions');
select pg_temp.ok(has_table_privilege('authenticated','public.friend_workouts','SELECT'),'rollback preserves original workout permission');
set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000001',true);
select pg_temp.ok((select count(*)=0 from storage.objects where bucket_id='friend-avatars'),'rollback disables owner avatar access despite broad grant');
select pg_temp.ok((select count(*)=1 from storage.objects where bucket_id='fixture-rollback-other'),'rollback preserves other bucket access');
select pg_temp.ok((select visibility='private' and avatar_path is not null from public.friend_profiles where user_id=auth.uid()),'rollback preserves privacy and photo reference');
set local role anon;
select pg_temp.ok((select count(*)=0 from storage.objects where bucket_id='friend-avatars'),'rollback denies anonymous photo access');
reset role;
select pg_temp.ok((select count(*)=1 from storage.objects where bucket_id='friend-avatars'),'rollback preserves stored objects');
rollback;
