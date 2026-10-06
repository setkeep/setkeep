-- New clients publish only records with explicit local sharing provenance.
-- No local history is migrated and no existing snapshots are pruned.
alter table public.friend_profiles
 add column friend_owned_sync_version integer not null default 1
 check (friend_owned_sync_version=1);

create function public.acknowledge_owned_friend_sharing(
 expected_owner uuid, consent_version text
) returns void
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null or expected_owner is distinct from actor then
  raise exception 'Authenticated owner required' using errcode='42501';
 end if;
 if consent_version is distinct from 'privacy-1.2' then
  raise exception 'Consent version unavailable' using errcode='22023';
 end if;
 update public.friend_profiles set visibility='friends',sharing_consent_version=1
 where user_id=actor;
 if not found then raise exception 'Profile unavailable'; end if;
end $$;

create function public.sync_owned_friend_workouts(
 expected_owner uuid, records jsonb, deleted_client_ids text[],
 device_id uuid, revision bigint
) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); sharing_allowed boolean; accepted boolean;
begin
 if actor is null or expected_owner is distinct from actor then
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
 -- Validate every record before metadata, deletion or publication can change.
 if exists(select 1 from jsonb_array_elements(records) r where
  jsonb_typeof(r)<>'object' or
  r->>'friendOwnerUserId' is distinct from actor::text or
  jsonb_typeof(r->'date') is distinct from 'string' or btrim(r->>'date')='' or
  jsonb_typeof(r->'sets') is distinct from 'array' or
  coalesce((r->>'durationSeconds')::integer,0)<0
 ) then raise exception 'Owned workout required' using errcode='22023'; end if;
 perform (r->>'date')::timestamptz from jsonb_array_elements(records) r;
 -- Empty devices never clear an existing owner's social history.
 if jsonb_array_length(records)=0 and cardinality(deleted_client_ids)=0 then
  return jsonb_build_object('accepted',true,'published',false);
 end if;
 select visibility='friends' and sharing_consent_version=1 into sharing_allowed
 from public.friend_profiles where user_id=actor for update;
 if not found then return jsonb_build_object('accepted',false,'published',false); end if;
 insert into public.friend_snapshot_versions(user_id,device_id,stored_revision)
 values(actor,device_id,revision)
 on conflict on constraint friend_snapshot_versions_pkey do update
 set stored_revision=excluded.stored_revision
 where public.friend_snapshot_versions.stored_revision<=excluded.stored_revision
 returning true into accepted;
 if accepted is not true then return jsonb_build_object('accepted',false,'published',false); end if;
 delete from public.friend_workouts
 where user_id=actor and client_id=any(deleted_client_ids);
 -- Retain pre-existing/shared records absent from this device's owned subset.
 -- Private profiles are never enabled or given new workout contents here.
 if sharing_allowed then
  insert into public.friend_workouts(user_id,client_id,performed_at,duration_seconds,sets)
  select actor,r->>'date',(r->>'date')::timestamptz,
   coalesce((r->>'durationSeconds')::integer,0),r->'sets'
  from jsonb_array_elements(records) r
  where not (r->>'date'=any(deleted_client_ids))
  on conflict(user_id,client_id) do update set
   performed_at=excluded.performed_at,duration_seconds=excluded.duration_seconds,sets=excluded.sets;
 end if;
 return jsonb_build_object('accepted',true,'published',sharing_allowed and jsonb_array_length(records)>0);
end $$;

revoke all on function public.acknowledge_owned_friend_sharing(uuid,text),
 public.sync_owned_friend_workouts(uuid,jsonb,text[],uuid,bigint) from public,anon;
grant execute on function public.acknowledge_owned_friend_sharing(uuid,text),
 public.sync_owned_friend_workouts(uuid,jsonb,text[],uuid,bigint) to authenticated;
