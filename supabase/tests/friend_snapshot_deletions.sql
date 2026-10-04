begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.denied(q text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then return true; end $$;
create function pg_temp.sync_snapshot(owner uuid,records jsonb,ids text[],publish boolean default true)
returns void language sql as $$
 select public.sync_friend_workouts(owner,records,ids,'64000000-0000-4000-8000-000000000001',100,publish)
$$;
insert into auth.users(id) values
('61000000-0000-0000-0000-000000000001'),
('61000000-0000-0000-0000-000000000002'),
('61000000-0000-0000-0000-000000000003');
insert into public.friend_profiles(user_id,display_name,visibility) values
('61000000-0000-0000-0000-000000000001','Synthetic owner','private'),
('61000000-0000-0000-0000-000000000002','Synthetic friend','private'),
('61000000-0000-0000-0000-000000000003','Synthetic pending','friends');
insert into public.friend_connections(requester,recipient,status) values
('61000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000002','accepted'),
('61000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000003','pending');
insert into public.friend_workouts(id,user_id,client_id,performed_at,duration_seconds,sets) values
('63000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000001','2026-10-01T12:00:00.000',now(),60,'[]'),
('63000000-0000-0000-0000-000000000002','61000000-0000-0000-0000-000000000001','2026-10-02T12:00:00.000',now(),60,'[]'),
('63000000-0000-0000-0000-000000000003','61000000-0000-0000-0000-000000000002','2026-10-01T12:00:00.000',now(),60,'[]');
insert into public.friend_likes values
('63000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000002'),
('63000000-0000-0000-0000-000000000002','61000000-0000-0000-0000-000000000002');
insert into public.friend_comments(workout_id,user_id,body) values
('63000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000002','Synthetic deleted'),
('63000000-0000-0000-0000-000000000002','61000000-0000-0000-0000-000000000002','Synthetic kept');
set local role authenticated;
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000001',true);
select public.publish_friend_workouts('[]');
select pg_temp.ok((select count(*)=2 from public.friend_workouts),'reproduces legacy private publish retaining deleted snapshots');
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000002',true);
select pg_temp.ok((select count(*)=1 from public.friend_workouts),'private owner data hidden from approved friend');
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync_snapshot('61000000-0000-0000-0000-000000000001','[]',array['2026-10-01T12:00:00.000'])$q$),'approved friend cannot delete private owner snapshot');
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000003',true);
select pg_temp.ok((select count(*)=0 from public.friend_workouts),'pending friend cannot read private snapshots');
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync_snapshot('61000000-0000-0000-0000-000000000001','[]',array['2026-10-01T12:00:00.000'])$q$),'pending friend cannot delete owner snapshot');
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync_snapshot(null,'[]',array['2026-10-01T12:00:00.000'])$q$),'null expected owner rejected');
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000001',true);
select pg_temp.ok(pg_temp.denied($q$delete from public.friend_workouts$q$),'no direct DELETE privilege added');
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync_snapshot('61000000-0000-0000-0000-000000000001','{}',array['2026-10-01T12:00:00.000'])$q$),'invalid payload fails before any delete');
select pg_temp.ok((select count(*)=2 from public.friend_workouts),'invalid request leaves owner snapshots unchanged');
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync_snapshot('61000000-0000-0000-0000-000000000001','[]',array[null::text])$q$),'null deletion ID rejected');
select pg_temp.sync_snapshot('61000000-0000-0000-0000-000000000001','[{"date":"2026-10-01T12:00:00.000","sets":[],"durationSeconds":60},{"date":"2026-10-03T12:00:00.000","sets":[]}]',array['2026-10-01T12:00:00.000']);
select pg_temp.ok((select count(*)=1 and min(client_id)='2026-10-02T12:00:00.000' from public.friend_workouts),'private deletion removes only explicit IDs and never uploads');
select pg_temp.ok((select visibility='private' from public.friend_profiles where user_id=auth.uid()),'private deletion never changes visibility');
select pg_temp.ok((select count(*)=1 from public.friend_likes),'deleted reactions cascade but kept like remains');
select pg_temp.ok((select count(*)=1 from public.friend_comments),'deleted comments cascade but kept comment remains');
select pg_temp.sync_snapshot('61000000-0000-0000-0000-000000000001','[]',array['2026-10-01T12:00:00.000'],false);
select pg_temp.ok((select count(*)=1 from public.friend_workouts),'duplicate retry is idempotent');
update public.friend_profiles set visibility='friends' where user_id=auth.uid();
select pg_temp.sync_snapshot('61000000-0000-0000-0000-000000000001','[]',array['2026-10-01T12:00:00.000'],false);
select pg_temp.ok((select count(*)=1 from public.friend_workouts),'deletion-only retry does not prune or publish public history');
select pg_temp.sync_snapshot('61000000-0000-0000-0000-000000000001','[{"date":"2026-10-01T12:00:00.000","sets":[]},{"date":"2026-10-02T12:00:00.000","sets":[],"durationSeconds":120}]',array['2026-10-01T12:00:00.000']);
select pg_temp.ok((select count(*)=1 and min(client_id)='2026-10-02T12:00:00.000' and min(duration_seconds)=120 from public.friend_workouts),'stale payload cannot resurrect tombstone and retained record updates');
select pg_temp.ok((select id='63000000-0000-0000-0000-000000000002' from public.friend_workouts),'kept snapshot identity remains');
select pg_temp.ok((select count(*)=1 from public.friend_likes),'kept reactions survive update');
-- Recreate an ordinary public snapshot and make upsert invalid after a delete.
select pg_temp.sync_snapshot('61000000-0000-0000-0000-000000000001','[{"date":"2026-10-02T12:00:00.000","sets":[]}]',array[]::text[]);
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync_snapshot('61000000-0000-0000-0000-000000000001','[{"date":"2026-10-04T12:00:00.000","durationSeconds":-1,"sets":[]}]',array['2026-10-02T12:00:00.000'])$q$),'invalid public upsert rolls back preceding delete');
select pg_temp.ok((select count(*)=1 and min(client_id)='2026-10-02T12:00:00.000' from public.friend_workouts),'transactional rollback preserves prior snapshot');
select pg_temp.ok(pg_temp.denied($q$select * from public.friend_snapshot_versions$q$),'ordering metadata unavailable to app users');
select public.sync_friend_workouts('61000000-0000-0000-0000-000000000001','[]',array['2026-10-02T12:00:00.000'],'64000000-0000-4000-8000-000000000001',101,false);
select public.sync_friend_workouts('61000000-0000-0000-0000-000000000001','[{"date":"2026-10-02T12:00:00.000","sets":[]}]',array[]::text[],'64000000-0000-4000-8000-000000000001',100);
select pg_temp.ok((select count(*)=0 from public.friend_workouts),'late old publication cannot resurrect deleted record');
select public.sync_friend_workouts('61000000-0000-0000-0000-000000000001','[{"date":"2026-10-02T12:00:00.000","sets":[]}]',array[]::text[],'64000000-0000-4000-8000-000000000001',102);
select public.sync_friend_workouts('61000000-0000-0000-0000-000000000001','[]',array['2026-10-02T12:00:00.000'],'64000000-0000-4000-8000-000000000001',101,false);
select pg_temp.ok((select count(*)=1 and min(client_id)='2026-10-02T12:00:00.000' from public.friend_workouts),'late old deletion cannot undo a newer restore');
select pg_temp.ok(pg_temp.denied($q$select public.sync_friend_workouts('61000000-0000-0000-0000-000000000001','[]',array[]::text[],null,103)$q$),'null device identity rejected');
select pg_temp.ok(pg_temp.denied($q$select public.sync_friend_workouts('61000000-0000-0000-0000-000000000001','[]',array[]::text[],'64000000-0000-4000-8000-000000000001',-1)$q$),'negative revision rejected');
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000002',true);
select pg_temp.ok((select count(*)=1 from public.friend_workouts where user_id=auth.uid() and client_id='2026-10-01T12:00:00.000'),'another owner same client ID untouched');
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync_snapshot('61000000-0000-0000-0000-000000000001','[]',array['2026-10-02T12:00:00.000'])$q$),'account-switch expected owner mismatch rejected');
select public.sync_friend_workouts('61000000-0000-0000-0000-000000000002','[]',array[]::text[],'64000000-0000-4000-8000-000000000001',1,false);
select set_config('request.jwt.claim.sub','',true);
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync_snapshot('61000000-0000-0000-0000-000000000001','[]',array['2026-10-02T12:00:00.000'])$q$),'authenticated role without identity rejected');
set local role anon;
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync_snapshot('61000000-0000-0000-0000-000000000001','[]',array['2026-10-02T12:00:00.000'])$q$),'anonymous RPC execution denied');
reset role;
select pg_temp.ok((select count(*)=1 from public.friend_snapshot_versions where user_id='61000000-0000-0000-0000-000000000002'),'owner ordering metadata stored independently');
delete from auth.users where id='61000000-0000-0000-0000-000000000002';
select pg_temp.ok((select count(*)=0 from public.friend_snapshot_versions where user_id='61000000-0000-0000-0000-000000000002'),'ordering metadata cascades on account deletion');
rollback;
