-- Manual only, after reverting the Edge handler. Never restores deleted data.
-- Refuse BEFORE mutation if successful offboarding made old NOT NULL impossible.
begin;
lock table auth.users in share row exclusive mode;
lock table public.tenant_menus,public.tenant_comments,public.tenant_templates,
 public.tenant_invites in share row exclusive mode;
do $$ begin
 if exists(select 1 from public.tenant_menus where created_by is null or edited_by is null)
 or exists(select 1 from public.tenant_comments where created_by is null or edited_by is null)
 or exists(select 1 from public.tenant_templates where created_by is null)
 or exists(select 1 from public.tenant_invites where created_by is null) then
  raise exception 'Cannot restore NOT NULL after offboarding; keep safety triggers and nullable attribution';
 end if;
 if to_regclass('public.gym_store_reports') is not null then
  lock table public.gym_store_reports in share row exclusive mode;
  if exists(select 1 from public.gym_store_reports where user_id is null) then
   raise exception 'Cannot restore store report authors after offboarding';
  end if;
 end if;
end $$;
drop trigger account_deletion_cleanup on auth.users;
drop trigger account_deletion_complete on auth.users;
drop trigger tenant_invite_terminal_expiry on public.tenant_invites;
drop function public.tenant_invite_terminal_expiry();
drop function public.account_deletion_cleanup();
drop function public.account_deletion_complete();
drop function public.account_deletion_prepare(uuid,text);
drop function public.account_deletion_receipt(text);
drop table public.account_deletion_requests;
alter table public.tenant_menus alter column created_by set not null,
 alter column edited_by set not null;
alter table public.tenant_comments alter column created_by set not null,
 alter column edited_by set not null;
alter table public.tenant_templates alter column created_by set not null;
alter table public.tenant_invites alter column created_by set not null;
alter table if exists public.gym_store_reports alter column user_id set not null;
commit;
