-- Non-destructive stop for the new friend write entry points only.
-- Do not DROP tables/columns, revoke earlier APIs, or revert owner consent or
-- visibility: existing codes, comments, tombstones and approved sharing survive.
begin;
do $$
declare entry text; routine regprocedure;
begin
 foreach entry in array array[
  'public.my_friend_invite_code()',
  'public.request_friend_v2(text)',
  'public.acknowledge_mutual_friend_sharing(text)',
  'public.send_friend_comment(uuid,text,uuid)'
 ] loop
  routine=to_regprocedure(entry);
  if routine is not null then
   execute 'revoke all on function '||routine::text||' from public,anon,authenticated';
  end if;
 end loop;
end $$;
commit;
