-- Synthetic-only QA. All rows and changes rolled back; never run against a linked project.
begin;
insert into auth.users(id) select ('00000000-0000-4000-9010-'||lpad(i::text,12,'0'))::uuid from generate_series(1,9)i;
insert into public.app_admins(user_id) values('00000000-0000-4000-9010-000000000009');
insert into public.gym_chains(id,name) values('qa-admin-chain','Synthetic admin QA');
insert into public.gym_stores(id,chain_id,source_id,name) select 'qa-admin-'||i,'qa-admin-chain',i::text,'Synthetic store '||i from generate_series(1,14)i;
insert into public.equipment(id,name,normalized_name,category) values
 ('qa-admin-machine','Synthetic admin machine','syntheticadminmachine','qa'),
 ('qa-admin-added','Synthetic added machine','syntheticaddedmachine','qa');
insert into public.gym_store_equipment(store_id,equipment_id,quantity,raw_name,source_kind)
 select 'qa-admin-'||i,'qa-admin-machine',4,'Synthetic admin machine','official' from generate_series(1,12)i;
insert into public.gym_change_candidates(store_id,equipment_id,change_type,candidate_key,proposed_value,status)
 select 'qa-admin-'||i,'qa-admin-machine','quantity_changed','qa-admin-machine:quantity:5',
 '{"equipment_id":"qa-admin-machine","reported_quantity":5}','needs_review' from generate_series(1,6)i;
insert into public.gym_change_candidates(store_id,equipment_id,change_type,candidate_key,proposed_value,status) values
 ('qa-admin-7','qa-admin-machine','temporarily_unavailable','qa-admin-machine:unavailable:partial:2','{"unavailable_scope":"partial","reported_unavailable_quantity":2}','needs_review'),
 ('qa-admin-8','qa-admin-machine','removed','qa-admin-machine','{}','needs_review'),
 ('qa-admin-9','qa-admin-machine','not_present','qa-admin-machine','{}','needs_review'),
 ('qa-admin-10','qa-admin-machine','available_again','qa-admin-machine:available:all','{}','needs_review'),
 ('qa-admin-11','qa-admin-machine','temporarily_unavailable','qa-admin-machine:unavailable:partial:4','{"unavailable_scope":"partial","reported_unavailable_quantity":4}','needs_review'),
 ('qa-admin-12','qa-admin-machine','wrong_name','qa-admin-machine:new','{"equipment_name":"new"}','needs_review'),
 ('qa-admin-13',null,'added','unmatchedsyntheticname','{"equipment_name":"Unmatched synthetic name"}','needs_review');
create function pg_temp.check_ok(value boolean,message text) returns void language plpgsql as $$begin
 if value is distinct from true then raise exception 'QA failed: %',message; end if;
end $$;
create function pg_temp.action(store text,act text,op uuid default gen_random_uuid(),eid text default null,confirmed boolean default false)
returns jsonb language plpgsql as $$declare id uuid;s jsonb;begin
 select c.id into id from public.gym_change_candidates c where store_id=store order by created_at limit 1;
 s:=public.get_admin_equipment_candidate(id,eid);
 return public.review_gym_equipment_candidate(id,act,s->>'status',(s->>'review_version')::bigint,op,'Synthetic reason',
 (s->>'master_present')::boolean,(s->>'master_updated_at')::timestamptz,eid,confirmed);
end $$;
create function pg_temp.expect_error(query text,code text) returns void language plpgsql as $$begin
 begin execute query; exception when others then
 if sqlstate=code then return; end if; raise;
 end;
 raise exception 'QA expected SQLSTATE %',code;
end $$;

