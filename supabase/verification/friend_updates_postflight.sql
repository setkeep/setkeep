-- Read-only metadata assertions after both migrations; no user-data output.
begin read only;
do $$
declare entry text; routine regprocedure; relation text;
begin
 foreach relation in array array['friend_invite_codes','friend_invite_limits','friend_comment_operations'] loop
  if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname=relation and c.relrowsecurity) then
   raise exception 'Private table RLS unavailable: %',relation;
  end if;
  if has_table_privilege('anon','public.'||relation,'SELECT,INSERT,UPDATE,DELETE') or
     has_table_privilege('authenticated','public.'||relation,'SELECT,INSERT,UPDATE,DELETE') then
   raise exception 'Private table grant too broad: %',relation;
  end if;
 end loop;
 foreach entry in array array[
  'public.my_friend_invite_code()','public.lookup_friend_invite_v2(text)',
  'public.request_friend_v2(text)','public.acknowledge_mutual_friend_sharing(text)',
  'public.friend_comment_thread(uuid)','public.friend_liker_avatars(uuid)',
  'public.send_friend_comment(uuid,text,uuid)'
 ] loop
  routine=to_regprocedure(entry);
  if routine is null then raise exception 'Required API unavailable: %',entry; end if;
  if not has_function_privilege('authenticated',routine,'EXECUTE') or has_function_privilege('anon',routine,'EXECUTE') then
   raise exception 'Unexpected API execute grants: %',entry;
  end if;
 end loop;
 foreach entry in array array['public.generate_friend_short_code()','public.resolve_friend_invite(text)','public.friend_invite_attempt_allowed()','public.friend_comment_operation_deleted()'] loop
  routine=to_regprocedure(entry);
  if routine is null or has_function_privilege('anon',routine,'EXECUTE') or has_function_privilege('authenticated',routine,'EXECUTE') then
   raise exception 'Internal function exposed/unavailable: %',entry;
  end if;
 end loop;
 if not exists(select 1 from pg_trigger where tgrelid='public.friend_comments'::regclass and tgname='friend_comment_operation_deleted' and tgenabled='O') then
  raise exception 'Comment deletion receipt guard unavailable';
 end if;
end $$;
select true as friend_updates_metadata_verified;
rollback;
