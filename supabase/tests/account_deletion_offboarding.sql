-- Disposable PostgreSQL ONLY. Fixtures and deletes are rolled back.
\set ON_ERROR_STOP on
begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',label; end if;
raise notice 'PASS: %',label; end $$;
create function pg_temp.denied(q text, expected_state text default null,
 expected_message text default null) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then
 return (expected_state is null or sqlstate=expected_state)
  and (expected_message is null or sqlerrm=expected_message); end $$;
insert into auth.users(id,email,email_confirmed_at)
select ('b0000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
 'deletion'||n||'@test.invalid',now() from generate_series(1,7)n;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-0000-0000-000000000001',true);
select public.tenant_create('Synthetic deletion tenant') as tenant \gset
select public.tenant_mutate(:'tenant','client','{"name":"Synthetic linked client"}')->>'id' as client \gset
select public.tenant_mutate(:'tenant','client_invite',jsonb_build_object('client_id',:'client'))->>'id' as token \gset
select set_config('request.jwt.claim.sub','b0000000-0000-0000-0000-000000000004',true);
select public.trainer_accept_invite(:'token','Synthetic linked client',true,true);
-- Logical revocation used to leave blocking Auth FKs.
select public.trainer_revoke_link(:'client');
reset role;

insert into public.tenant_memberships(tenant_id,user_id,is_trainer,status)
values(:'tenant','b0000000-0000-0000-0000-000000000002',true,'removed');
insert into public.tenant_assignments values(:'tenant',:'client','b0000000-0000-0000-0000-000000000002');
insert into public.tenant_clients(tenant_id,linked_user_id,client_name,share_workouts,status)
values(:'tenant','b0000000-0000-0000-0000-000000000003','Retained peer',true,'active') returning id as peer_client \gset
insert into public.tenant_menus(tenant_id,client_id,name,created_by,edited_by,client_read_by,client_read_at)
values(:'tenant',:'peer_client','Retained menu','b0000000-0000-0000-0000-000000000002',
 'b0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000004',now()) returning id as menu \gset
insert into public.tenant_comments(tenant_id,client_id,body,created_by,edited_by,client_read_by,shared_with_client)
values(:'tenant',:'peer_client','Retained comment','b0000000-0000-0000-0000-000000000002',
 'b0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000004',true) returning id as comment \gset
insert into public.tenant_templates(tenant_id,name,items,created_by)
values(:'tenant','Retained template','[]','b0000000-0000-0000-0000-000000000002') returning id as template \gset
insert into public.tenant_invites(tenant_id,kind,client_id,created_by)
values(:'tenant','client',:'peer_client','b0000000-0000-0000-0000-000000000002') returning token as staff_token \gset
insert into public.workouts(user_id,client_id,performed_at,sets,recorded_by,record_source,canceled_by,canceled_at)
values('b0000000-0000-0000-0000-000000000003','retained-peer',now(),'[]',
 'b0000000-0000-0000-0000-000000000002','self','b0000000-0000-0000-0000-000000000002',now());
-- Backfilled bridge can also block an otherwise valid Auth cascade.
insert into public.trainer_profiles(user_id,display_name)
values('b0000000-0000-0000-0000-000000000002','Legacy staff');
insert into public.trainer_client_links(trainer_id,client_id,client_name)
values('b0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000003','Legacy peer') returning id as legacy \gset
update public.tenant_clients set legacy_link_id=:'legacy' where id=:'peer_client';
update public.tenants set legacy_trainer_id='b0000000-0000-0000-0000-000000000002' where id=:'tenant';

-- Preflight and authoritative trigger refuse all tenant owners without changes.
set local role service_role;
select pg_temp.ok(public.account_deletion_prepare('b0000000-0000-0000-0000-000000000001',repeat('1',64))->>'error'
 ='tenant_owner_requires_transfer','owner preflight explains transfer requirement');
reset role;
select pg_temp.ok(pg_temp.denied('delete from auth.users where id=''b0000000-0000-0000-0000-000000000001''',
 'P0001','tenant_owner_requires_transfer'),'direct Auth owner delete also refused with explicit reason');
select pg_temp.ok((select count(*)=0 from public.account_deletion_requests),'owner refusal stores no request');
select pg_temp.ok((select linked_user_id='b0000000-0000-0000-0000-000000000004' from public.tenant_clients where id=:'client'), 'blocked delete leaves shared references unchanged');

-- Service-only boundary, even for a signed-in caller's own UUID.
set local role anon;
select pg_temp.ok(pg_temp.denied('select public.account_deletion_prepare(''b0000000-0000-0000-0000-000000000003'',repeat(''3'',64))'),'anon cannot prepare deletion');
select pg_temp.ok(pg_temp.denied('select public.account_deletion_receipt(repeat(''3'',64))'),'anon cannot read receipts');
reset role;
set local role authenticated;
select pg_temp.ok(pg_temp.denied('select public.account_deletion_prepare(''b0000000-0000-0000-0000-000000000003'',repeat(''3'',64))'),'authenticated cannot target users');
select pg_temp.ok(pg_temp.denied('select * from public.account_deletion_requests'),'authenticated cannot read request table');
reset role;

-- Prepare twice is idempotent, before Auth deletion receipt must be false.
set local role service_role;
select pg_temp.ok((public.account_deletion_prepare('b0000000-0000-0000-0000-000000000004',repeat('4',64))->>'ready')::boolean,'revoked client ready');
select pg_temp.ok((public.account_deletion_prepare('b0000000-0000-0000-0000-000000000004',repeat('4',64))->>'ready')::boolean,'duplicate prepare succeeds');
select pg_temp.ok(not public.account_deletion_receipt(repeat('4',64)),'prepared receipt is not deletion proof');
reset role;
select pg_temp.ok((select count(*)=1 from public.account_deletion_requests),'one request for duplicate prepare');
select pg_temp.ok(pg_temp.denied('select public.account_deletion_prepare(''b0000000-0000-0000-0000-000000000005'',repeat(''4'',64))',
 'P0001','Receipt conflict'),'receipt key cannot be reassigned to another user');
select pg_temp.ok(pg_temp.denied('select public.account_deletion_prepare(''b0000000-0000-0000-0000-000000000005'',''invalid'')',
 'P0001','Invalid receipt key'),'malformed receipt rejected');
delete from auth.users where id='b0000000-0000-0000-0000-000000000004';
select pg_temp.ok((select linked_user_id is null and status='revoked' and not share_workouts and not allow_recording and not share_heatmap and not share_body_weight from public.tenant_clients where id=:'client'),'client unlinked and every consent disabled');
select pg_temp.ok((select client_read_by is null from public.tenant_menus where id=:'menu'),'menu reader removed');
select pg_temp.ok((select client_read_by is null from public.tenant_comments where id=:'comment'),'comment reader removed');
select pg_temp.ok((select used_by is null and expires_at='-infinity'::timestamptz from public.tenant_invites where token=:'token'),'consumed invite permanently expires before attribution clears');
update public.tenant_invites set expires_at=now()+interval '1 day' where token=:'token';
select pg_temp.ok((select expires_at='-infinity'::timestamptz from public.tenant_invites where token=:'token'),'later reissue cannot revive terminal token');
set local role service_role;
select pg_temp.ok(public.account_deletion_receipt(repeat('4',64)),'committed Auth deletion has receipt');
select pg_temp.ok(not public.account_deletion_receipt(repeat('7',64)),'different credential has no receipt');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-0000-0000-000000000005',true);
select pg_temp.ok(public.trainer_preview_invite(:'token') is null,'used invite has no preview');
select pg_temp.ok(pg_temp.denied(format('select public.trainer_accept_invite(%L,''Replay'')',:'token')),'another verified user cannot replay used invite');
reset role;

-- Removed staff, attribution, legacy linkage and assignment FKs all handled.
select public.account_deletion_prepare('b0000000-0000-0000-0000-000000000002',repeat('2',64));
delete from auth.users where id='b0000000-0000-0000-0000-000000000002';
select pg_temp.ok(not exists(select 1 from public.tenant_memberships where user_id='b0000000-0000-0000-0000-000000000002'),'removed membership cleared');
select pg_temp.ok(not exists(select 1 from public.tenant_assignments where user_id='b0000000-0000-0000-0000-000000000002'),'dependent assignment cleared first');
select pg_temp.ok((select created_by is null and edited_by is null and name='Retained menu' from public.tenant_menus where id=:'menu'),'other client menu retained with nullable authors');
select pg_temp.ok((select created_by is null and edited_by is null and body='Retained comment' from public.tenant_comments where id=:'comment'),'other client comment retained');
select pg_temp.ok((select created_by is null from public.tenant_templates where id=:'template'),'shared template retained');
select pg_temp.ok((select created_by is null and expires_at='-infinity'::timestamptz from public.tenant_invites where token=:'staff_token'),'staff invitation invalidated');
select pg_temp.ok((select linked_user_id='b0000000-0000-0000-0000-000000000003' and legacy_link_id is null and share_workouts from public.tenant_clients where id=:'peer_client'),'unrelated client retained, legacy bridge cleared');
select pg_temp.ok((select legacy_trainer_id is null from public.tenants where id=:'tenant'),'transferred legacy trainer reference cleared');
select pg_temp.ok((select recorded_by is null and canceled_by is null and canceled_at is not null from public.workouts where client_id='retained-peer'),'other user workout retained with recorder and cancel actor cleared');

-- Unexpected downstream FK failure rolls back every cleanup and success marker.
insert into public.tenant_clients(tenant_id,linked_user_id,client_name,share_workouts,allow_recording)
values(:'tenant','b0000000-0000-0000-0000-000000000006','Retry client',true,true) returning id as retry_client \gset
create table public.account_deletion_test_blocker(user_id uuid references auth.users(id));
insert into public.account_deletion_test_blocker values('b0000000-0000-0000-0000-000000000006');
select public.account_deletion_prepare('b0000000-0000-0000-0000-000000000006',repeat('6',64));
select pg_temp.ok(pg_temp.denied('delete from auth.users where id=''b0000000-0000-0000-0000-000000000006''','23503'),'unexpected FK failure is refused');
select pg_temp.ok((select linked_user_id='b0000000-0000-0000-0000-000000000006' and share_workouts and allow_recording and client_name='Retry client' from public.tenant_clients where id=:'retry_client'),'failed Auth delete rolled all sharing changes back');
select pg_temp.ok(not public.account_deletion_receipt(repeat('6',64)),'failed Auth delete has no completed receipt');
delete from public.account_deletion_test_blocker;
delete from auth.users where id='b0000000-0000-0000-0000-000000000006';
select pg_temp.ok(public.account_deletion_receipt(repeat('6',64)),'retry after obstruction succeeds');
delete from auth.users where id='b0000000-0000-0000-0000-000000000006';
select pg_temp.ok((select count(*)=1 from public.account_deletion_requests where token_hash=repeat('6',64)),'duplicate delete has no extra side effects');

-- Reuse existing verified owner RPC, with a real active replacement member.
insert into public.tenant_memberships(tenant_id,user_id,is_admin,is_trainer,status)
values(:'tenant','b0000000-0000-0000-0000-000000000003',true,true,'active');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-0000-0000-000000000001',true);
select public.tenant_mutate(:'tenant','owner',jsonb_build_object('user_id','b0000000-0000-0000-0000-000000000003'));
reset role;
select public.account_deletion_prepare('b0000000-0000-0000-0000-000000000001',repeat('1',64));
delete from auth.users where id='b0000000-0000-0000-0000-000000000001';
select pg_temp.ok(exists(select 1 from public.tenants where id=:'tenant'),'ownership transfer retains organization');
select pg_temp.ok(exists(select 1 from auth.users where id='b0000000-0000-0000-0000-000000000003'),'new owner retained');
select pg_temp.ok(exists(select 1 from public.tenant_menus where id=:'menu'),'organization records survive former owner deletion');
update public.account_deletion_requests set completed_at=now()-interval '8 days' where token_hash=repeat('4',64);
select pg_temp.ok(not public.account_deletion_receipt(repeat('4',64)),'expired receipt cannot assert success');
select public.account_deletion_prepare('b0000000-0000-0000-0000-000000000005',repeat('5',64));
select pg_temp.ok(not exists(select 1 from public.account_deletion_requests where token_hash=repeat('4',64)),'next prepare purges expired receipts');
rollback;
