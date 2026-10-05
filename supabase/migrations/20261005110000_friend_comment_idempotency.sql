-- Local draft: approved separately before the new comment composer is enabled.
-- Keeps the legacy comment INSERT API and existing rows/RLS compatible.
begin;
select sharing_consent_version from public.friend_profiles limit 0;
alter table public.friend_profiles add column comment_idempotency_version integer not null default 1 check(comment_idempotency_version in(0,1));
create table public.friend_comment_operations (
 user_id uuid not null references auth.users(id) on delete cascade,
 operation_id uuid not null,
 workout_id uuid not null references public.friend_workouts(id) on delete cascade,
 body_hash bytea not null check(octet_length(body_hash)=32),
 comment_id uuid references public.friend_comments(id) on delete set null,
 deleted boolean not null default false,
 primary key(user_id,operation_id)
);
alter table public.friend_comment_operations enable row level security;
revoke all on public.friend_comment_operations from public,anon,authenticated;

-- Tombstones survive comment deletion. They retain only a hash, no deleted body,
-- and cascade away when its account or workout is deleted.
create function public.friend_comment_operation_deleted() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 -- Auth/workout cascade may delete the parent before this trigger fires.
 -- Remove its now-unneeded receipt instead of updating a dangling FK row.
 delete from public.friend_comment_operations o where o.comment_id=old.id and (
  not exists(select 1 from auth.users where id=o.user_id) or
  not exists(select 1 from public.friend_workouts where id=o.workout_id)
 );
 update public.friend_comment_operations set deleted=true,comment_id=null where comment_id=old.id;
 return old;
end $$;
revoke all on function public.friend_comment_operation_deleted() from public,anon,authenticated;
create trigger friend_comment_operation_deleted before delete on public.friend_comments
 for each row execute function public.friend_comment_operation_deleted();

create function public.send_friend_comment(target_workout_id uuid,body text,operation_id uuid) returns uuid
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); text_body text:=btrim(body); operation public.friend_comment_operations;
 new_id uuid; fingerprint bytea;
begin
 if actor is null or not exists(select 1 from auth.users where id=actor) or
 not public.can_read_friend_workout(target_workout_id) then
  raise exception 'Comment unavailable' using errcode='42501';
 end if;
 if operation_id is null or text_body is null or char_length(text_body) not between 1 and 140 or
 text_body !~ '[^[:space:]]' then raise exception 'Comment unavailable' using errcode='22023'; end if;
 fingerprint=sha256(convert_to(text_body,'UTF8'));
 insert into public.friend_comment_operations(user_id,operation_id,workout_id,body_hash)
 values(actor,operation_id,target_workout_id,fingerprint) on conflict do nothing;
 -- Serializes same-operation retries across devices/requests.
 select * into operation from public.friend_comment_operations
 where user_id=actor and friend_comment_operations.operation_id=send_friend_comment.operation_id for update;
 -- A concurrent receipt lock may have delayed this request while friendship,
 -- visibility or the account was revoked. Recheck with a fresh snapshot.
 if not exists(select 1 from auth.users where id=actor) or
 not public.can_read_friend_workout(target_workout_id) then
  raise exception 'Comment unavailable' using errcode='42501';
 end if;
 if operation.workout_id is distinct from target_workout_id or operation.body_hash is distinct from fingerprint or operation.deleted then
  raise exception 'Comment operation unavailable' using errcode='22023';
 end if;
 if operation.comment_id is not null then
  if exists(select 1 from public.friend_comments where id=operation.comment_id and user_id=actor and workout_id=target_workout_id) then
   return operation.comment_id;
  end if;
  raise exception 'Comment operation unavailable' using errcode='22023';
 end if;
 insert into public.friend_comments(workout_id,user_id,body) values(target_workout_id,actor,text_body) returning id into new_id;
 update public.friend_comment_operations set comment_id=new_id
 where user_id=actor and friend_comment_operations.operation_id=send_friend_comment.operation_id;
 return new_id;
end $$;
revoke all on function public.send_friend_comment(uuid,text,uuid) from public,anon;
grant execute on function public.send_friend_comment(uuid,text,uuid) to authenticated;
commit;
