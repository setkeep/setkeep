-- Read-only catalog checks; no application rows, identities or invite codes.
begin read only;
set local lock_timeout='2s';
set local statement_timeout='15s';
do $$ begin
 if current_setting('server_version_num')::integer<110000 then
  raise exception 'Review constant-default column locking on this PostgreSQL version'; end if;
 if to_regclass('public.friend_profiles') is null or to_regclass('public.friend_workouts') is null or
    to_regprocedure('auth.uid()') is null then raise exception 'Friends MVP prerequisites missing'; end if;
 if exists(select 1 from pg_attribute where not attisdropped and
  ((attrelid='public.friend_workouts'::regclass and attname='updated_at') or
   (attrelid='public.friend_profiles'::regclass and attname='friend_workout_updates_version'))) or
  to_regprocedure('public.latest_updated_friend_workouts()') is not null or
  to_regprocedure('public.stamp_friend_workout_update()') is not null or
  to_regclass('public.friend_workouts_owner_updated') is not null or
  exists(select 1 from pg_trigger where tgrelid='public.friend_workouts'::regclass
   and tgname='friend_workout_updated_at') then
  raise exception 'Candidate name collision or partial apply; stop, do not rerun'; end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') or
    not exists(select 1 from pg_roles where rolname='anon') then raise exception 'Expected roles missing'; end if;
 if exists(select 1 from pg_class where oid in('public.friend_profiles'::regclass,'public.friend_workouts'::regclass)
  and (not relrowsecurity or relkind<>'r')) then raise exception 'Expected RLS tables unavailable'; end if;
end $$;
select current_setting('server_version') as server_version,transaction_read_only from
 (select current_setting('transaction_read_only') as transaction_read_only) s;
select c.oid::regclass::text as relation,c.reltuples as estimated_rows,
 pg_total_relation_size(c.oid) as total_bytes,c.relrowsecurity,c.relforcerowsecurity,c.relacl
from pg_class c where c.oid in('public.friend_profiles'::regclass,'public.friend_workouts'::regclass);
select l.relation::regclass::text as relation,l.mode,l.granted,l.pid,
 a.wait_event_type,a.wait_event,clock_timestamp()-a.xact_start as transaction_age
from pg_locks l left join pg_stat_activity a using(pid)
where l.relation in('public.friend_profiles'::regclass,'public.friend_workouts'::regclass)
order by l.relation,l.pid,l.mode;
rollback;
