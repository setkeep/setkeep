-- Synthetic fixtures only. All records, roles and changes roll back.
begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.denied(q text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then return true; end $$;
create function pg_temp.record(owner uuid,day integer,duration integer default 60) returns jsonb language sql as $$
 select jsonb_build_object('friendOwnerUserId',owner,'date',format('2026-10-%sT12:00:00.000',lpad(day::text,2,'0')),'durationSeconds',duration,'sets','[]'::jsonb)
$$;
create function pg_temp.sync(owner uuid,records jsonb,ids text[] default array[]::text[],revision bigint default 10,device uuid default '75400000-0000-4000-8000-000000000001') returns jsonb language sql as $$
 select public.sync_owned_friend_workouts(owner,records,ids,device,revision)
$$;
insert into auth.users(id) values
('75000000-0000-4000-8000-000000000001'),
('75000000-0000-4000-8000-000000000002'),
('75000000-0000-4000-8000-000000000003'),
('75000000-0000-4000-8000-000000000004');
insert into public.friend_profiles(user_id,display_name,visibility) values
('75000000-0000-4000-8000-000000000001','Synthetic A','private'),
('75000000-0000-4000-8000-000000000002','Synthetic B','private'),
('75000000-0000-4000-8000-000000000003','Synthetic pending','friends');
insert into public.friend_connections(requester,recipient,status) values
('75000000-0000-4000-8000-000000000001','75000000-0000-4000-8000-000000000002','accepted'),
('75000000-0000-4000-8000-000000000001','75000000-0000-4000-8000-000000000003','pending');
insert into public.friend_workouts(id,user_id,client_id,performed_at,duration_seconds,sets) values
('75300000-0000-4000-8000-000000000001','75000000-0000-4000-8000-000000000001','2026-10-01T12:00:00.000',now(),60,'[]'),
('75300000-0000-4000-8000-000000000002','75000000-0000-4000-8000-000000000001','2026-10-02T12:00:00.000',now(),60,'[]'),
('75300000-0000-4000-8000-000000000003','75000000-0000-4000-8000-000000000002','2026-10-01T12:00:00.000',now(),60,'[]');
insert into public.friend_likes values ('75300000-0000-4000-8000-000000000002','75000000-0000-4000-8000-000000000002');
insert into public.friend_comments(workout_id,user_id,body) values ('75300000-0000-4000-8000-000000000002','75000000-0000-4000-8000-000000000002','Synthetic kept');
select pg_temp.ok((select bool_and(friend_owned_sync_version=1) from public.friend_profiles where user_id::text like '75000000%'),'additive capability marker present');
set local role authenticated;
select set_config('request.jwt.claim.sub','75000000-0000-4000-8000-000000000001',true);
select pg_temp.ok((select visibility='private' and sharing_consent_version=0 from public.friend_profiles where user_id=auth.uid()),'migration does not grant sharing');
select pg_temp.ok(pg_temp.sync(auth.uid(),'[]')='{"accepted":true,"published":false}'::jsonb,'empty device receives harmless receipt');
select pg_temp.ok((select count(*)=2 from public.friend_workouts),'empty device retains existing snapshots');
select pg_temp.ok(pg_temp.sync(auth.uid(),jsonb_build_array(pg_temp.record(auth.uid(),3)))='{"accepted":true,"published":false}'::jsonb,'private publication is acknowledged without publishing');
select pg_temp.ok((select count(*)=2 from public.friend_workouts),'private request uploads nothing');
select pg_temp.ok((select visibility='private' from public.friend_profiles where user_id=auth.uid()),'private never automatically becomes friends');
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync(null,'[]')$q$),'null owner rejected');
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync('75000000-0000-4000-8000-000000000002','[]')$q$),'account switch owner mismatch rejected');
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync(auth.uid(),'[{"date":"2026-10-03T12:00:00.000","sets":[]}]',array['2026-10-01T12:00:00.000'])$q$),'unknown provenance rejected before deletion');
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync(auth.uid(),jsonb_build_array(pg_temp.record('75000000-0000-4000-8000-000000000002',3)))$q$),'other account record rejected');
select pg_temp.ok(pg_temp.denied($q$select public.acknowledge_owned_friend_sharing('75000000-0000-4000-8000-000000000002','privacy-1.2')$q$),'consent bound to authenticated owner');
select pg_temp.ok(pg_temp.denied($q$select public.acknowledge_owned_friend_sharing(auth.uid(),'privacy-old')$q$),'old consent rejected');
select public.acknowledge_owned_friend_sharing(auth.uid(),'privacy-1.2');
select pg_temp.ok((select visibility='friends' and sharing_consent_version=1 from public.friend_profiles where user_id=auth.uid()),'explicit consent enables only current account');
select pg_temp.ok(pg_temp.sync(auth.uid(),jsonb_build_array(pg_temp.record(auth.uid(),3)))='{"accepted":true,"published":true}'::jsonb,'owned new workout publishes after explicit consent');
select pg_temp.ok((select count(*)=3 from public.friend_workouts where user_id=auth.uid()),'additive publication retains server-only history');
select pg_temp.sync(auth.uid(),jsonb_build_array(pg_temp.record(auth.uid(),2,120)));
select pg_temp.ok((select id='75300000-0000-4000-8000-000000000002' and duration_seconds=120 from public.friend_workouts where client_id='2026-10-02T12:00:00.000'),'owned update preserves snapshot identity');
select pg_temp.ok((select count(*)=1 from public.friend_likes),'owned update preserves likes');
select pg_temp.ok((select count(*)=1 from public.friend_comments),'owned update preserves comments');
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync(auth.uid(),jsonb_build_array(pg_temp.record(auth.uid(),4,-1)),array['2026-10-02T12:00:00.000'])$q$),'invalid duration rejects deletion atomically');
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync(auth.uid(),jsonb_build_array(pg_temp.record(auth.uid(),4)||'{"date":"invalid-date"}'::jsonb),array['2026-10-02T12:00:00.000'])$q$),'invalid date rejects before deletion');
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync(auth.uid(),jsonb_build_array(pg_temp.record(auth.uid(),4),pg_temp.record(auth.uid(),4)),array['2026-10-02T12:00:00.000'])$q$),'duplicate upsert rolls back entire request');
select pg_temp.ok((select count(*)=3 from public.friend_workouts where user_id=auth.uid()),'invalid requests preserve original rows');
select pg_temp.ok(pg_temp.denied($q$delete from public.friend_workouts$q$),'no direct deletion grant');
select pg_temp.ok(pg_temp.denied($q$select * from public.friend_snapshot_versions$q$),'ordering metadata remains unavailable');
update public.friend_profiles set visibility='private' where user_id=auth.uid();
select pg_temp.sync(auth.uid(),jsonb_build_array(pg_temp.record(auth.uid(),4)),array['2026-10-01T12:00:00.000'],11);
select pg_temp.ok((select count(*)=2 from public.friend_workouts where user_id=auth.uid()),'private explicit delete affects exact owner ID only');
select pg_temp.ok((select visibility='private' from public.friend_profiles where user_id=auth.uid()),'private deletion does not grant consent');
select pg_temp.ok(pg_temp.sync(auth.uid(),jsonb_build_array(pg_temp.record(auth.uid(),1)),array[]::text[],10)='{"accepted":false,"published":false}'::jsonb,'stale request receipt rejects publication');
select public.acknowledge_owned_friend_sharing(auth.uid(),'privacy-1.2');
select pg_temp.sync(auth.uid(),jsonb_build_array(pg_temp.record(auth.uid(),1)),array[]::text[],12);
select pg_temp.sync(auth.uid(),'[]',array['2026-10-01T12:00:00.000'],11);
select pg_temp.ok((select count(*)=3 from public.friend_workouts where user_id=auth.uid()),'late deletion cannot undo newer restore');
select pg_temp.sync(auth.uid(),jsonb_build_array(pg_temp.record(auth.uid(),5)),array[]::text[],1,'75400000-0000-4000-8000-000000000002');
select pg_temp.ok((select count(*)=4 from public.friend_workouts where user_id=auth.uid()),'another device adds without pruning');
update public.friend_profiles set sharing_consent_version=0 where user_id=auth.uid();
select pg_temp.ok(pg_temp.sync(auth.uid(),jsonb_build_array(pg_temp.record(auth.uid(),6)),array[]::text[],13)='{"accepted":true,"published":false}'::jsonb,'missing sharing consent blocks publication');
select pg_temp.ok((select sharing_consent_version=0 from public.friend_profiles where user_id=auth.uid()),'sync never grants missing consent');
update public.friend_profiles set visibility='private' where user_id=auth.uid();
select set_config('request.jwt.claim.sub','75000000-0000-4000-8000-000000000002',true);
select pg_temp.ok((select visibility='private' from public.friend_profiles where user_id=auth.uid()),'another profile remains private');
select pg_temp.ok((select count(*)=1 from public.friend_workouts),'accepted friend cannot read private owner snapshots');
select pg_temp.ok((select client_id='2026-10-01T12:00:00.000' from public.friend_workouts),'other owner same client ID retained');
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync('75000000-0000-4000-8000-000000000001','[]',array['2026-10-02T12:00:00.000'])$q$),'accepted friend cannot delete another owner');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_likes values ('75300000-0000-4000-8000-000000000002',auth.uid())$q$),'private reaction write rejected');
select set_config('request.jwt.claim.sub','75000000-0000-4000-8000-000000000003',true);
select pg_temp.ok((select count(*)=0 from public.friend_workouts),'pending friend cannot read snapshots');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_comments(workout_id,user_id,body) values ('75300000-0000-4000-8000-000000000002',auth.uid(),'Synthetic denied')$q$),'pending friend cannot write comments');
select set_config('request.jwt.claim.sub','75000000-0000-4000-8000-000000000004',true);
select pg_temp.ok(pg_temp.sync(auth.uid(),jsonb_build_array(pg_temp.record(auth.uid(),1)))='{"accepted":false,"published":false}'::jsonb,'missing profile receives unaccepted receipt');
select set_config('request.jwt.claim.sub','',true);
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync('75000000-0000-4000-8000-000000000001','[]')$q$),'authenticated role without identity denied');
set local role anon;
select pg_temp.ok(pg_temp.denied($q$select pg_temp.sync('75000000-0000-4000-8000-000000000001','[]')$q$),'anonymous owned sync denied');
select pg_temp.ok(pg_temp.denied($q$select public.acknowledge_owned_friend_sharing('75000000-0000-4000-8000-000000000001','privacy-1.2')$q$),'anonymous consent denied');
select pg_temp.ok(pg_temp.denied($q$select * from public.friend_workouts$q$),'anonymous snapshot read denied');
reset role;
select pg_temp.ok((select count(*)=2 from public.friend_snapshot_versions where user_id='75000000-0000-4000-8000-000000000001'),'owner devices maintain separate revisions');
rollback;
