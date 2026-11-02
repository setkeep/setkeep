-- Isolated synthetic database only. Not a production verification script.
create role fixture_other nologin;
alter default privileges in schema public grant all on tables to anon,authenticated;
alter default privileges in schema public grant execute on functions to anon,authenticated;
create schema supabase_migrations;
create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[]);
insert into supabase_migrations.schema_migrations values('fixture-unrelated','unrelated',array['select 1']);
create table public.fixture_blocks(viewer uuid,owner uuid);
revoke all on public.fixture_blocks from public,anon,authenticated;
create function public.fixture_not_blocked(owner_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select not exists(select 1 from public.fixture_blocks where viewer=auth.uid() and owner=owner_id)
$$;
revoke all on function public.fixture_not_blocked(uuid) from public,anon;
grant execute on function public.fixture_not_blocked(uuid) to authenticated;
create policy fixture_restrictive_block on public.friend_workouts as restrictive for select
 to authenticated using(public.fixture_not_blocked(user_id));
insert into auth.users(id) select ('92000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,7) n;
insert into public.friend_profiles(user_id,display_name,visibility)
 select id,'Synthetic',case when id='92000000-0000-4000-8000-000000000003' then 'private' else 'friends' end
 from auth.users where id::text like '92000000-%';
insert into public.friend_connections(requester,recipient,status) values
 ('92000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000002','accepted'),
 ('92000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000003','accepted'),
 ('92000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000004','pending'),
 ('92000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000006','accepted'),
 ('92000000-0000-4000-8000-000000000005','92000000-0000-4000-8000-000000000007','accepted');
insert into public.fixture_blocks values('92000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000006');
insert into public.friend_workouts(user_id,client_id,performed_at,duration_seconds,sets)
 select id,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z',60,'[]' from auth.users where id::text like '92000000-%';
insert into public.friend_likes(workout_id,user_id)
 select id,'92000000-0000-4000-8000-000000000001' from public.friend_workouts where user_id='92000000-0000-4000-8000-000000000002';
insert into public.friend_comments(workout_id,user_id,body)
 select id,'92000000-0000-4000-8000-000000000001','Synthetic' from public.friend_workouts where user_id='92000000-0000-4000-8000-000000000002';
create function public.fixture_state() returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object(
'rows',jsonb_build_object('friend_profiles',(select coalesce(jsonb_agg(to_jsonb(t)-'updated_at'-'friend_workout_updates_version' order by (to_jsonb(t)-'updated_at'-'friend_workout_updates_version')::text),'[]'::jsonb) from public.friend_profiles t),'friend_workouts',(select coalesce(jsonb_agg(to_jsonb(t)-'updated_at'-'friend_workout_updates_version' order by (to_jsonb(t)-'updated_at'-'friend_workout_updates_version')::text),'[]'::jsonb) from public.friend_workouts t),'friend_connections',(select coalesce(jsonb_agg(to_jsonb(t)-'updated_at'-'friend_workout_updates_version' order by (to_jsonb(t)-'updated_at'-'friend_workout_updates_version')::text),'[]'::jsonb) from public.friend_connections t),'friend_likes',(select coalesce(jsonb_agg(to_jsonb(t)-'updated_at'-'friend_workout_updates_version' order by (to_jsonb(t)-'updated_at'-'friend_workout_updates_version')::text),'[]'::jsonb) from public.friend_likes t),'friend_comments',(select coalesce(jsonb_agg(to_jsonb(t)-'updated_at'-'friend_workout_updates_version' order by (to_jsonb(t)-'updated_at'-'friend_workout_updates_version')::text),'[]'::jsonb) from public.friend_comments t)),
 'tables',(select jsonb_agg(jsonb_build_array(c.oid::regclass::text,c.relowner,c.relrowsecurity,c.relforcerowsecurity,c.relacl) order by c.relname) from pg_class c where c.oid in('public.friend_profiles'::regclass,'public.friend_workouts'::regclass,'public.friend_connections'::regclass,'public.friend_likes'::regclass,'public.friend_comments'::regclass)),
 'policies',(select jsonb_agg(to_jsonb(p) order by tablename,policyname) from pg_policies p where schemaname='public' and tablename in('friend_profiles','friend_workouts','friend_connections','friend_likes','friend_comments')),
 'functions',(select jsonb_agg(jsonb_build_array(p.oid::regprocedure::text,p.proowner,p.prosecdef,p.proconfig,p.proacl,pg_get_functiondef(p.oid)) order by p.oid::regprocedure::text)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('are_friends','can_read_friend_workout','request_friend','accept_friend','publish_friend_workouts','list_friend_connections','fixture_not_blocked')),
 'columns',(select jsonb_agg(jsonb_build_array(a.attrelid::regclass::text,a.attname,a.atttypid,a.attnotnull,a.attacl,pg_get_expr(d.adbin,d.adrelid)) order by a.attrelid,a.attnum)
  from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid in('public.friend_profiles'::regclass,'public.friend_workouts'::regclass,'public.friend_connections'::regclass,'public.friend_likes'::regclass,'public.friend_comments'::regclass) and a.attnum>0 and not a.attisdropped and a.attname not in('updated_at','friend_workout_updates_version')),
 'constraints',(select jsonb_agg(jsonb_build_array(conrelid::regclass::text,conname,pg_get_constraintdef(oid)) order by conrelid,conname)
  from pg_constraint where conrelid in('public.friend_profiles'::regclass,'public.friend_workouts'::regclass,'public.friend_connections'::regclass,'public.friend_likes'::regclass,'public.friend_comments'::regclass) and conname<>'friend_profiles_friend_workout_updates_version_check'),
 'indexes',(select jsonb_agg(to_jsonb(i) order by tablename,indexname) from pg_indexes i where schemaname='public' and tablename in('friend_profiles','friend_workouts','friend_connections','friend_likes','friend_comments') and indexname<>'friend_workouts_owner_updated'),
 'default_acl',(select coalesce(jsonb_agg(to_jsonb(d) order by oid),'[]'::jsonb) from pg_default_acl d),
 'other_history',(select jsonb_agg(to_jsonb(h) order by version) from supabase_migrations.schema_migrations h where version<>'20261102090000')
 )
$$;
revoke all on function public.fixture_state() from public,anon,authenticated;
create table public.fixture_snapshot(payload jsonb);
revoke all on public.fixture_snapshot from public,anon,authenticated;
insert into public.fixture_snapshot select public.fixture_state();
