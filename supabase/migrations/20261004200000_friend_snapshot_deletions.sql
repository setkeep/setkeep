-- Only per-device ordering metadata; no workout contents or sharing choice.
create table public.friend_snapshot_versions (
 user_id uuid not null references auth.users(id) on delete cascade,
 device_id uuid not null,
 stored_revision bigint not null check(stored_revision>=0),
 primary key(user_id,device_id)
);
alter table public.friend_snapshot_versions enable row level security;
revoke all on public.friend_snapshot_versions from public,anon,authenticated;
grant all on public.friend_snapshot_versions to service_role;

-- Owner-bound, retryable deletions work even when sharing is private.
-- Leave the deployed publish RPC and all sharing/RLS choices compatible.
create function public.sync_friend_workouts(
 expected_owner uuid, records jsonb, deleted_client_ids text[],
 device_id uuid, revision bigint, publish_snapshot boolean default true
) returns void
language plpgsql security definer set search_path=public as $$
declare owner_id uuid := auth.uid(); filtered jsonb; accepted boolean;
begin
 if owner_id is null or expected_owner is distinct from owner_id then
  raise exception 'Authenticated owner required' using errcode='42501';
 end if;
 if device_id is null or revision is null or revision<0 then
  raise exception 'Device and nonnegative revision required' using errcode='22023';
 end if;
 if records is null or jsonb_typeof(records)<>'array' then
  raise exception 'Array required' using errcode='22023';
 end if;
 if deleted_client_ids is null or exists(
  select 1 from unnest(deleted_client_ids) id where id is null or btrim(id)=''
 ) then raise exception 'Deletion IDs required' using errcode='22023'; end if;
 -- Serialize with owner profile changes; never change visibility ourselves.
 perform 1 from public.friend_profiles where user_id=owner_id for update;
 -- Responses can be lost while a request is still running on the server.
 -- Older publication/deletion requests must not override a newer delete/Undo.
 insert into public.friend_snapshot_versions(user_id,device_id,stored_revision)
 values(owner_id,device_id,revision)
 on conflict on constraint friend_snapshot_versions_pkey do update
 set stored_revision=excluded.stored_revision
 where public.friend_snapshot_versions.stored_revision<=excluded.stored_revision
 returning true into accepted;
 if accepted is not true then return; end if;
 delete from public.friend_workouts
 where user_id=owner_id and client_id=any(deleted_client_ids);
 select coalesce(jsonb_agg(value),'[]'::jsonb) into filtered
 from jsonb_array_elements(records)
 where not (value->>'date'=any(deleted_client_ids));
 -- Existing RPC publishes only with explicit friends visibility. In private
 -- mode only the exact requested IDs above are deleted, without new uploads.
 if publish_snapshot then perform public.publish_friend_workouts(filtered); end if;
end $$;
revoke all on function public.sync_friend_workouts(uuid,jsonb,text[],uuid,bigint,boolean) from public,anon;
grant execute on function public.sync_friend_workouts(uuid,jsonb,text[],uuid,bigint,boolean) to authenticated;
