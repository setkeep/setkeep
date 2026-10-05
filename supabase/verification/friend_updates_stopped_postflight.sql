-- Read-only check after the non-destructive stop. No user-data output.
begin read only;
do $$
declare entry text; routine regprocedure;
begin
 foreach entry in array array['public.my_friend_invite_code()','public.request_friend_v2(text)','public.acknowledge_mutual_friend_sharing(text)','public.send_friend_comment(uuid,text,uuid)'] loop
  routine=to_regprocedure(entry);
  if routine is not null and (has_function_privilege('authenticated',routine,'EXECUTE') or has_function_privilege('anon',routine,'EXECUTE')) then
   raise exception 'New write API still enabled: %',entry;
  end if;
 end loop;
 foreach entry in array array['public.lookup_friend_invite_v2(text)','public.friend_comment_thread(uuid)','public.friend_liker_avatars(uuid)','public.request_friend(uuid)','public.accept_friend(uuid)'] loop
  routine=to_regprocedure(entry);
  if routine is null or not has_function_privilege('authenticated',routine,'EXECUTE') or has_function_privilege('anon',routine,'EXECUTE') then
   raise exception 'Expected existing/read API grants unavailable: %',entry;
  end if;
 end loop;
 if not (has_table_privilege('authenticated','public.friend_comments','SELECT') and
         has_table_privilege('authenticated','public.friend_comments','INSERT') and
         has_table_privilege('authenticated','public.friend_comments','DELETE')) then
  raise exception 'Legacy comment endpoint grants unavailable';
 end if;
end $$;
select true as new_friend_writes_stopped_existing_apis_preserved;
rollback;
