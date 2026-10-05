begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.denied(q text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then return true; end $$;
insert into auth.users(id) values('a1000000-0000-0000-0000-000000000001'),('a1000000-0000-0000-0000-000000000002'),('a1000000-0000-0000-0000-000000000003');
insert into public.friend_profiles(user_id,display_name,visibility) values
 ('a1000000-0000-0000-0000-000000000001','Owner','friends'),
 ('a1000000-0000-0000-0000-000000000002','Friend','friends'),
 ('a1000000-0000-0000-0000-000000000003','Stranger','private');
insert into public.friend_connections(requester,recipient,status) values('a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000002','accepted');
insert into public.friend_workouts(id,user_id,client_id,performed_at,duration_seconds,sets) values
 ('a3000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','record-one',now(),30,'[]'),
 ('a3000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000001','record-two',now(),30,'[]');
set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
create temporary table receipt as select public.send_friend_comment('a3000000-0000-0000-0000-000000000001','日本語コメント','a4000000-0000-4000-8000-000000000001') as id;
select pg_temp.ok(public.send_friend_comment('a3000000-0000-0000-0000-000000000001','日本語コメント','a4000000-0000-4000-8000-000000000001')=(select id from receipt),'lost-response retry returns original comment');
select pg_temp.ok((select count(*)=1 from public.friend_comments),'same operation creates exactly one comment');
select pg_temp.ok(pg_temp.denied($q$select public.send_friend_comment('a3000000-0000-0000-0000-000000000001','changed','a4000000-0000-4000-8000-000000000001')$q$),'same operation cannot change body');
select pg_temp.ok(pg_temp.denied($q$select public.send_friend_comment('a3000000-0000-0000-0000-000000000002','日本語コメント','a4000000-0000-4000-8000-000000000001')$q$),'same operation cannot move thread');
select pg_temp.ok(pg_temp.denied($q$select public.send_friend_comment('a3000000-0000-0000-0000-000000000001',repeat('あ',141),'a4000000-0000-4000-8000-000000000002')$q$),'141 Unicode characters denied');
select pg_temp.ok(pg_temp.denied($q$select public.send_friend_comment('a3000000-0000-0000-0000-000000000001',E'\n\t ','a4000000-0000-4000-8000-000000000002')$q$),'whitespace-only denied');
select public.send_friend_comment('a3000000-0000-0000-0000-000000000001',repeat('あ',140),'a4000000-0000-4000-8000-000000000002');
select pg_temp.ok((select count(*)=2 from public.friend_comments),'140 Unicode characters accepted');
select pg_temp.ok(pg_temp.denied($q$select * from public.friend_comment_operations$q$),'even author cannot enumerate private receipts');
delete from public.friend_comments where id=(select id from receipt);
select pg_temp.ok(pg_temp.denied($q$select public.send_friend_comment('a3000000-0000-0000-0000-000000000001','日本語コメント','a4000000-0000-4000-8000-000000000001')$q$),'deleted comment operation cannot resurrect');
select pg_temp.ok((select count(*)=1 from public.friend_comments),'delete retry did not create replacement');
-- Older clients still write through their original RLS-protected endpoint.
insert into public.friend_comments(workout_id,user_id,body) values('a3000000-0000-0000-0000-000000000001',auth.uid(),'Legacy comment');
select pg_temp.ok((select count(*)=2 from public.friend_comments),'legacy direct INSERT remains compatible');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
select public.send_friend_comment('a3000000-0000-0000-0000-000000000001','Owner uses same op UUID','a4000000-0000-4000-8000-000000000002');
select pg_temp.ok((select count(*)=3 from public.friend_comments),'operations scoped per authenticated author');
update public.friend_profiles set visibility='private' where user_id=auth.uid();
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
select pg_temp.ok(pg_temp.denied($q$select public.send_friend_comment('a3000000-0000-0000-0000-000000000001',repeat('あ',140),'a4000000-0000-4000-8000-000000000002')$q$),'known receipt replay denied after owner makes record private');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
update public.friend_profiles set visibility='friends' where user_id=auth.uid();
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
delete from public.friend_connections;
select pg_temp.ok(pg_temp.denied($q$select public.send_friend_comment('a3000000-0000-0000-0000-000000000001',repeat('あ',140),'a4000000-0000-4000-8000-000000000002')$q$),'known receipt replay denied after friend removal');
select pg_temp.ok(pg_temp.denied($q$select public.send_friend_comment('a3000000-0000-0000-0000-000000000001','new','a4000000-0000-4000-8000-000000000003')$q$),'removed friend cannot create new comment');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000003',true);
select pg_temp.ok(pg_temp.denied($q$select public.send_friend_comment('a3000000-0000-0000-0000-000000000001','new','a4000000-0000-4000-8000-000000000003')$q$),'stranger cannot create comment');
set local role anon;
select pg_temp.ok(pg_temp.denied($q$select public.send_friend_comment('a3000000-0000-0000-0000-000000000001','anonymous','a4000000-0000-4000-8000-000000000003')$q$),'anonymous cannot execute');
reset role;
select pg_temp.ok((select deleted and comment_id is null from public.friend_comment_operations where user_id='a1000000-0000-0000-0000-000000000002' and operation_id='a4000000-0000-4000-8000-000000000001'),'delete stores tombstone without retained body');
select pg_temp.ok((select body_hash=sha256(convert_to('日本語コメント','UTF8')) from public.friend_comment_operations where operation_id='a4000000-0000-4000-8000-000000000001'),'only SHA256 binding retained');
delete from auth.users where id='a1000000-0000-0000-0000-000000000002';
select pg_temp.ok((select count(*)=0 from public.friend_comment_operations where user_id='a1000000-0000-0000-0000-000000000002'),'author deletion cascades receipts and tombstones');
select pg_temp.ok((select count(*)=1 from public.friend_comments),'author deletion cascades legacy and new comments');
delete from public.friend_workouts where id='a3000000-0000-0000-0000-000000000001';
select pg_temp.ok((select count(*)=0 from public.friend_comment_operations),'workout deletion cascades remaining operations');
rollback;
