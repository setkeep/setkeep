-- Synthetic fixtures only, run with the isolated test runner, never production.
begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.denied(q text) returns boolean language plpgsql as $$
begin execute q; return false; exception when insufficient_privilege then return true; end $$;
select pg_temp.ok(public.fixture_state()=(select payload from public.fixture_snapshot),'apply preserves all existing content, ACL, policies and legacy routines');
select pg_temp.ok((select count(*)=1 from supabase_migrations.schema_migrations where version='20261102090000'),'only target migration is registered');
select pg_temp.ok((select not prosecdef from pg_proc where oid='public.latest_updated_friend_workouts()'::regprocedure),'new RPC is invoker');
select pg_temp.ok(not has_function_privilege('anon','public.latest_updated_friend_workouts()','execute'),'anon has no new execute');
select pg_temp.ok(not has_function_privilege('fixture_other','public.latest_updated_friend_workouts()','execute'),'unrelated database role has no new execute');
select pg_temp.ok(not has_function_privilege('authenticated','public.stamp_friend_workout_update()','execute'),'authenticated cannot directly invoke trigger routine');
select pg_temp.ok(not has_column_privilege('authenticated','public.friend_workouts','updated_at','update'),'new timestamp grants no direct write');
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select pg_temp.ok((select count(*)=1 from public.latest_updated_friend_workouts()),'normal approved public friend is visible');
select pg_temp.ok((select user_id='92000000-0000-4000-8000-000000000002' from public.latest_updated_friend_workouts()),'only expected friend owner is returned');
select pg_temp.ok(not exists(select 1 from public.latest_updated_friend_workouts() f
 where not exists(select 1 from public.friend_workouts old where old.id=f.id)),'new RPC is a subset of pre-existing authorized SELECT');
select pg_temp.ok(not exists(select 1 from public.latest_updated_friend_workouts() where user_id=auth.uid()),'own records do not become friend-feed records');
select pg_temp.ok(not exists(select 1 from public.latest_updated_friend_workouts()
 where user_id='92000000-0000-4000-8000-000000000003'),'accepted private friend is excluded');
select pg_temp.ok(not exists(select 1 from public.latest_updated_friend_workouts()
 where user_id='92000000-0000-4000-8000-000000000004'),'pending friend is excluded');
select pg_temp.ok(not exists(select 1 from public.latest_updated_friend_workouts()
 where user_id='92000000-0000-4000-8000-000000000005'),'unrelated user is excluded');
select pg_temp.ok(not exists(select 1 from public.latest_updated_friend_workouts()
 where user_id='92000000-0000-4000-8000-000000000006'),'synthetic restrictive block policy is respected');
select pg_temp.ok(pg_temp.denied($q$update public.friend_workouts set updated_at=now()$q$),'authenticated cannot forge timestamps');
select pg_temp.ok(pg_temp.denied($q$delete from public.friend_workouts$q$),'new RPC does not grant delete');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_workouts(user_id,client_id,performed_at,duration_seconds,sets)
 values(auth.uid(),'forged',now(),0,'[]')$q$),'new RPC does not grant insert');
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000005',true);
select pg_temp.ok((select count(*)=1 and min(user_id::text)='92000000-0000-4000-8000-000000000007' from public.latest_updated_friend_workouts()),'another viewer sees only their own authorized friend');
select set_config('request.jwt.claim.sub','',true);
select pg_temp.ok((select count(*)=0 from public.latest_updated_friend_workouts()),'authenticated role without identity sees no rows');
set local role anon;
select pg_temp.ok(pg_temp.denied($q$select public.latest_updated_friend_workouts()$q$),'anonymous execution really fails');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000002',true);
update public.friend_profiles set visibility='private' where user_id=auth.uid();
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select pg_temp.ok((select count(*)=0 from public.latest_updated_friend_workouts()),'owner privacy revokes timestamp and workout together');
reset role;
update public.friend_profiles set visibility='friends' where user_id='92000000-0000-4000-8000-000000000002';
set local role authenticated;
delete from public.friend_connections where recipient='92000000-0000-4000-8000-000000000002';
select pg_temp.ok((select count(*)=0 from public.latest_updated_friend_workouts()),'connection withdrawal/block by removal revokes feed immediately');
reset role;
rollback;
