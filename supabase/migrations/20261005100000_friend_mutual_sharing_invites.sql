-- Local draft. Deploy separately after approval, before enabling the new app.
-- No existing owner's sharing choice is changed by this migration.
begin;
select avatar_path from public.friend_profiles limit 0;
select user_id from public.account_avatar_cleanup limit 0;
alter table public.friend_profiles add column sharing_consent_version integer not null default 0
  check (sharing_consent_version in (0,1));

create table public.friend_invite_codes (
 user_id uuid primary key references public.friend_profiles(user_id) on delete cascade,
 short_code text not null unique check(short_code ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$'),
 created_at timestamptz not null default now()
);
create table public.friend_invite_limits (
 user_id uuid primary key references auth.users(id) on delete cascade,
 minute_start timestamptz not null, minute_count integer not null,
 day_start date not null, day_count integer not null
);
alter table public.friend_invite_codes enable row level security;
alter table public.friend_invite_limits enable row level security;
revoke all on public.friend_invite_codes, public.friend_invite_limits from public,anon,authenticated;

-- UUID v4 uses the PostgreSQL cryptographic random source. Skip its fixed
-- version/variant bytes, then use rejection sampling for the 31-symbol alphabet.
create function public.generate_friend_short_code() returns text
language plpgsql volatile set search_path='' as $$
declare alphabet text:='ABCDEFGHJKMNPQRSTUVWXYZ23456789'; bytes bytea; i integer; n integer; result text:='';
begin
 while length(result)<8 loop
  bytes=decode(replace(gen_random_uuid()::text,'-',''),'hex');
  for i in 0..15 loop
   if i in(6,8) then continue; end if;
   n=get_byte(bytes,i);
   if n<248 then result=result||substr(alphabet,(n%31)+1,1); end if;
   if length(result)=8 then return result; end if;
  end loop;
 end loop;
 return result;
end $$;
revoke all on function public.generate_friend_short_code() from public,anon,authenticated;

create function public.my_friend_invite_code() returns text
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); result text; attempts integer:=0;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 -- Serialize code creation for this owner, including concurrent devices.
 perform 1 from public.friend_profiles where user_id=actor for update;
 if not found then raise exception 'Profile unavailable'; end if;
 select short_code into result from public.friend_invite_codes where user_id=actor;
 if result is not null then return result; end if;
 loop
  attempts=attempts+1;
  if attempts>64 then raise exception 'Invite unavailable'; end if;
  begin
   result=public.generate_friend_short_code();
   insert into public.friend_invite_codes(user_id,short_code) values(actor,result);
   return result;
  exception when unique_violation then
   -- An independently generated code collided. Retry; never reuse its owner.
  end;
 end loop;
end $$;

-- Invalid attempts return a value, not an exception: the rate-limit write must
-- commit even for bad/self/unknown codes. A rejected request cannot roll it back.
create function public.friend_invite_attempt_allowed() returns boolean
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); stamp timestamptz:=clock_timestamp(); counts public.friend_invite_limits;
begin
 if actor is null or not exists(select 1 from auth.users where id=actor) or
 not exists(select 1 from public.friend_profiles where user_id=actor) then return false; end if;
 insert into public.friend_invite_limits(user_id,minute_start,minute_count,day_start,day_count)
 values(actor,stamp,0,(stamp at time zone 'UTC')::date,0) on conflict(user_id) do nothing;
 select * into counts from public.friend_invite_limits where user_id=actor for update;
 if stamp>=counts.minute_start+interval '1 minute' then counts.minute_start=stamp; counts.minute_count=0; end if;
 if counts.day_start<>(stamp at time zone 'UTC')::date then counts.day_start=(stamp at time zone 'UTC')::date; counts.day_count=0; end if;
 counts.minute_count=least(counts.minute_count+1,21);
 counts.day_count=least(counts.day_count+1,101);
 update public.friend_invite_limits set minute_start=counts.minute_start,minute_count=counts.minute_count,
 day_start=counts.day_start,day_count=counts.day_count where user_id=actor;
 return counts.minute_count<=20 and counts.day_count<=100;
end $$;
revoke all on function public.friend_invite_attempt_allowed() from public,anon,authenticated;

