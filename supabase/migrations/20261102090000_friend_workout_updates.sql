-- Candidate only: deploy separately before enabling update-time ordering.
-- Existing rows retain unknown update times; do not invent historical activity.
begin;
alter table public.friend_workouts add column updated_at timestamptz;
alter table public.friend_profiles
 add column friend_workout_updates_version integer not null default 1
 check (friend_workout_updates_version=1);

create function public.stamp_friend_workout_update() returns trigger
language plpgsql set search_path='' as $$
begin
 -- A batch is one shared update, not a sequence determined by row order.
 if tg_op='INSERT' then
  new.updated_at=statement_timestamp();
 elsif row(new.performed_at,new.duration_seconds,new.sets)
       is distinct from row(old.performed_at,old.duration_seconds,old.sets) then
  new.updated_at=statement_timestamp();
 else
  new.updated_at=old.updated_at;
 end if;
 return new;
end $$;
revoke all on function public.stamp_friend_workout_update() from public,anon,authenticated;
create trigger friend_workout_updated_at before insert or update
 on public.friend_workouts for each row execute function public.stamp_friend_workout_update();

-- Only surviving, currently authorized shared rows contribute to ordering.
-- Deletion/private/removed relationships never leave an activity side channel.
create function public.latest_updated_friend_workouts()
returns setof public.friend_workouts
language sql stable security invoker set search_path='' as $$
 select distinct on (f.user_id) f.* from public.friend_workouts f
 where f.user_id<>auth.uid()
 order by f.user_id,f.updated_at desc nulls last,f.performed_at desc,f.id desc
$$;
revoke all on function public.latest_updated_friend_workouts() from public,anon;
grant execute on function public.latest_updated_friend_workouts() to authenticated;
create index friend_workouts_owner_updated on public.friend_workouts
 (user_id,updated_at desc nulls last,performed_at desc,id desc);
commit;
