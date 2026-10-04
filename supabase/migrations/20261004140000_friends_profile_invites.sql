-- Local draft: apply separately after approval. Existing sharing stays private.
alter table public.friend_profiles add column avatar_path text;
alter table public.friend_profiles add constraint friend_avatar_owner_path check (
  avatar_path is null or avatar_path ~ ('^' || user_id::text || '/[0-9]+\.png$')
);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('friend-avatars','friend-avatars',false,524288,array['image/png']);

create policy friend_avatar_read on storage.objects for select to authenticated using (
  bucket_id='friend-avatars' and (
    (storage.foldername(name))[1]=auth.uid()::text or exists (
      select 1 from public.friend_profiles p where p.avatar_path=name
        and p.visibility='friends' and public.are_friends(auth.uid(),p.user_id)
    )
  )
);
create policy friend_avatar_insert on storage.objects for insert to authenticated with check (
  bucket_id='friend-avatars' and name ~ ('^' || auth.uid()::text || '/[0-9]+\.png$')
);
create policy friend_avatar_update on storage.objects for update to authenticated using (
  bucket_id='friend-avatars' and (storage.foldername(name))[1]=auth.uid()::text
) with check (
  bucket_id='friend-avatars' and name ~ ('^' || auth.uid()::text || '/[0-9]+\.png$')
);
create policy friend_avatar_delete on storage.objects for delete to authenticated using (
  bucket_id='friend-avatars' and (storage.foldername(name))[1]=auth.uid()::text
);

-- Storage policies combine permissive grants with OR. These bucket-specific
-- restrictive guards remain effective even alongside unrelated broad grants.
-- They return true for every other bucket, preserving its existing behavior.
create policy friend_avatar_anon_guard on storage.objects as restrictive for all to anon
using (bucket_id<>'friend-avatars') with check (bucket_id<>'friend-avatars');
create policy friend_avatar_read_guard on storage.objects as restrictive for select to authenticated using (
  bucket_id<>'friend-avatars' or (
    (storage.foldername(name))[1]=auth.uid()::text or exists (
      select 1 from public.friend_profiles p where p.avatar_path=name
        and p.visibility='friends' and public.are_friends(auth.uid(),p.user_id)
    )
  )
);
create policy friend_avatar_insert_guard on storage.objects as restrictive for insert to authenticated with check (
  bucket_id<>'friend-avatars' or name ~ ('^' || auth.uid()::text || '/[0-9]+\.png$')
);
create policy friend_avatar_update_guard on storage.objects as restrictive for update to authenticated using (
  bucket_id<>'friend-avatars' or (storage.foldername(name))[1]=auth.uid()::text
) with check (
  bucket_id<>'friend-avatars' or name ~ ('^' || auth.uid()::text || '/[0-9]+\.png$')
);
create policy friend_avatar_delete_guard on storage.objects as restrictive for delete to authenticated using (
  bucket_id<>'friend-avatars' or (storage.foldername(name))[1]=auth.uid()::text
);

-- Invite possession permits a minimal preview, never workouts or private photos.
create function public.lookup_friend_invite(code uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare target uuid; display text; connection_status text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select user_id,display_name into target,display from friend_profiles where invite_code=code;
  if target is null or target=auth.uid() then raise exception 'Invalid invite code'; end if;
  select status into connection_status from friend_connections
    where (requester=auth.uid() and recipient=target) or (recipient=auth.uid() and requester=target);
  return jsonb_build_object('display_name',display,'status',connection_status);
end $$;

create function public.latest_friend_workouts() returns setof public.friend_workouts
language sql stable security invoker set search_path=public as $$
  select distinct on (user_id) * from friend_workouts where user_id<>auth.uid()
    order by user_id,performed_at desc,id desc
$$;
create index friend_workouts_owner_recent on public.friend_workouts(user_id,performed_at desc);

create function public.list_friend_connections_with_avatar()
returns table(id uuid,requester uuid,recipient uuid,status text,friend_name text,avatar_path text)
language sql stable security definer set search_path=public as $$
  select c.id,c.requester,c.recipient,c.status,p.display_name,
    case when c.status='accepted' and p.visibility='friends' then p.avatar_path else null end
  from friend_connections c join friend_profiles p
    on p.user_id=case when c.requester=auth.uid() then c.recipient else c.requester end
  where auth.uid() in (c.requester,c.recipient) order by c.created_at
$$;
revoke all on function public.lookup_friend_invite(uuid),public.latest_friend_workouts(),public.list_friend_connections_with_avatar() from public,anon;
grant execute on function public.lookup_friend_invite(uuid),public.latest_friend_workouts(),public.list_friend_connections_with_avatar() to authenticated;
