-- Read-only prerequisites. No profile, identity, invite-code or comment content.
begin read only;
do $$
begin
 if to_regprocedure('pg_catalog.sha256(bytea)') is null then
  raise exception 'Required built-in SHA256 unavailable';
 end if;
 if to_regclass('public.friend_profiles') is null or
 to_regclass('public.account_avatar_cleanup') is null or
 to_regprocedure('public.friend_avatar_access_allowed(text,boolean)') is null or
 to_regprocedure('public.sync_friend_workouts(uuid,jsonb,text[],uuid,bigint,boolean)') is null then
  raise exception 'Required deployed friend/avatar/snapshot prerequisites unavailable';
 end if;
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='friend_profiles' and column_name='avatar_path') then
  raise exception 'Avatar profile prerequisite unavailable';
 end if;
 if not exists(select 1 from storage.buckets where id='friend-avatars' and public=false and file_size_limit=524288) then
  raise exception 'Expected private avatar bucket unavailable';
 end if;
end $$;
select
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='friend_profiles' and column_name='sharing_consent_version') as mutual_sharing_migration_present,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='friend_profiles' and column_name='comment_idempotency_version') as comment_retry_migration_present;
rollback;
