-- Read-only: confirms just the candidate additions are gone.
begin read only;
do $$ begin
 if to_regprocedure('public.latest_updated_friend_workouts()') is not null or
    to_regprocedure('public.stamp_friend_workout_update()') is not null or
    to_regclass('public.friend_workouts_owner_updated') is not null or
    exists(select 1 from pg_trigger where tgrelid='public.friend_workouts'::regclass and tgname='friend_workout_updated_at') or
    exists(select 1 from pg_attribute where not attisdropped and
     ((attrelid='public.friend_workouts'::regclass and attname='updated_at') or
      (attrelid='public.friend_profiles'::regclass and attname='friend_workout_updates_version'))) then
  raise exception 'Candidate objects remain'; end if;
 if to_regprocedure('public.publish_friend_workouts(jsonb)') is null or
    to_regprocedure('public.list_friend_connections()') is null or
    not has_function_privilege('authenticated','public.publish_friend_workouts(jsonb)','execute') or
    exists(select 1 from pg_class where oid in('public.friend_profiles'::regclass,'public.friend_workouts'::regclass)
     and not relrowsecurity) then raise exception 'Existing friend APIs or RLS unavailable'; end if;
end $$;
select 'candidate objects removed; legacy API/RLS retained' as result;
rollback;
