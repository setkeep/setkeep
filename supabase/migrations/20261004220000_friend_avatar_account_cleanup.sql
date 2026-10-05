-- Separate from the unshipped 30-day retention migration. No cron or data sweep.
-- Requires 20261004140000 (avatars) and deployed 20261004180000 (offboarding).
begin;
-- Fail before changing anything if the separately approved avatar schema is absent.
select avatar_path from public.friend_profiles limit 0;
create table public.account_avatar_cleanup (
 user_id uuid primary key references auth.users(id) on delete cascade,
 token_hash text not null check(token_hash ~ '^[0-9a-f]{64}$'),
 attempt uuid not null, lease_until timestamptz not null,
 verified_at timestamptz, requested_at timestamptz not null default clock_timestamp()
);
alter table public.account_avatar_cleanup enable row level security;
revoke all on public.account_avatar_cleanup from public,anon,authenticated,service_role;

-- Lock writes against cleanup preparation. A valid but deleted user's JWT
-- cannot read/write this bucket. Pending cleanup also stops new uploads.
create function public.friend_avatar_access_allowed(p_name text,p_write boolean default false)
returns boolean language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); owner_id uuid;
begin
 if actor is null or p_name is null or p_name !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9]+\.png$' then return false; end if;
 owner_id=split_part(p_name,'/',1)::uuid;
 if p_write then
  if owner_id<>actor then return false; end if;
  -- The pending gate is read AFTER this lock, using a fresh volatile snapshot.
  perform 1 from auth.users where id=actor for key share;
  if not found then return false; end if;
 elsif not exists(select 1 from auth.users where id=actor) then return false;
 end if;
 if not exists(select 1 from auth.users where id=owner_id) or
 exists(select 1 from public.account_avatar_cleanup where user_id in(actor,owner_id)) then return false; end if;
 if not exists(select 1 from public.friend_profiles where user_id=owner_id) then return false; end if;
 if owner_id=actor then return true; end if;
 return not p_write and exists(select 1 from public.friend_profiles
  where user_id=owner_id and avatar_path=p_name and visibility='friends')
  and public.are_friends(actor,owner_id);
end $$;
revoke all on function public.friend_avatar_access_allowed(text,boolean) from public,anon;
grant execute on function public.friend_avatar_access_allowed(text,boolean) to authenticated;
create policy friend_avatar_lifecycle_guard on storage.objects as restrictive for all to authenticated
 using(bucket_id<>'friend-avatars' or public.friend_avatar_access_allowed(name,false))
 with check(bucket_id<>'friend-avatars' or public.friend_avatar_access_allowed(name,true));