-- Production-like default ACLs must not leak new admin objects to service_role.
select pg_temp.check_ok(not has_table_privilege('service_role','public.gym_equipment_review_operations','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),'new audit table service_role denied');
select pg_temp.check_ok(not has_function_privilege('service_role','public.get_admin_equipment_candidate(uuid,text)','EXECUTE'),'new snapshot service_role denied');
select pg_temp.check_ok(not has_function_privilege('service_role','public.list_admin_equipment_candidates(integer)','EXECUTE'),'new list service_role denied');
select pg_temp.check_ok(not has_function_privilege('service_role','public.review_gym_equipment_candidate(uuid,text,text,bigint,uuid,text,boolean,timestamptz,text,boolean)','EXECUTE'),'new mutation service_role denied');
select pg_temp.check_ok(not has_function_privilege('service_role','public.lock_gym_equipment_review()','EXECUTE'),'new lock helper service_role denied');
select pg_temp.check_ok(not has_function_privilege('service_role','public.bump_gym_candidate_review_version()','EXECUTE'),'new version helper service_role denied');
select pg_temp.check_ok(has_function_privilege('service_role','public.apply_gym_change_candidate(uuid)','EXECUTE'),'existing automatic entrance retained');
select pg_temp.check_ok(has_function_privilege('service_role','public.confirm_training_equipment(text,text,text,text,boolean,uuid)','EXECUTE'),'existing confirmation entrance retained');

set local role authenticated;
set local request.jwt.claim.sub='00000000-0000-4000-9010-000000000001';
select pg_temp.expect_error('select public.list_admin_equipment_candidates()', '42501');
-- SECURITY DEFINER does not replace administrator identity checks.
select pg_temp.expect_error('select public.review_gym_equipment_candidate(gen_random_uuid(),''hold'',''needs_review'',1,gen_random_uuid(),''reason'',false,null)', '42501');
select pg_temp.check_ok((select count(*)=0 from public.gym_equipment_review_operations),'nonadmin audit RLS');
select pg_temp.expect_error('update public.gym_equipment_reports set status=''rejected''','42501');
set local request.jwt.claim.sub='00000000-0000-4000-9010-000000000009';
select pg_temp.check_ok(jsonb_array_length(public.list_admin_equipment_candidates()->'rows')=13,'admin list');
select pg_temp.action('qa-admin-1','apply');
select pg_temp.check_ok((select quantity=5 and source_kind='admin' from public.gym_store_equipment where store_id='qa-admin-1'),'manual quantity update');
select pg_temp.check_ok((select application_type='admin' and before_data->>'quantity'='4' and after_data->>'quantity'='5' from public.gym_auto_applications where store_id='qa-admin-1'),'atomic application history');
select pg_temp.action('qa-admin-1','rollback');
select pg_temp.check_ok((select quantity=4 and source_kind='official' from public.gym_store_equipment where store_id='qa-admin-1'),'admin rollback exact source restore');
select pg_temp.action('qa-admin-2','hold');
select pg_temp.expect_error('select pg_temp.action(''qa-admin-2'',''apply'')','22023');
select pg_temp.action('qa-admin-2','release');
select pg_temp.action('qa-admin-2','reject');
select pg_temp.expect_error('select pg_temp.action(''qa-admin-2'',''apply'')','40001');
select pg_temp.action('qa-admin-7','apply');
select pg_temp.check_ok((select available and presence_status='present' and unavailable_quantity=2 from public.gym_store_equipment where store_id='qa-admin-7'),'partial differs from removed');
select pg_temp.action('qa-admin-8','apply');
select pg_temp.check_ok((select not available and presence_status='removed' from public.gym_store_equipment where store_id='qa-admin-8'),'removed');
select pg_temp.action('qa-admin-9','apply');
select pg_temp.check_ok((select presence_status='removed' from public.gym_store_equipment where store_id='qa-admin-9'),'manual not_present maps removed');
select pg_temp.action('qa-admin-10','apply');
select pg_temp.expect_error('select pg_temp.action(''qa-admin-11'',''apply'')','22023');
select pg_temp.check_ok((select status='needs_review' from public.gym_change_candidates where store_id='qa-admin-11'),'failed application rolled back candidate');
select pg_temp.expect_error('select pg_temp.action(''qa-admin-12'',''apply'')','22023');
select pg_temp.expect_error('select pg_temp.action(''qa-admin-13'',''apply'')','22023');
select pg_temp.expect_error('select pg_temp.action(''qa-admin-13'',''apply'',gen_random_uuid(),''qa-admin-added'',false)','22023');
select pg_temp.action('qa-admin-13','apply',gen_random_uuid(),'qa-admin-added',true);
select pg_temp.check_ok((select equipment_id='qa-admin-added' from public.gym_store_equipment where store_id='qa-admin-13'),'explicit mapping adoption');
select pg_temp.action('qa-admin-13','rollback');
select pg_temp.check_ok((select count(*)=0 from public.gym_store_equipment where store_id='qa-admin-13'),'rollback inserted equipment');

-- Idempotency must return original result even after candidate version changed.
do $$declare s jsonb;r jsonb;again jsonb;id uuid;op uuid:=gen_random_uuid();begin
 select c.id into id from public.gym_change_candidates c where store_id='qa-admin-3';
 s:=public.get_admin_equipment_candidate(id);
 r:=public.review_gym_equipment_candidate(id,'hold',s->>'status',(s->>'review_version')::bigint,op,'Same reason',true,(s->>'master_updated_at')::timestamptz);
 again:=public.review_gym_equipment_candidate(id,'hold',s->>'status',(s->>'review_version')::bigint,op,'Same reason',true,(s->>'master_updated_at')::timestamptz);
 perform pg_temp.check_ok(r=again,'same request idempotent');
 perform pg_temp.expect_error(format('select public.review_gym_equipment_candidate(%L,''hold'',%L,%s,%L,''Different'',true,%L)',id,s->>'status',s->>'review_version',op,s->>'master_updated_at'),'22023');
 perform pg_temp.expect_error(format('select public.review_gym_equipment_candidate(%L,''hold'',%L,%s,gen_random_uuid(),''Reason'',true,%L)',id,s->>'status',s->>'review_version',s->>'master_updated_at'),'40001');
end $$;
-- A concurrent/new master update must be explicitly refreshed before any action.
do $$declare s jsonb;id uuid;begin
 select c.id into id from public.gym_change_candidates c where store_id='qa-admin-4';
 s:=public.get_admin_equipment_candidate(id);
 perform pg_temp.expect_error(format('select public.review_gym_equipment_candidate(%L,''apply'',%L,%s,gen_random_uuid(),''Reason'',true,%L)',id,s->>'status',s->>'review_version','2000-01-01'),'40001');
end $$;
select pg_temp.action('qa-admin-5','apply');
reset role;
update public.gym_store_equipment set quantity=6,updated_at=clock_timestamp() where store_id='qa-admin-5';
set local role authenticated;
select pg_temp.expect_error('select pg_temp.action(''qa-admin-5'',''rollback'')','P0001');
-- After update, rollback is rejected even with a fresh candidate/master snapshot.
select pg_temp.check_ok((select quantity=6 from public.gym_store_equipment where store_id='qa-admin-5'),'rollback did not overwrite later master');

-- Report ingestion continues to group while held, retaining new evidence.
set local request.jwt.claim.sub='00000000-0000-4000-9010-000000000001';
insert into public.gym_equipment_reports(store_id,kind,equipment_name) values('qa-admin-14','added','Synthetic added machine');
set local request.jwt.claim.sub='00000000-0000-4000-9010-000000000009';
select pg_temp.action('qa-admin-14','hold');
set local request.jwt.claim.sub='00000000-0000-4000-9010-000000000002';
insert into public.gym_equipment_reports(store_id,kind,equipment_name) values('qa-admin-14','added','Synthetic added machine');
set local request.jwt.claim.sub='00000000-0000-4000-9010-000000000003';
insert into public.gym_equipment_reports(store_id,kind,equipment_name) values('qa-admin-14','added','Synthetic added machine');
set local request.jwt.claim.sub='00000000-0000-4000-9010-000000000009';
select pg_temp.check_ok((select count(*)=1 and bool_and(admin_held) from public.gym_change_candidates where store_id='qa-admin-14'),'held candidate retained after new reports');
select pg_temp.check_ok((select count(*)=0 from public.gym_store_equipment where store_id='qa-admin-14'),'no auto apply while held');
reset role;
select public.reevaluate_gym_change_candidate(id) from public.gym_change_candidates where store_id='qa-admin-14';
select public.apply_gym_change_candidate(id) from public.gym_change_candidates where store_id='qa-admin-14';
set local role authenticated;
select pg_temp.check_ok((select count(*)=0 from public.gym_store_equipment where store_id='qa-admin-14'),'direct internal reevaluate/apply respect hold');
select pg_temp.action('qa-admin-14','release');
select pg_temp.check_ok((select status='auto_applied' and not admin_held from public.gym_change_candidates where store_id='qa-admin-14'),'release resumes existing automatic apply');
select pg_temp.check_ok((select count(*)=3 from public.gym_equipment_reports where store_id='qa-admin-14' and status='applied'),'atomic auto related report update');
select pg_temp.expect_error('select pg_temp.action(''qa-admin-14'',''apply'',gen_random_uuid(),''qa-admin-added'',true)','40001');
select pg_temp.action('qa-admin-14','rollback');

-- Individual review RPC remains usable; table mutation is now RPC-only.
set local request.jwt.claim.sub='00000000-0000-4000-9010-000000000004';
insert into public.gym_equipment_reports(store_id,equipment_id,kind,reported_quantity) values('qa-admin-6','qa-admin-machine','quantity_changed',5);
set local request.jwt.claim.sub='00000000-0000-4000-9010-000000000009';
select public.update_admin_report('equipment',id,status,'reviewing','Review') from public.gym_equipment_reports where store_id='qa-admin-6';
select pg_temp.action('qa-admin-6','apply');
select pg_temp.check_ok((select status='applied' and reviewed_by=auth.uid() from public.gym_equipment_reports where store_id='qa-admin-6'),'manual apply updates pending/reviewing report with actor');
select pg_temp.check_ok((select count(*)=1 from public.gym_equipment_review_operations where candidate_id=(select id from public.gym_change_candidates where store_id='qa-admin-6')),'one operation persisted');
rollback;
