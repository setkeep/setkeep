-- Use only after approval to resume the stopped APIs. Do not reapply CREATE
-- migrations or update owner visibility/consent, codes, comments or receipts.
begin;
grant execute on function public.my_friend_invite_code() to authenticated;
grant execute on function public.request_friend_v2(text) to authenticated;
grant execute on function public.acknowledge_mutual_friend_sharing(text) to authenticated;
grant execute on function public.send_friend_comment(uuid,text,uuid) to authenticated;
commit;