create or replace function public.account_deletion_prepare(p_user uuid, p_token_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
  raise exception 'Invalid receipt key';
 end if;
 -- Synchronize with Auth DELETE. No cloud references are changed here.
 perform 1 from auth.users where id=p_user for update;
 if not found then return jsonb_build_object('ready',false,'error','user_missing'); end if;
 if exists(select 1 from public.tenants where billing_owner_id=p_user) then
  return jsonb_build_object('ready',false,'error','tenant_owner_requires_transfer');
 end if;
 -- Opportunistic purge; inactive deployments also need scheduled maintenance.
 delete from public.account_deletion_requests
 where coalesce(completed_at,requested_at)<now()-interval '7 days';
 insert into public.account_deletion_requests(token_hash,user_id)
 values(p_token_hash,p_user) on conflict(token_hash) do nothing;
 if not exists(select 1 from public.account_deletion_requests
  where token_hash=p_token_hash and user_id=p_user) then
  raise exception 'Receipt conflict';
 end if;
 return jsonb_build_object('ready',true,'avatar_cleanup_required',true);
end $$;


create function public.account_avatar_cleanup_begin(p_user uuid,p_token_hash text,p_attempt uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; previous public.account_avatar_cleanup;
begin
 if p_attempt is null then raise exception 'invalid_cleanup_attempt'; end if;
 result=public.account_deletion_prepare(p_user,p_token_hash);
 if result->>'ready'<>'true' then return result; end if;
 -- Do not remove images placed by a different principal or unrelated Storage.
 if exists(select 1 from storage.objects o where bucket_id='friend-avatars' and split_part(name,'/',1)=p_user::text
  and coalesce(to_jsonb(o)->>'owner_id',to_jsonb(o)->>'owner') is distinct from p_user::text) then
  return jsonb_build_object('ready',false,'error','unsupported_avatar_owner');
 end if;
 if exists(select 1 from storage.objects o where coalesce(to_jsonb(o)->>'owner_id',to_jsonb(o)->>'owner')=p_user::text
  and (bucket_id<>'friend-avatars' or split_part(name,'/',1)<>p_user::text)) then
  return jsonb_build_object('ready',false,'error','unsupported_storage_owner');
 end if;
 select * into previous from public.account_avatar_cleanup where user_id=p_user for update;
 if found and previous.attempt<>p_attempt and previous.lease_until>clock_timestamp() then
  return jsonb_build_object('ready',false,'error','avatar_cleanup_in_progress');
 end if;
 insert into public.account_avatar_cleanup(user_id,token_hash,attempt,lease_until)
 values(p_user,p_token_hash,p_attempt,clock_timestamp()+interval '2 minutes')
 on conflict(user_id) do update set token_hash=excluded.token_hash,attempt=excluded.attempt,
 lease_until=excluded.lease_until,verified_at=null;
 return jsonb_build_object('ready',true);
end $$;

create function public.account_avatar_cleanup_check(p_user uuid,p_token_hash text,p_attempt uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform 1 from auth.users where id=p_user for update;
 if not found then return jsonb_build_object('ready',false); end if;
 if exists(select 1 from storage.objects o where bucket_id='friend-avatars' and split_part(name,'/',1)=p_user::text
  and coalesce(to_jsonb(o)->>'owner_id',to_jsonb(o)->>'owner') is distinct from p_user::text) then
  return jsonb_build_object('ready',false); end if;
 update public.account_avatar_cleanup set lease_until=clock_timestamp()+interval '2 minutes'
 where user_id=p_user and token_hash=p_token_hash and attempt=p_attempt and lease_until>clock_timestamp();
 return jsonb_build_object('ready',found);
end $$;
create function public.account_avatar_cleanup_confirm(p_user uuid,p_token_hash text,p_attempt uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform 1 from auth.users where id=p_user for update;
 if not found then return jsonb_build_object('ready',false); end if;
 if exists(select 1 from storage.objects where bucket_id='friend-avatars'
  and split_part(name,'/',1)=p_user::text) then return jsonb_build_object('ready',false); end if;
 update public.account_avatar_cleanup set verified_at=clock_timestamp(),lease_until=clock_timestamp()+interval '2 minutes'
 where user_id=p_user and token_hash=p_token_hash and attempt=p_attempt and lease_until>clock_timestamp();
 return jsonb_build_object('ready',found);
end $$;
-- Failed/aborted attempts release only their own lease. The upload gate remains
-- until a new verified request finishes, or the user explicitly cancels.
create function public.account_avatar_cleanup_release(p_user uuid,p_token_hash text,p_attempt uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform 1 from auth.users where id=p_user for update;
 if not found then return false; end if;
 update public.account_avatar_cleanup set lease_until=clock_timestamp(),verified_at=null
 where user_id=p_user and token_hash=p_token_hash and attempt=p_attempt;
 return found;
end $$;
-- Available for a future UI/support action; it restores no deleted photo bytes.
create function public.cancel_avatar_account_deletion() returns boolean
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null then raise exception using errcode='42501',message='Authentication required'; end if;
 perform 1 from auth.users where id=actor for update;
 if not found then return false; end if;
 delete from public.account_avatar_cleanup where user_id=actor and lease_until<=clock_timestamp();
 return found;
end $$;
revoke all on function public.cancel_avatar_account_deletion() from public,anon;
grant execute on function public.cancel_avatar_account_deletion() to authenticated;

-- Auth success may only follow verified media cleanup. This covers direct
-- dashboard deletion too and preserves existing offboarding's atomic rollback.
create function public.account_avatar_cleanup_auth_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from storage.objects where bucket_id='friend-avatars' and split_part(name,'/',1)=old.id::text)
 or exists(select 1 from public.account_avatar_cleanup where user_id=old.id
  and (verified_at is null or lease_until<=clock_timestamp())) then
  raise exception using errcode='P0001',message='avatar_cleanup_required';
 end if;
 return old;
end $$;
create trigger account_deletion_01_avatar_guard before delete on auth.users
 for each row execute function public.account_avatar_cleanup_auth_guard();
revoke all on function public.account_avatar_cleanup_begin(uuid,text,uuid),
 public.account_avatar_cleanup_check(uuid,text,uuid),public.account_avatar_cleanup_confirm(uuid,text,uuid),
 public.account_avatar_cleanup_release(uuid,text,uuid),public.account_avatar_cleanup_auth_guard()
 from public,anon,authenticated,service_role;
grant execute on function public.account_avatar_cleanup_begin(uuid,text,uuid),
 public.account_avatar_cleanup_check(uuid,text,uuid),public.account_avatar_cleanup_confirm(uuid,text,uuid),
 public.account_avatar_cleanup_release(uuid,text,uuid) to service_role;
commit;
