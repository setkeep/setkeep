begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.denied(q text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then return true; end $$;
insert into auth.users(id) values
 ('81000000-0000-0000-0000-000000000001'),('81000000-0000-0000-0000-000000000002'),
 ('81000000-0000-0000-0000-000000000003'),('81000000-0000-0000-0000-000000000004');
insert into public.friend_profiles(user_id,display_name,visibility,avatar_path) values
 ('81000000-0000-0000-0000-000000000001','Owner','friends',null),
 ('81000000-0000-0000-0000-000000000002','Friend','friends','81000000-0000-0000-0000-000000000002/1.png'),
 ('81000000-0000-0000-0000-000000000003','Pending','friends',null),
 ('81000000-0000-0000-0000-000000000004','Other','friends',null);
insert into public.friend_connections(requester,recipient,status) values
 ('81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000002','accepted'),
 ('81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000003','pending');
insert into public.friend_workouts(id,user_id,client_id,performed_at,duration_seconds,sets) values
 ('83000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000001','2020-01-01T10:00:00.000','2020-01-01T10:00:00Z',60,'[]'),
 ('83000000-0000-0000-0000-000000000002','81000000-0000-0000-0000-000000000002','2020-01-01T10:00:00.000','2020-01-01T10:00:00Z',60,'[]');
set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000002',true);
insert into public.friend_likes(workout_id,user_id,created_at) values
 ('83000000-0000-0000-0000-000000000001',auth.uid(),'2000-01-01T00:00:00Z');
select pg_temp.ok((select created_at>now()-interval '1 minute' from public.friend_likes where user_id=auth.uid()),'client cannot forge like timestamp');
select pg_temp.ok((select count(*)=0 from public.received_friend_likes()),'actor cannot read another owners inbox');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_likes(workout_id,user_id) values('83000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000004')$q$),'cannot forge liker');
select pg_temp.ok(pg_temp.denied($q$update public.friend_likes set created_at='2030-01-01'$q$),'cannot rewrite timestamp');
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000001',true);
select pg_temp.ok((select count(*)=1 from public.received_friend_likes()),'owner receives exactly one like');
select pg_temp.ok((select owner_id=auth.uid() and client_id='2020-01-01T10:00:00.000' and workout_id='83000000-0000-0000-0000-000000000001' from public.received_friend_likes()),'exact old session identity returned');
select pg_temp.ok((select display_name='Friend' and avatar_path is not null from public.received_friend_likes()),'registered actor name and authorized avatar returned');
insert into public.friend_likes(workout_id,user_id) values('83000000-0000-0000-0000-000000000001',auth.uid());
select pg_temp.ok((select count(*)=1 from public.received_friend_likes()),'self likes do not generate notifications');
reset role;
update public.friend_profiles set display_name='Renamed',visibility='private' where user_id='81000000-0000-0000-0000-000000000002';
set local role authenticated;
select pg_temp.ok((select display_name='Renamed' and avatar_path is null from public.received_friend_likes()),'fresh registered name but private actor avatar withheld');
reset role;
update public.friend_profiles set visibility='private' where user_id='81000000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.ok((select count(*)=0 from public.received_friend_likes()),'unshared owner has no notifications');
select pg_temp.ok((select count(*)=2 from public.friend_liker_avatars('83000000-0000-0000-0000-000000000001')),'own like count remains readable when private');
reset role;
update public.friend_profiles set visibility='friends' where user_id in('81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000002');
insert into public.friend_likes(workout_id,user_id) values('83000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000003');
set local role authenticated;
select pg_temp.ok((select count(*)=1 from public.received_friend_likes()),'unapproved liker is excluded');
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000004',true);
select pg_temp.ok((select count(*)=0 from public.received_friend_likes()),'unrelated inbox read denied');
select pg_temp.ok((select count(*)=0 from public.friend_liker_avatars('83000000-0000-0000-0000-000000000001')),'unrelated detail like read denied');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_likes(workout_id,user_id) values('83000000-0000-0000-0000-000000000001',auth.uid())$q$),'unrelated like write denied');
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000002',true);
select created_at as original_created from public.friend_likes where user_id=auth.uid() and workout_id='83000000-0000-0000-0000-000000000001' \gset
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_likes(workout_id,user_id) values('83000000-0000-0000-0000-000000000001',auth.uid())$q$),'one like per actor/session');
delete from public.friend_likes where user_id=auth.uid() and workout_id='83000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000001',true);
select pg_temp.ok((select count(*)=0 from public.received_friend_likes()),'unlike removes notification');
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000002',true);
select pg_sleep(.001);
insert into public.friend_likes(workout_id,user_id) values('83000000-0000-0000-0000-000000000001',auth.uid());
select pg_temp.ok((select created_at>:'original_created'::timestamptz from public.friend_likes where user_id=auth.uid() and workout_id='83000000-0000-0000-0000-000000000001'),'relike gets a new actual event timestamp');
delete from public.friend_connections where recipient=auth.uid();
select pg_temp.ok((select count(*)=0 from public.friend_likes where workout_id='83000000-0000-0000-0000-000000000001'),'removed friend cannot read likes');
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000001',true);
select pg_temp.ok((select count(*)=0 from public.received_friend_likes()),'friend removal suppresses owner notification');
reset role;
insert into public.friend_connections(requester,recipient,status) values('81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000002','accepted');
insert into public.account_avatar_cleanup(user_id) values('81000000-0000-0000-0000-000000000002');
set local role authenticated;
select pg_temp.ok((select count(*)=0 from public.received_friend_likes()),'pending actor cleanup suppresses name and photo');
reset role;
delete from public.account_avatar_cleanup;
update public.friend_likes set created_at=null where user_id='81000000-0000-0000-0000-000000000002';
set local role authenticated;
select pg_temp.ok((select count(*)=0 from public.received_friend_likes()),'legacy timestamp is not invented or delivered as a new event');
select pg_temp.ok((select count(*)=3 from public.friend_liker_avatars('83000000-0000-0000-0000-000000000001')),'legacy likes still count in existing detail');
reset role;
update public.friend_likes set created_at=clock_timestamp() where user_id='81000000-0000-0000-0000-000000000002';
delete from public.friend_workouts where id='83000000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.ok((select count(*)=0 from public.received_friend_likes()),'deleted workout removes notification');
select pg_temp.ok((select count(*)=0 from public.friend_likes),'deleted workout likes cascade');
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000001',true);
set local role anon;
select pg_temp.ok(pg_temp.denied('select public.received_friend_likes()'),'anonymous notification read denied');
select pg_temp.ok(pg_temp.denied('select * from public.friend_likes'),'anonymous like table read denied');
set local role authenticated;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.ok((select count(*)=0 from public.received_friend_likes()),'authenticated role without a user cannot read');
rollback;
