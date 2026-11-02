-- Operational metadata only. Do not add SELECTs of application rows.
begin read only;
set local statement_timeout='15s';
select table_name,column_name,data_type,is_nullable,column_default from information_schema.columns
where table_schema='public' and table_name in('friend_profiles','friend_workouts','friend_connections','friend_likes','friend_comments')
order by table_name,ordinal_position;
select schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check from pg_policies
where schemaname='public' and tablename in('friend_profiles','friend_workouts','friend_connections','friend_likes','friend_comments')
order by tablename,policyname;
select c.oid::regclass::text as relation,c.relowner::regrole::text as owner,
 c.relrowsecurity,c.relforcerowsecurity,c.relacl from pg_class c
where c.oid in('public.friend_profiles'::regclass,'public.friend_workouts'::regclass,
 'public.friend_connections'::regclass,'public.friend_likes'::regclass,'public.friend_comments'::regclass);
select p.oid::regprocedure::text as routine,p.prosecdef,p.proconfig,p.proacl,md5(p.prosrc) as body_md5,
 pg_get_functiondef(p.oid) as definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in('are_friends','can_read_friend_workout','publish_friend_workouts',
 'sync_friend_workouts','sync_owned_friend_workouts','latest_friend_workouts','list_friend_connections',
 'list_friend_connections_with_avatar','stamp_friend_workout_update','latest_updated_friend_workouts')
order by p.oid::regprocedure::text;
select tgname,pg_get_triggerdef(oid) as definition from pg_trigger
where tgrelid='public.friend_workouts'::regclass and not tgisinternal;
select indexname,indexdef from pg_indexes where schemaname='public' and tablename in('friend_profiles','friend_workouts');
select column_name,data_type from information_schema.columns
where table_schema='supabase_migrations' and table_name='schema_migrations' order by ordinal_position;
-- Function names only: potential dynamic-SQL dependencies require review too.
select p.oid::regprocedure::text as possible_update_dependency from pg_proc p
join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
and p.prosrc ilike '%friend_workouts%' and p.prosrc ilike '%updated_at%';
rollback;
