-- No existing records are deleted by applying this migration.
-- Cleanup happens ONLY inside a successful Auth hard-delete transaction.
begin;
alter table public.tenant_menus alter column created_by drop not null,
 alter column edited_by drop not null;
alter table public.tenant_comments alter column created_by drop not null,
 alter column edited_by drop not null;
alter table public.tenant_templates alter column created_by drop not null;
alter table public.tenant_invites alter column created_by drop not null;
-- Installed on catalog deployments; preserve shared reports, erase attribution.
alter table if exists public.gym_store_reports alter column user_id drop not null;

-- Older reissue RPCs set expires_at=now(). Never let that resurrect a terminal
-- invitation for a transaction whose now() predates the reissue.
create function public.tenant_invite_terminal_expiry() returns trigger
language plpgsql set search_path='' as $$
begin
 if old.expires_at='-infinity'::timestamptz then new.expires_at=old.expires_at; end if;
 return new;
end $$;
create trigger tenant_invite_terminal_expiry before update on public.tenant_invites
 for each row execute function public.tenant_invite_terminal_expiry();

-- Not an Auth FK: the completion receipt must survive Auth deletion.
-- Hashes, never bearer tokens. No email, workout data or error payloads.
create table public.account_deletion_requests (
 token_hash text primary key check(token_hash ~ '^[0-9a-f]{64}$'),
 user_id uuid not null,
 completed_at timestamptz,
 requested_at timestamptz not null default clock_timestamp()
);
alter table public.account_deletion_requests enable row level security;
revoke all on public.account_deletion_requests from public, anon, authenticated;

create function public.account_deletion_prepare(p_user uuid, p_token_hash text)
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
 return jsonb_build_object('ready',true);
end $$;

create function public.account_deletion_receipt(p_token_hash text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.account_deletion_requests
  where token_hash=p_token_hash and completed_at is not null
  and completed_at>now()-interval '7 days')
$$;

create function public.account_deletion_cleanup() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 -- Owner deletion must never cascade an organization or its other users.
 if exists(select 1 from public.tenants where billing_owner_id=old.id) then
  raise exception using errcode='P0001', message='tenant_owner_requires_transfer';
 end if;
 -- Same lock used by tenant mutations, invites and consent changes.
 perform 1 from public.tenants t where t.legacy_trainer_id=old.id
  or exists(select 1 from public.tenant_memberships m where m.tenant_id=t.id and m.user_id=old.id)
  or exists(select 1 from public.tenant_clients c where c.tenant_id=t.id and
   (c.linked_user_id=old.id or c.legacy_link_id in
    (select id from public.trainer_client_links where client_id=old.id or trainer_id=old.id)))
  or exists(select 1 from public.tenant_invites i where i.tenant_id=t.id and (i.used_by=old.id or i.created_by=old.id))
  or exists(select 1 from public.tenant_menus m where m.tenant_id=t.id and
   (m.created_by=old.id or m.edited_by=old.id or m.client_read_by=old.id))
  or exists(select 1 from public.tenant_comments c where c.tenant_id=t.id and
   (c.created_by=old.id or c.edited_by=old.id or c.client_read_by=old.id))
  or exists(select 1 from public.tenant_templates p where p.tenant_id=t.id and p.created_by=old.id)
  or exists(select 1 from public.workouts w where w.tenant_id=t.id and w.canceled_by=old.id)
 order by t.id for update;
 -- Recheck after locks: preflight is advisory, this is authoritative.
 if exists(select 1 from public.tenants where billing_owner_id=old.id) then
  raise exception using errcode='P0001', message='tenant_owner_requires_transfer';
 end if;
 -- Expire BEFORE clearing used_by; it must never reopen a consumed invite.
 update public.tenant_invites set expires_at='-infinity'::timestamptz,
  used_by=case when used_by=old.id then null else used_by end,
  created_by=case when created_by=old.id then null else created_by end
 where used_by=old.id or created_by=old.id
  or client_id in(select id from public.tenant_clients where linked_user_id=old.id);

 update public.tenant_clients set linked_user_id=null, status='revoked',
  client_name='退会済みユーザー', share_workouts=false, allow_recording=false,
  share_heatmap=false, share_body_weight=false, consent_at=null
 where linked_user_id=old.id;
 -- Clear legacy bridge before its Auth-driven cascade (also after transfer).
 update public.tenant_clients set legacy_link_id=null where legacy_link_id in
  (select id from public.trainer_client_links where client_id=old.id or trainer_id=old.id);
 delete from public.tenant_assignments where user_id=old.id;
 delete from public.tenant_memberships where user_id=old.id;
 update public.tenants set legacy_trainer_id=null where legacy_trainer_id=old.id;

 -- Keep other clients' organization records; remove Auth attribution only.
 update public.tenant_menus set
  created_by=case when created_by=old.id then null else created_by end,
  edited_by=case when edited_by=old.id then null else edited_by end,
  client_read_by=case when client_read_by=old.id then null else client_read_by end
 where created_by=old.id or edited_by=old.id or client_read_by=old.id;
 update public.tenant_comments set
  created_by=case when created_by=old.id then null else created_by end,
  edited_by=case when edited_by=old.id then null else edited_by end,
  client_read_by=case when client_read_by=old.id then null else client_read_by end
 where created_by=old.id or edited_by=old.id or client_read_by=old.id;
 update public.tenant_templates set created_by=null where created_by=old.id;
 update public.workouts set canceled_by=null where canceled_by=old.id;
 if to_regclass('public.gym_store_reports') is not null then
  update public.gym_store_reports set
   user_id=case when user_id=old.id then null else user_id end,
   reviewed_by=case when reviewed_by=old.id then null else reviewed_by end
  where user_id=old.id or reviewed_by=old.id;
 end if;
 if to_regclass('public.gym_store_changes') is not null then
  update public.gym_store_changes set changed_by=null where changed_by=old.id;
 end if;

 -- AFTER DELETE records success only if all FK cascades succeed.
 return old;
end $$;
create function public.account_deletion_complete() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 update public.account_deletion_requests set completed_at=clock_timestamp()
 where user_id=old.id and completed_at is null;
 return old;
end $$;
create trigger account_deletion_cleanup before delete on auth.users
 for each row execute function public.account_deletion_cleanup();
create trigger account_deletion_complete after delete on auth.users
 for each row execute function public.account_deletion_complete();

revoke all on function public.account_deletion_prepare(uuid,text),
 public.account_deletion_receipt(text), public.account_deletion_cleanup(),
 public.account_deletion_complete(), public.tenant_invite_terminal_expiry() from public,anon,authenticated;
grant execute on function public.account_deletion_prepare(uuid,text),
 public.account_deletion_receipt(text) to service_role;
commit;
