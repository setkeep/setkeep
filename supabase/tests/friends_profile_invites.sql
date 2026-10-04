begin;
-- Model a pre-existing broad Storage grant. Friend guards must still deny
-- unauthorized avatar access while allowing existing non-friend buckets.
create policy fixture_existing_select on storage.objects for select to anon,authenticated using(true);
create policy fixture_existing_insert on storage.objects for insert to anon,authenticated with check(true);
create policy fixture_existing_update on storage.objects for update to anon,authenticated using(true) with check(true);
create policy fixture_existing_delete on storage.objects for delete to anon,authenticated using(true);
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.denied(q text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then return true; end $$;
insert into auth.users(id) values
 ('61000000-0000-0000-0000-000000000001'),('61000000-0000-0000-0000-000000000002'),
 ('61000000-0000-0000-0000-000000000003'),('61000000-0000-0000-0000-000000000004');
insert into public.friend_profiles(user_id,display_name,invite_code) values
 ('61000000-0000-0000-0000-000000000001','A','62000000-0000-0000-0000-000000000001'),
 ('61000000-0000-0000-0000-000000000002','B','62000000-0000-0000-0000-000000000002'),
 ('61000000-0000-0000-0000-000000000003','C','62000000-0000-0000-0000-000000000003'),
 ('61000000-0000-0000-0000-000000000004','D','62000000-0000-0000-0000-000000000004');
set local role authenticated;
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000001',true);
select pg_temp.ok((select visibility='private' from public.friend_profiles where user_id=auth.uid()),'new profile is private');
update public.friend_profiles set display_name='Renamed' where user_id=auth.uid();
select pg_temp.ok((select visibility='private' from public.friend_profiles where user_id=auth.uid()),'name change does not publish');
select pg_temp.ok(pg_temp.denied($q$select public.lookup_friend_invite('62000000-0000-0000-0000-000000000001')$q$),'self invite rejected');
select pg_temp.ok(pg_temp.denied($q$select public.lookup_friend_invite('62000000-0000-0000-0000-000000000099')$q$),'invalid invite rejected');
select pg_temp.ok(public.lookup_friend_invite('62000000-0000-0000-0000-000000000002')=jsonb_build_object('display_name','B','status',null),'preview exposes only name and relationship');
select public.request_friend('62000000-0000-0000-0000-000000000002');
select pg_temp.ok(public.lookup_friend_invite('62000000-0000-0000-0000-000000000002')->>'status'='pending','duplicate relationship preview');
insert into storage.objects(bucket_id,name) values('friend-avatars','61000000-0000-0000-0000-000000000001/1.png');
update public.friend_profiles set avatar_path='61000000-0000-0000-0000-000000000001/1.png' where user_id=auth.uid();
select pg_temp.ok((select count(*)=1 from storage.objects where bucket_id='friend-avatars'),'owner reads private avatar');
select pg_temp.ok(pg_temp.denied($q$update storage.objects set bucket_id='friend-avatars',name='61000000-0000-0000-0000-000000000002/2.png' where name='61000000-0000-0000-0000-000000000001/1.png'$q$),'broad grant cannot transfer photo ownership');
select pg_temp.ok(pg_temp.denied($q$insert into storage.objects(bucket_id,name) values('friend-avatars','61000000-0000-0000-0000-000000000002/1.png')$q$),'other folder upload rejected');
select pg_temp.ok(pg_temp.denied($q$update public.friend_profiles set avatar_path='61000000-0000-0000-0000-000000000002/1.png' where user_id=auth.uid()$q$),'other photo reference rejected');
select pg_temp.ok(pg_temp.denied($q$insert into storage.objects(bucket_id,name) values('friend-avatars','61000000-0000-0000-0000-000000000001/../2.png')$q$),'path traversal rejected');
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000002',true);
select pg_temp.ok((select count(*)=0 from storage.objects where bucket_id='friend-avatars'),'pending cannot read photo');
select pg_temp.ok((select avatar_path is null from public.list_friend_connections_with_avatar()),'pending cannot get photo path');
select public.accept_friend((select id from public.friend_connections limit 1));
select pg_temp.ok((select count(*)=0 from storage.objects where bucket_id='friend-avatars'),'approved cannot read private photo');
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000001',true);
update public.friend_profiles set visibility='friends' where user_id=auth.uid();
select public.publish_friend_workouts('[{"date":"2026-10-02T00:00:00Z","sets":[]},{"date":"2026-10-03T00:00:00Z","sets":[]}]');
select public.request_friend('62000000-0000-0000-0000-000000000003');
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000003',true);
select public.accept_friend((select id from public.friend_connections limit 1));
update public.friend_profiles set visibility='friends' where user_id=auth.uid();
select public.publish_friend_workouts('[{"date":"2026-10-01T00:00:00Z","sets":[]},{"date":"2026-10-04T00:00:00Z","sets":[]}]');
select public.request_friend('62000000-0000-0000-0000-000000000002');
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000002',true);
select public.accept_friend((select id from public.friend_connections where status='pending'));
select pg_temp.ok((select count(*)=1 from storage.objects where bucket_id='friend-avatars'),'approved reads shared current photo');
select pg_temp.ok((select count(*)=2 from public.latest_friend_workouts()),'one latest session for each approved friend');
select pg_temp.ok((select min(performed_at)='2026-10-03T00:00:00Z' from public.latest_friend_workouts()),'old sessions excluded from home');
select pg_temp.ok((select count(*)=4 from public.friend_workouts),'detail history remains intact');
update storage.objects set name='61000000-0000-0000-0000-000000000002/99.png' where bucket_id='friend-avatars';
delete from storage.objects where bucket_id='friend-avatars';
update public.friend_profiles set avatar_path=null where user_id='61000000-0000-0000-0000-000000000001';
select pg_temp.ok((select count(*)=1 from storage.objects where bucket_id='friend-avatars'),'friend cannot overwrite or delete photo');
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000004',true);
select pg_temp.ok((select count(*)=0 from public.latest_friend_workouts()),'stranger feed denied');
select pg_temp.ok((select count(*)=0 from storage.objects where bucket_id='friend-avatars'),'stranger photo denied');
select pg_temp.ok((select count(*)=0 from public.list_friend_connections_with_avatar()),'stranger connections denied');
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000001',true);
update public.friend_profiles set avatar_path=null,visibility='private' where user_id=auth.uid();
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000002',true);
select pg_temp.ok((select count(*)=0 from storage.objects where bucket_id='friend-avatars'),'removed photo and private setting revoke read');
select pg_temp.ok((select count(*)=1 from public.latest_friend_workouts()),'private friend excluded from latest feed');
delete from public.friend_connections;
select pg_temp.ok((select count(*)=0 from public.latest_friend_workouts()),'removal revokes latest feed');
set local role anon;
select pg_temp.ok(pg_temp.denied($q$select public.lookup_friend_invite('62000000-0000-0000-0000-000000000001')$q$),'anonymous preview denied');
select pg_temp.ok(pg_temp.denied($q$select public.latest_friend_workouts()$q$),'anonymous latest feed denied');
select pg_temp.ok((select count(*)=0 from storage.objects where bucket_id='friend-avatars'),'anonymous private bucket denied');
select pg_temp.ok(pg_temp.denied($q$insert into storage.objects(bucket_id,name) values('friend-avatars','61000000-0000-0000-0000-000000000002/2.png')$q$),'broad grant cannot enable anonymous upload');
reset role;
select pg_temp.ok((select not public and file_size_limit=524288 and allowed_mime_types=array['image/png'] from storage.buckets where id='friend-avatars'),'bucket is private and bounds PNG uploads');
insert into storage.buckets(id,name,public) values('fixture-other-bucket','fixture-other-bucket',false);
set local role authenticated;
insert into storage.objects(bucket_id,name) values('fixture-other-bucket','unrelated/file.png');
select pg_temp.ok((select count(*)=1 from storage.objects where bucket_id='fixture-other-bucket'),'existing other bucket access preserved');
update storage.objects set name='unrelated/renamed.png' where bucket_id='fixture-other-bucket';
delete from storage.objects where bucket_id='fixture-other-bucket';
select pg_temp.ok((select count(*)=0 from storage.objects where bucket_id='fixture-other-bucket'),'existing other bucket mutations preserved');
rollback;
