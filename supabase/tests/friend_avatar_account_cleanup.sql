-- Synthetic Auth/Storage metadata ONLY. ROLLBACK removes every fixture.
\set ON_ERROR_STOP on
begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',label;end if;raise notice 'PASS: %',label;end $$;
create function pg_temp.denied(q text,state text default '42501') returns boolean language plpgsql as $$
begin execute q;return false;exception when others then return sqlstate=state;end $$;
create policy fixture_broad_avatar on storage.objects for all to anon,authenticated using(true) with check(true);
insert into auth.users(id,email,email_confirmed_at)
select ('d1000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'avatar'||n||'@test.invalid',now() from generate_series(1,4)n;
insert into public.friend_profiles(user_id,display_name,visibility,avatar_path) values
('d1000000-0000-0000-0000-000000000001','A','friends','d1000000-0000-0000-0000-000000000001/1.png'),
('d1000000-0000-0000-0000-000000000002','B','friends','d1000000-0000-0000-0000-000000000002/2.png');
insert into public.friend_connections(requester,recipient,status) values
('d1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000002','accepted');
insert into storage.objects(bucket_id,name,owner_id) values
('friend-avatars','d1000000-0000-0000-0000-000000000001/1.png','d1000000-0000-0000-0000-000000000001'),
('friend-avatars','d1000000-0000-0000-0000-000000000001/9.png','d1000000-0000-0000-0000-000000000001'),
('friend-avatars','d1000000-0000-0000-0000-000000000002/2.png','d1000000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000001',true);
select pg_temp.ok((select count(*)=3 from storage.objects where bucket_id='friend-avatars'),'owner reads owned photos and approved current peer photo');
select pg_temp.ok(pg_temp.denied($q$select * from public.account_avatar_cleanup$q$),'caller cannot read cleanup gate');
select pg_temp.ok(pg_temp.denied($q$select public.account_avatar_cleanup_begin('d1000000-0000-0000-0000-000000000002',repeat('a',64),'d2000000-0000-0000-0000-000000000001')$q$),'caller cannot initiate another user cleanup');
reset role;
select pg_temp.ok(pg_temp.denied($q$delete from auth.users where id='d1000000-0000-0000-0000-000000000001'$q$,'P0001'),'direct Auth deletion refuses remaining avatar bytes');
set local role service_role;
select pg_temp.ok((public.account_deletion_prepare('d1000000-0000-0000-0000-000000000001',repeat('a',64))->>'avatar_cleanup_required')::boolean,'prepare explicitly requires media phase');
select pg_temp.ok((public.account_avatar_cleanup_begin('d1000000-0000-0000-0000-000000000001',repeat('a',64),'d2000000-0000-0000-0000-000000000001')->>'ready')::boolean,'verified request claims cleanup gate');
select pg_temp.ok(not (public.account_avatar_cleanup_begin('d1000000-0000-0000-0000-000000000001',repeat('a',64),'d2000000-0000-0000-0000-000000000002')->>'ready')::boolean,'concurrent attempt cannot steal live lease');
select pg_temp.ok(not public.account_avatar_cleanup_release('d1000000-0000-0000-0000-000000000001',repeat('a',64),'d2000000-0000-0000-0000-000000000002'),'wrong attempt cannot release lease');
select pg_temp.ok(not (public.account_avatar_cleanup_confirm('d1000000-0000-0000-0000-000000000001',repeat('a',64),'d2000000-0000-0000-0000-000000000001')->>'ready')::boolean,'remaining metadata prevents confirmation');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000001',true);
select pg_temp.ok((select count(*)=0 from storage.objects where bucket_id='friend-avatars'),'pending deletion stops owner reads');
select pg_temp.ok(pg_temp.denied($q$insert into storage.objects(bucket_id,name) values('friend-avatars','d1000000-0000-0000-0000-000000000001/3.png')$q$),'pending deletion stops new uploads');
select pg_temp.ok(not public.cancel_avatar_account_deletion(),'live worker cannot be cancelled during removal');
select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000002',true);
select pg_temp.ok((select count(*)=1 from storage.objects where bucket_id='friend-avatars'),'pending owner photos also hidden from approved peer');
select pg_temp.ok(not public.cancel_avatar_account_deletion(),'peer cannot cancel someone else cleanup');
reset role;
set local role service_role;
select pg_temp.ok(public.account_avatar_cleanup_release('d1000000-0000-0000-0000-000000000001',repeat('a',64),'d2000000-0000-0000-0000-000000000001'),'failed attempt releases own lease');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000001',true);
select pg_temp.ok(public.cancel_avatar_account_deletion(),'only live owner can cancel inactive attempt');
select pg_temp.ok((select count(*)=3 from storage.objects where bucket_id='friend-avatars'),'cancel reopens access without deleting photos');
reset role;
set local role service_role;
select pg_temp.ok((public.account_avatar_cleanup_begin('d1000000-0000-0000-0000-000000000001',repeat('b',64),'d2000000-0000-0000-0000-000000000002')->>'ready')::boolean,'new verified token safely retries same owner');
reset role;
-- Model acknowledged Storage API metadata removal only in this synthetic DB.
delete from storage.objects where bucket_id='friend-avatars' and split_part(name,'/',1)='d1000000-0000-0000-0000-000000000001';
set local role service_role;
select pg_temp.ok((public.account_avatar_cleanup_confirm('d1000000-0000-0000-0000-000000000001',repeat('b',64),'d2000000-0000-0000-0000-000000000002')->>'ready')::boolean,'empty verified prefix allows Auth phase');
reset role;
delete from auth.users where id='d1000000-0000-0000-0000-000000000001';
select pg_temp.ok((select count(*)=0 from public.account_avatar_cleanup),'successful Auth transaction removes cleanup gate');
select pg_temp.ok((select count(*)=1 from storage.objects where bucket_id='friend-avatars'),'peer photo untouched');
select pg_temp.ok((select count(*)=1 from public.friend_profiles),'peer profile untouched');
set local role service_role;
select pg_temp.ok(public.account_deletion_receipt(repeat('b',64)),'lost success response retains completion receipt');
reset role;
-- Simulate a residual object to prove stale JWT denial independently of absence.
insert into storage.objects(bucket_id,name,owner_id) values('friend-avatars','d1000000-0000-0000-0000-000000000001/99.png','d1000000-0000-0000-0000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000001',true);
select pg_temp.ok((select count(*)=0 from storage.objects where bucket_id='friend-avatars'),'deleted JWT cannot read residual own or peer photos');
select pg_temp.ok(pg_temp.denied($q$insert into storage.objects(bucket_id,name) values('friend-avatars','d1000000-0000-0000-0000-000000000001/100.png')$q$),'deleted JWT cannot recreate images');
update storage.objects set name='d1000000-0000-0000-0000-000000000001/98.png' where bucket_id='friend-avatars';
delete from storage.objects where bucket_id='friend-avatars';
reset role;
select pg_temp.ok((select count(*)=2 from storage.objects where bucket_id='friend-avatars'),'deleted JWT cannot update or delete other residual objects');
insert into storage.buckets(id,name,public) values('unrelated','unrelated',false);
insert into storage.objects(bucket_id,name,owner_id) values('unrelated','legacy/record.dat','d1000000-0000-0000-0000-000000000002');
set local role service_role;
select pg_temp.ok(public.account_avatar_cleanup_begin('d1000000-0000-0000-0000-000000000002',repeat('c',64),'d2000000-0000-0000-0000-000000000003')->>'error'='unsupported_storage_owner','unrelated owned Storage blocks media phase without deleting it');
reset role;
select pg_temp.ok((select count(*)=0 from public.account_avatar_cleanup),'unsupported Storage does not set pending gate');
select pg_temp.ok((select count(*)=1 from storage.objects where bucket_id='unrelated'),'unrelated object retained');
delete from storage.objects where bucket_id='unrelated';
insert into storage.objects(bucket_id,name,owner_id) values('friend-avatars','d1000000-0000-0000-0000-000000000002/99.png','d1000000-0000-0000-0000-000000000003');
set local role service_role;
select pg_temp.ok(public.account_avatar_cleanup_begin('d1000000-0000-0000-0000-000000000002',repeat('c',64),'d2000000-0000-0000-0000-000000000003')->>'error'='unsupported_avatar_owner','foreign owner metadata is never deletion authority');
reset role;
select pg_temp.ok((select count(*)=3 from storage.objects where bucket_id='friend-avatars'),'foreign ownership failure preserves every image');
set local role anon;
select pg_temp.ok((select count(*)=0 from storage.objects where bucket_id='friend-avatars'),'anonymous remains denied despite broad grant');
select pg_temp.ok(pg_temp.denied($q$select public.cancel_avatar_account_deletion()$q$),'anonymous cannot cancel cleanup');
reset role;
rollback;
