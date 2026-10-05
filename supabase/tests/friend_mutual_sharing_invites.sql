begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.denied(q text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then return true; end $$;
insert into auth.users(id) values
 ('71000000-0000-0000-0000-000000000001'),('71000000-0000-0000-0000-000000000002'),
 ('71000000-0000-0000-0000-000000000003'),('71000000-0000-0000-0000-000000000004');
insert into public.friend_profiles(user_id,display_name,invite_code,avatar_path) values
 ('71000000-0000-0000-0000-000000000001','Owner','72000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001/1.png'),
 ('71000000-0000-0000-0000-000000000002','Friend','72000000-0000-0000-0000-000000000002','71000000-0000-0000-0000-000000000002/2.png'),
 ('71000000-0000-0000-0000-000000000003','Third','72000000-0000-0000-0000-000000000003','71000000-0000-0000-0000-000000000003/3.png'),
 ('71000000-0000-0000-0000-000000000004','Pending','72000000-0000-0000-0000-000000000004',null);
select pg_temp.ok((select bool_and(visibility='private' and sharing_consent_version=0) from public.friend_profiles where user_id::text like '71000000%'),'migration preserves private defaults');
insert into public.friend_invite_codes values('71000000-0000-0000-0000-000000000002','ABCD2345',now());
create temporary table generator_saved as select pg_get_functiondef('public.generate_friend_short_code()'::regprocedure) as definition;
create temporary sequence collision_sequence;
create or replace function public.generate_friend_short_code() returns text language sql volatile as $$
 select case when nextval('pg_temp.collision_sequence')=1 then 'ABCD2345' else 'HJKM6789' end
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000001',true);
select pg_temp.ok(public.my_friend_invite_code()='HJKM6789','collision retries and never steals other owner code');
select pg_temp.ok(public.my_friend_invite_code()='HJKM6789','own code stable across device refresh');
select pg_temp.ok(pg_temp.denied($q$select * from public.friend_invite_codes$q$),'even owner cannot enumerate private code table');
select pg_temp.ok(pg_temp.denied($q$select public.resolve_friend_invite('ABCD2345')$q$),'resolver internal only');
select pg_temp.ok(public.lookup_friend_invite_v2('abcd-2345')=jsonb_build_object('ok',true,'display_name','Friend','status',null),'short preview normalizes human form and reveals minimal fields');
select pg_temp.ok(public.lookup_friend_invite_v2('72000000-0000-0000-0000-000000000002')->>'display_name'='Friend','legacy UUID links remain valid');
select pg_temp.ok(public.lookup_friend_invite_v2('bad')=public.lookup_friend_invite_v2('HJKM6789'),'unknown and self responses indistinguishable');
select pg_temp.ok(public.request_friend_v2('ABCD2345')->>'status'='pending','short code creates pending only');
select pg_temp.ok(public.request_friend_v2('ABCD2345')->>'status'='pending','repeat request idempotent');
select pg_temp.ok(pg_temp.denied($q$select public.accept_friend((select id from public.friend_connections limit 1))$q$),'requester cannot self approve');
select pg_temp.ok(pg_temp.denied($q$select public.acknowledge_mutual_friend_sharing('privacy-1.1')$q$),'old consent cannot grant new sharing');
select public.acknowledge_mutual_friend_sharing('privacy-1.2');
select pg_temp.ok((select visibility='friends' and sharing_consent_version=1 from public.friend_profiles where user_id=auth.uid()),'explicit new consent grants own sharing');
reset role;
select pg_temp.ok((select visibility='private' and sharing_consent_version=0 from public.friend_profiles where display_name='Friend'),'other private owner permission unchanged');
do $$ begin execute (select definition from generator_saved); end $$;
select pg_temp.ok((select bool_and(public.generate_friend_short_code() ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$') from generate_series(1,1000)),'secure generator format avoids confusable symbols');
insert into public.friend_workouts(id,user_id,client_id,performed_at,duration_seconds,sets) values
 ('73000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001','2026-10-03T00:00:00.000',now(),10,'[]'),
 ('73000000-0000-0000-0000-000000000002','71000000-0000-0000-0000-000000000002','private-record',now(),10,'[]');
insert into public.friend_connections(requester,recipient,status) values
 ('71000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000003','accepted'),
 ('71000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000004','pending');
set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000002',true);
select pg_temp.ok((select count(*)=0 from public.friend_comment_thread('73000000-0000-0000-0000-000000000001')),'pending interaction identities denied');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_likes values('73000000-0000-0000-0000-000000000001',auth.uid())$q$),'pending like denied');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_comments(workout_id,user_id,body) values('73000000-0000-0000-0000-000000000001',auth.uid(),'pending')$q$),'pending comment denied');
select public.accept_friend((select id from public.friend_connections where requester='71000000-0000-0000-0000-000000000001'));
insert into public.friend_likes values('73000000-0000-0000-0000-000000000001',auth.uid());
insert into public.friend_comments(workout_id,user_id,body) values('73000000-0000-0000-0000-000000000001',auth.uid(),'日本語\nHello');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_likes values('73000000-0000-0000-0000-000000000001',auth.uid())$q$),'one like per user preserved');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_comments(workout_id,user_id,body) values('73000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001','impersonated')$q$),'comment impersonation denied');
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000003',true);
select public.acknowledge_mutual_friend_sharing('privacy-1.2');
insert into public.friend_likes values('73000000-0000-0000-0000-000000000001',auth.uid());
insert into public.friend_comments(workout_id,user_id,body) values('73000000-0000-0000-0000-000000000001',auth.uid(),'Third comment');
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000001',true);
select pg_temp.ok((select display_name='Friend' and avatar_path is null from public.friend_comment_thread('73000000-0000-0000-0000-000000000001') where user_id='71000000-0000-0000-0000-000000000002'),'approved name visible but private sender photo denied');
select pg_temp.ok((select count(*)=0 from public.friend_comment_thread('73000000-0000-0000-0000-000000000002')),'private workout thread denied even to approved friend');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_comments(workout_id,user_id,body) values('73000000-0000-0000-0000-000000000002',auth.uid(),'private')$q$),'private workout write denied');
select pg_temp.ok((select count(*)=2 from public.friend_liker_avatars('73000000-0000-0000-0000-000000000001')),'liker rows agree with original workout count');
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000002',true);
select pg_temp.ok((select display_name is null and avatar_path is null from public.friend_comment_thread('73000000-0000-0000-0000-000000000001') where user_id='71000000-0000-0000-0000-000000000003'),'unrelated third party name/photo withheld');
select public.acknowledge_mutual_friend_sharing('privacy-1.2');
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000001',true);
select pg_temp.ok((select avatar_path is not null from public.friend_liker_avatars('73000000-0000-0000-0000-000000000001') where user_id='71000000-0000-0000-0000-000000000002'),'approved shared liker photo available');
reset role;
insert into public.account_avatar_cleanup(user_id) values('71000000-0000-0000-0000-000000000002');
set local role authenticated;
select pg_temp.ok((select avatar_path is null from public.friend_liker_avatars('73000000-0000-0000-0000-000000000001') where user_id='71000000-0000-0000-0000-000000000002'),'pending account cleanup revokes liker avatar');
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000004',true);
select pg_temp.ok((select count(*)=0 from public.friend_comment_thread('73000000-0000-0000-0000-000000000001')),'unapproved thread denied');
select pg_temp.ok((select count(*)=0 from public.friend_liker_avatars('73000000-0000-0000-0000-000000000001')),'unapproved likers denied');
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000002',true);
delete from public.friend_connections;
select pg_temp.ok((select count(*)=0 from public.friend_comment_thread('73000000-0000-0000-0000-000000000001')),'friend removal revokes thread');
select pg_temp.ok((select count(*)=0 from public.friend_liker_avatars('73000000-0000-0000-0000-000000000001')),'friend removal revokes avatars');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_comments(workout_id,user_id,body) values('73000000-0000-0000-0000-000000000001',auth.uid(),'removed')$q$),'removed friend write denied');
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000004',true);
do $$ begin for i in 1..25 loop perform public.lookup_friend_invite_v2('INVALID!'); end loop; end $$;
select pg_temp.ok(public.lookup_friend_invite_v2('ABCD2345')->>'ok'='false','bad attempts exhaust persistent shared rate limit');
reset role;
select pg_temp.ok((select minute_count=21 and day_count=26 from public.friend_invite_limits where user_id='71000000-0000-0000-0000-000000000004'),'invalid rate writes are committed not exception-rolled-back');
update public.friend_invite_limits set minute_start=clock_timestamp()-interval '2 minutes',day_count=100 where user_id='71000000-0000-0000-0000-000000000004';
set local role authenticated;
select pg_temp.ok(public.request_friend_v2('ABCD2345')->>'ok'='false','daily limit remains after minute reset');
set local role anon;
select pg_temp.ok(pg_temp.denied($q$select public.lookup_friend_invite_v2('ABCD2345')$q$),'anonymous preview execute denied');
select pg_temp.ok(pg_temp.denied($q$select public.my_friend_invite_code()$q$),'anonymous code denied');
select pg_temp.ok(pg_temp.denied($q$select public.friend_comment_thread('73000000-0000-0000-0000-000000000001')$q$),'anonymous thread denied');
select pg_temp.ok(pg_temp.denied($q$select public.friend_liker_avatars('73000000-0000-0000-0000-000000000001')$q$),'anonymous avatar identities denied');
select pg_temp.ok(pg_temp.denied($q$select public.acknowledge_mutual_friend_sharing('privacy-1.2')$q$),'anonymous sharing consent denied');
reset role;
delete from auth.users where id='71000000-0000-0000-0000-000000000003';
set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000001',true);
select pg_temp.ok((select count(*)=1 from public.friend_comments),'deleted author comments cascade');
select pg_temp.ok((select count(*)=1 from public.friend_likes),'deleted author likes cascade');
rollback;
