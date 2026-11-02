-- Synthetic local fixtures only. All changes roll back.
begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',label; end if; raise notice 'PASS: %',label; end $$;
insert into auth.users(id) select ('91000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,5) n;
insert into public.friend_profiles(user_id,display_name,visibility)
 select id,'Synthetic',case when id='91000000-0000-4000-8000-000000000004' then 'private' else 'friends' end
 from auth.users where id::text like '91000000-%';
insert into public.friend_connections(requester,recipient,status)
 select '91000000-0000-4000-8000-000000000001',user_id,'accepted' from public.friend_profiles
 where user_id in('91000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000003','91000000-0000-4000-8000-000000000004');
insert into public.friend_workouts(user_id,client_id,performed_at,duration_seconds,sets) values
 ('91000000-0000-4000-8000-000000000002','older','2026-01-01T00:00:00Z',60,'[]'),
 ('91000000-0000-4000-8000-000000000002','newer','2026-10-30T00:00:00Z',60,'[]'),
 ('91000000-0000-4000-8000-000000000003','third','2026-10-30T00:00:00Z',60,'[]'),
 ('91000000-0000-4000-8000-000000000004','private','2026-10-30T00:00:00Z',60,'[]'),
 ('91000000-0000-4000-8000-000000000005','unapproved','2026-10-30T00:00:00Z',60,'[]'),
 ('91000000-0000-4000-8000-000000000001','self','2026-10-30T00:00:00Z',60,'[]');
select pg_temp.ok((select count(distinct updated_at)=1 from public.friend_workouts),'one shared batch has one update timestamp');
create temporary table before_update as select id,updated_at from public.friend_workouts;
update public.friend_workouts set sets=sets,updated_at='2000-01-01T00:00:00Z';
select pg_temp.ok(not exists(select 1 from public.friend_workouts f join before_update b using(id) where f.updated_at is distinct from b.updated_at),'no-op re-sync preserves timestamp and ignores supplied stamp');
update public.friend_workouts set duration_seconds=61 where client_id='older';
select pg_temp.ok((select f.updated_at>b.updated_at from public.friend_workouts f join before_update b using(id) where f.client_id='older'),'real content edit advances update time');
select pg_temp.ok((select not prosecdef from pg_proc where oid='public.latest_updated_friend_workouts()'::regprocedure),'latest updates uses invoker RLS');
select pg_temp.ok(not has_function_privilege('anon','public.latest_updated_friend_workouts()','execute'),'anonymous cannot execute updates RPC');
select pg_temp.ok(not has_column_privilege('authenticated','public.friend_workouts','updated_at','update'),'clients cannot forge update times');
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
select pg_temp.ok((select count(*)=2 from public.latest_updated_friend_workouts()),'only accepted public friends with visible records are returned');
select pg_temp.ok((select client_id='older' from public.latest_updated_friend_workouts() where user_id='91000000-0000-4000-8000-000000000002'),'edited old workout wins over newer exercise date');
reset role;
-- Simulate legacy timestamps and exact ties, without rewriting real data.
alter table public.friend_workouts disable trigger friend_workout_updated_at;
update public.friend_workouts set updated_at=null where client_id in('older','newer');
alter table public.friend_workouts enable trigger friend_workout_updated_at;
set local role authenticated;
select pg_temp.ok((select updated_at is null and client_id='newer' from public.latest_updated_friend_workouts() where user_id='91000000-0000-4000-8000-000000000002'),'legacy rows remain unknown; exercise date only selects displayed legacy record');
reset role;
alter table public.friend_workouts disable trigger friend_workout_updated_at;
update public.friend_workouts set updated_at='2026-11-02T00:00:00Z' where client_id in('older','newer');
alter table public.friend_workouts enable trigger friend_workout_updated_at;
set local role authenticated;
select pg_temp.ok((select client_id='newer' from public.latest_updated_friend_workouts() where user_id='91000000-0000-4000-8000-000000000002'),'exact update tie has deterministic record selection');
reset role;
delete from public.friend_workouts where client_id='newer';
set local role authenticated;
select pg_temp.ok((select client_id='older' from public.latest_updated_friend_workouts() where user_id='91000000-0000-4000-8000-000000000002'),'deleted latest record falls back to surviving visible record');
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
update public.friend_profiles set visibility='private' where user_id=auth.uid();
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
select pg_temp.ok((select count(*)=1 from public.latest_updated_friend_workouts()),'private setting immediately revokes content and update metadata');
delete from public.friend_connections where recipient='91000000-0000-4000-8000-000000000003';
select pg_temp.ok((select count(*)=0 from public.latest_updated_friend_workouts()),'relationship removal immediately revokes update feed');
reset role;
rollback;
