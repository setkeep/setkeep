-- Candidate rollback only. Requires separate approval before production use.
-- Drops only the additions from 20261102090000; never use CASCADE.
-- updated_at metadata is lost. Shared content/consent/relationships remain.
begin;
set local lock_timeout='2s';
set local statement_timeout='60s';
do $$
declare workout_att smallint; capability_att smallint; capability_check oid;
 history_present boolean; history_name text; history_hash text;
begin
 if to_regprocedure('public.latest_updated_friend_workouts()') is null or
    to_regprocedure('public.stamp_friend_workout_update()') is null or
    to_regclass('public.friend_workouts_owner_updated') is null then
  raise exception 'Expected candidate objects missing; stop and inspect';
 end if;
 if not exists(select 1 from pg_proc where oid='public.latest_updated_friend_workouts()'::regprocedure
   and not prosecdef and md5(prosrc)='0fed6dc71cfa6d4b5a3b3df33ac87490') or
    not exists(select 1 from pg_proc where oid='public.stamp_friend_workout_update()'::regprocedure
   and not prosecdef and md5(prosrc)='c2f207092b19441ec39ebded6791b883') then
  raise exception 'Candidate function drift; do not drop';
 end if;
 select attnum into workout_att from pg_attribute
 where attrelid='public.friend_workouts'::regclass and attname='updated_at'
 and not attisdropped and atttypid='timestamptz'::regtype and not attnotnull and not atthasdef;
 select attnum into capability_att from pg_attribute
 where attrelid='public.friend_profiles'::regclass and attname='friend_workout_updates_version'
 and not attisdropped and atttypid='integer'::regtype and attnotnull;
 if workout_att is null or capability_att is null or not exists(
  select 1 from pg_attrdef where adrelid='public.friend_profiles'::regclass
  and adnum=capability_att and pg_get_expr(adbin,adrelid)='1'
 ) then raise exception 'Candidate column drift; do not drop'; end if;
 select oid into capability_check from pg_constraint
 where conrelid='public.friend_profiles'::regclass
 and conname='friend_profiles_friend_workout_updates_version_check'
 and pg_get_constraintdef(oid)='CHECK ((friend_workout_updates_version = 1))';
 if capability_check is null or not exists(
  select 1 from pg_trigger where tgrelid='public.friend_workouts'::regclass
  and tgname='friend_workout_updated_at' and not tgisinternal and tgtype=23
  and tgfoid='public.stamp_friend_workout_update()'::regprocedure
 ) or pg_get_indexdef('public.friend_workouts_owner_updated'::regclass)<>
  'CREATE INDEX friend_workouts_owner_updated ON public.friend_workouts USING btree (user_id, updated_at DESC NULLS LAST, performed_at DESC, id DESC)' then
  raise exception 'Candidate trigger/index/check drift; do not drop';
 end if;
 -- DROP COLUMN can automatically remove indexes/checks even without CASCADE.
 -- Refuse any extra dependency, including objects added by another feature.
 if exists(
  select 1 from pg_depend d where d.refclassid='pg_class'::regclass and (
   (d.refobjid='public.friend_workouts'::regclass and d.refobjsubid=workout_att) or
   (d.refobjid='public.friend_profiles'::regclass and d.refobjsubid=capability_att)
  ) and not (
   (d.classid='pg_class'::regclass and d.objid='public.friend_workouts_owner_updated'::regclass) or
   (d.classid='pg_constraint'::regclass and d.objid=capability_check) or
   (d.classid='pg_attrdef'::regclass and exists(select 1 from pg_attrdef a
     where a.oid=d.objid and a.adrelid='public.friend_profiles'::regclass and a.adnum=capability_att))
  )
 ) then raise exception 'Unrelated dependency on candidate columns; do not drop'; end if;
 if to_regclass('supabase_migrations.schema_migrations') is not null then
  execute 'select exists(select 1 from supabase_migrations.schema_migrations where version=$1)'
   into history_present using '20261102090000';
  if history_present then
   execute 'select name,md5(coalesce(array_to_string(statements,E''\n''),''''))
    from supabase_migrations.schema_migrations where version=$1'
    into history_name,history_hash using '20261102090000';
   if history_name is distinct from 'friend_workout_updates' or
      history_hash is distinct from '82700c455b56b970c90ed33b16618f6c' then
    raise exception 'Migration history differs from prepared source; do not delete';
   end if;
  end if;
 end if;
end $$;
drop function public.latest_updated_friend_workouts();
drop trigger friend_workout_updated_at on public.friend_workouts;
drop function public.stamp_friend_workout_update();
drop index public.friend_workouts_owner_updated;
alter table public.friend_workouts drop column updated_at;
alter table public.friend_profiles drop column friend_workout_updates_version;
do $$ begin
 if to_regclass('supabase_migrations.schema_migrations') is not null then
  execute 'delete from supabase_migrations.schema_migrations where version=$1'
   using '20261102090000';
 end if;
end $$;
notify pgrst,'reload schema';
commit;
