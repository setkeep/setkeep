-- Read-only health check, safe for production metadata. No user rows.
begin read only;
set local statement_timeout='15s';
do $$ begin
 if not exists(select 1 from pg_attribute where attrelid='public.friend_workouts'::regclass
  and attname='updated_at' and not attisdropped and atttypid='timestamptz'::regtype
  and not attnotnull and not atthasdef) then raise exception 'Unexpected timestamp column'; end if;
 if not exists(select 1 from pg_attribute where attrelid='public.friend_profiles'::regclass
  and attname='friend_workout_updates_version' and not attisdropped and attnotnull
  and atttypid='integer'::regtype) then raise exception 'Capability column missing'; end if;
 if not exists(select 1 from pg_proc where oid='public.latest_updated_friend_workouts()'::regprocedure
  and not prosecdef and md5(prosrc)='0fed6dc71cfa6d4b5a3b3df33ac87490') or
    not exists(select 1 from pg_proc where oid='public.stamp_friend_workout_update()'::regprocedure
  and not prosecdef and md5(prosrc)='c2f207092b19441ec39ebded6791b883') then
  raise exception 'Unexpected candidate function'; end if;
 if not has_function_privilege('authenticated','public.latest_updated_friend_workouts()','execute') or
    has_function_privilege('anon','public.latest_updated_friend_workouts()','execute') or
    has_function_privilege('authenticated','public.stamp_friend_workout_update()','execute') then
  raise exception 'Unexpected candidate execute permissions'; end if;
 if has_column_privilege('authenticated','public.friend_workouts','updated_at','update') or
    has_table_privilege('authenticated','public.friend_workouts','insert') or
    has_table_privilege('authenticated','public.friend_workouts','delete') then
  raise exception 'Unexpected shared workout write privileges'; end if;
 if not exists(select 1 from pg_trigger where tgrelid='public.friend_workouts'::regclass
  and tgname='friend_workout_updated_at' and tgenabled='O' and tgtype=23
  and tgfoid='public.stamp_friend_workout_update()'::regprocedure) then
  raise exception 'Candidate trigger unavailable'; end if;
 if not exists(select 1 from pg_index where indexrelid='public.friend_workouts_owner_updated'::regclass
  and indisvalid and indisready) then raise exception 'Candidate index unavailable'; end if;
 if exists(select 1 from pg_class where oid in('public.friend_profiles'::regclass,'public.friend_workouts'::regclass)
  and not relrowsecurity) then raise exception 'RLS missing'; end if;
end $$;
select 'candidate catalog health passed' as result;
rollback;