create function public.resolve_friend_invite(code text) returns uuid
language plpgsql stable security definer set search_path='' as $$
declare result uuid; normalized text:=upper(btrim(code));
begin
 if code is null or length(code)>64 then return null; end if;
 if normalized ~ '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$' then
  select user_id into result from public.friend_profiles where invite_code=normalized::uuid;
 elsif normalized ~ '^([ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}|[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}-[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4})$' then
  select user_id into result from public.friend_invite_codes where short_code=replace(normalized,'-','');
 end if;
 return result;
end $$;
revoke all on function public.resolve_friend_invite(text) from public,anon,authenticated;

create function public.lookup_friend_invite_v2(code text) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); target uuid; display text; connection_status text;
begin
 if not public.friend_invite_attempt_allowed() then return jsonb_build_object('ok',false,'error','invite_unavailable'); end if;
 target=public.resolve_friend_invite(code);
 if target is null or target=actor then return jsonb_build_object('ok',false,'error','invite_unavailable'); end if;
 select display_name into display from public.friend_profiles where user_id=target;
 select status into connection_status from public.friend_connections
 where (requester=actor and recipient=target) or (recipient=actor and requester=target);
 return jsonb_build_object('ok',true,'display_name',display,'status',connection_status);
end $$;

create function public.request_friend_v2(code text) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); target uuid; connection_status text;
begin
 if not public.friend_invite_attempt_allowed() then return jsonb_build_object('ok',false,'error','invite_unavailable'); end if;
 target=public.resolve_friend_invite(code);
 if target is null or target=actor then return jsonb_build_object('ok',false,'error','invite_unavailable'); end if;
 -- A request never approves a reciprocal pending connection automatically.
 insert into public.friend_connections(requester,recipient) values(actor,target) on conflict do nothing;
 select status into connection_status from public.friend_connections
 where (requester=actor and recipient=target) or (recipient=actor and requester=target);
 return jsonb_build_object('ok',true,'status',connection_status);
end $$;

create function public.acknowledge_mutual_friend_sharing(consent_version text) returns void
language plpgsql volatile security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if consent_version is distinct from 'privacy-1.2' then raise exception 'Consent version unavailable'; end if;
 update public.friend_profiles set visibility='friends',sharing_consent_version=1 where user_id=auth.uid();
 if not found then raise exception 'Profile unavailable'; end if;
end $$;

-- These APIs are scoped to the original workout. They do not create a DM,
-- copy a thread, or expose an unrelated participant's private profile/photo.
create function public.friend_comment_thread(target_workout_id uuid)
returns table(id uuid,workout_id uuid,user_id uuid,body text,created_at timestamptz,display_name text,avatar_path text)
language sql stable security definer set search_path='' as $$
 select c.id,c.workout_id,c.user_id,c.body,c.created_at,
 case when c.user_id=auth.uid() or public.are_friends(auth.uid(),c.user_id) then p.display_name else null end,
 case when public.friend_avatar_access_allowed(p.avatar_path,false) then p.avatar_path else null end
 from public.friend_comments c left join public.friend_profiles p on p.user_id=c.user_id
 where c.workout_id=$1 and exists(select 1 from auth.users where id=auth.uid())
 and public.can_read_friend_workout($1) order by c.created_at,c.id
$$;
create function public.friend_liker_avatars(target_workout_id uuid)
returns table(user_id uuid,avatar_path text)
language sql stable security definer set search_path='' as $$
 select l.user_id,case when public.friend_avatar_access_allowed(p.avatar_path,false) then p.avatar_path else null end
 from public.friend_likes l left join public.friend_profiles p on p.user_id=l.user_id
 where l.workout_id=$1 and exists(select 1 from auth.users where id=auth.uid())
 and public.can_read_friend_workout($1) order by l.user_id
$$;
revoke all on function public.my_friend_invite_code(),public.lookup_friend_invite_v2(text),public.request_friend_v2(text),
 public.acknowledge_mutual_friend_sharing(text),public.friend_comment_thread(uuid),public.friend_liker_avatars(uuid) from public,anon;
grant execute on function public.my_friend_invite_code(),public.lookup_friend_invite_v2(text),public.request_friend_v2(text),
 public.acknowledge_mutual_friend_sharing(text),public.friend_comment_thread(uuid),public.friend_liker_avatars(uuid) to authenticated;
commit;
