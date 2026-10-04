-- Disposable DB with real gym_store_reports / gym_store_changes DDL installed.
begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',label; end if;
raise notice 'PASS: %',label; end $$;
insert into auth.users(id,email,email_confirmed_at) values
 ('c0000000-0000-0000-0000-000000000001','reporter@test.invalid',now()),
 ('c0000000-0000-0000-0000-000000000002','reviewer@test.invalid',now()),
 ('c0000000-0000-0000-0000-000000000003','peer@test.invalid',now());
insert into public.gym_store_reports(user_id,kind,reported_chain_name,reported_name,reported_address,reviewed_by)
values('c0000000-0000-0000-0000-000000000001','new_store','Synthetic chain','Synthetic store','Synthetic address',
 'c0000000-0000-0000-0000-000000000002') returning id as report \gset
insert into public.gym_store_reports(user_id,kind,reported_chain_name,reported_name,reported_address)
values('c0000000-0000-0000-0000-000000000003','new_store','Synthetic chain','Peer store','Peer address') returning id as peer_report \gset
insert into public.gym_chains(id,name) values('synthetic-deletion-chain','Synthetic deletion chain');
insert into public.gym_stores(id,chain_id,source_id,name)
values('synthetic-deletion-store','synthetic-deletion-chain','synthetic-delete','Synthetic deletion store');
insert into public.gym_store_changes(store_id,operation,changed_by)
values('synthetic-deletion-store','Synthetic change','c0000000-0000-0000-0000-000000000002');
select public.account_deletion_prepare('c0000000-0000-0000-0000-000000000001',repeat('a',64));
delete from auth.users where id='c0000000-0000-0000-0000-000000000001';
select pg_temp.ok((select user_id is null and reported_name='Synthetic store' from public.gym_store_reports where id=:'report'),'shared report retained without Auth author');
delete from auth.users where id='c0000000-0000-0000-0000-000000000002';
select pg_temp.ok((select reviewed_by is null from public.gym_store_reports where id=:'report'),'review attribution cleared');
select pg_temp.ok((select changed_by is null and operation='Synthetic change' from public.gym_store_changes where store_id='synthetic-deletion-store'),'store audit retained without Auth actor');
select pg_temp.ok((select user_id='c0000000-0000-0000-0000-000000000003' and reported_name='Peer store' from public.gym_store_reports where id=:'peer_report'),'unrelated report and user retained');
select pg_temp.ok(exists(select 1 from public.gym_stores where id='synthetic-deletion-store'),'catalog store retained');
rollback;
