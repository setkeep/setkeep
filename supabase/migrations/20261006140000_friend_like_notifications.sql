-- Existing likes keep an unknown timestamp. Only new likes become notifications.
-- Workout/liker identities and all visibility decisions stay on the server.
begin;
alter table public.friend_likes add column created_at timestamptz;
alter table public.friend_likes alter column created_at set default clock_timestamp();

create function public.stamp_friend_like() returns trigger
language plpgsql set search_path='' as $$
begin
 new.created_at := clock_timestamp();
 return new;
end $$;
create trigger friend_like_created_at before insert on public.friend_likes
for each row execute function public.stamp_friend_like();
revoke all on function public.stamp_friend_like() from public,anon,authenticated;

create function public.received_friend_likes()
returns table(workout_id uuid,user_id uuid,owner_id uuid,client_id text,
 performed_at timestamptz,created_at timestamptz,display_name text,avatar_path text)
language sql stable security definer set search_path='' as $$
 select w.id,l.user_id,w.user_id,w.client_id,w.performed_at,l.created_at,p.display_name,
 case when public.friend_avatar_access_allowed(p.avatar_path,false) then p.avatar_path else null end
 from public.friend_likes l
 join public.friend_workouts w on w.id=l.workout_id
 join public.friend_profiles p on p.user_id=l.user_id
 join public.friend_profiles owner_profile on owner_profile.user_id=w.user_id
 where w.user_id=auth.uid() and l.user_id<>auth.uid() and l.created_at is not null
 and exists(select 1 from auth.users where id=auth.uid())
 and owner_profile.visibility='friends'
 and public.are_friends(auth.uid(),l.user_id)
 and public.can_read_friend_workout(w.id)
 and not exists(select 1 from public.account_avatar_cleanup where user_id in(auth.uid(),l.user_id))
 order by l.created_at desc,w.id,l.user_id
$$;
revoke all on function public.received_friend_likes() from public,anon;
grant execute on function public.received_friend_likes() to authenticated;
commit;
