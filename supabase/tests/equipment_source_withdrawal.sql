begin;
-- Before-migration snapshots are recorded by the runner, not copied from production.
do $$ begin
 if (select count(*) from public.gym_stores)<>(select n from qa_store_snapshot) then raise exception 'Store count changed'; end if;
 if (select md5(string_agg(to_jsonb(s)::text,'' order by s.id)) from public.gym_stores s)<>(select h from qa_store_snapshot) then raise exception 'Store metadata changed'; end if;
 if exists(select 1 from equipment_quarantine.inventory q join public.gym_store_equipment g using(store_id,equipment_id)) then raise exception 'Original relation still published'; end if;
 if exists(select 1 from qa_other_inventory b full join public.gym_store_equipment g using(store_id,equipment_id) where (b.original is not null or not public.community_equipment_only(g.store_id)) and b.original is distinct from to_jsonb(g)) then raise exception 'Other inventory changed'; end if;
 if exists(select 1 from equipment_quarantine.hidden_equipment h join public.equipment e on e.id=h.equipment_id where h.original<>to_jsonb(e)) then raise exception 'Archived master altered'; end if;
end $$;
-- Match production public default grants: all new routines must explicitly
-- remove service_role/PUBLIC, without touching pre-existing ACLs.
do $$ declare r record; name text; role_name text; begin
 for r in select p.oid,p.proacl from pg_proc p join qa_existing_routine_acl old on old.oid=p.oid loop
  if r.proacl is distinct from (select proacl from qa_existing_routine_acl where oid=r.oid) then raise exception 'Existing routine ACL changed'; end if;
 end loop;
 for r in select c.oid,c.relacl from pg_class c join qa_existing_relation_acl old on old.oid=c.oid loop
  if r.relacl is distinct from (select relacl from qa_existing_relation_acl where oid=r.oid) then raise exception 'Existing relation ACL changed'; end if;
 end loop;
 foreach name in array array['community_equipment_only(text)','equipment_publication_allowed(text)','check_community_equipment_report()','guard_equipment_publication()','guard_withdrawn_equipment_master()'] loop
  if has_function_privilege('service_role',('public.'||name)::regprocedure,'EXECUTE') then raise exception 'New service_role EXECUTE leak: %',name; end if;
  if name in ('community_equipment_only(text)','equipment_publication_allowed(text)') then
   if not has_function_privilege('anon',('public.'||name)::regprocedure,'EXECUTE') or not has_function_privilege('authenticated',('public.'||name)::regprocedure,'EXECUTE') then raise exception 'Helper access missing'; end if;
  else
   if has_function_privilege('anon',('public.'||name)::regprocedure,'EXECUTE') or has_function_privilege('authenticated',('public.'||name)::regprocedure,'EXECUTE') then raise exception 'Internal trigger callable'; end if;
  end if;
 end loop;
 foreach role_name in array array['anon','authenticated','service_role'] loop
  if has_schema_privilege(role_name,'equipment_quarantine','USAGE') or has_schema_privilege(role_name,'equipment_quarantine','CREATE') then raise exception 'Archive schema permission leaked'; end if;
  for r in select oid from pg_class where relnamespace='equipment_quarantine'::regnamespace and relkind='r' loop
   if has_table_privilege(role_name,r.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then raise exception 'Archive table permission leaked'; end if;
  end loop;
 end loop;
 if has_column_privilege('authenticated','public.gym_equipment_reports','on_site_confirmed','INSERT') then raise exception 'Derived confirmation field client writable'; end if;
end $$;
set local role anon;
do $$ begin
 if exists(select 1 from public.gym_store_equipment g where public.community_equipment_only(g.store_id) and g.source_kind='official') then raise exception 'Public relation leak'; end if;
 if exists(select 1 from public.search_equipment('',0) x where not public.equipment_publication_allowed(x->'equipment'->>'id')) then raise exception 'Search leak'; end if;
 if has_schema_privilege('anon','equipment_quarantine','usage') then raise exception 'Archive readable'; end if;
end $$;
reset role;
-- Saved imports cannot recreate a relationship or overwrite a hidden master.
do $$ declare q record; before_count int; begin
 select * into q from equipment_quarantine.inventory limit 1;
 if q is null then raise exception 'QA needs seeded target inventory'; end if;
 select count(*) into before_count from public.gym_store_equipment;
 insert into public.gym_store_equipment select (jsonb_populate_record(null::public.gym_store_equipment,q.original)).*;
 if (select count(*) from public.gym_store_equipment)<>before_count then raise exception 'Reimport published'; end if;
end $$;
insert into public.gym_chains(id,name) values ('anytime-fitness','Synthetic Anytime') on conflict do nothing;
insert into public.gym_stores(id,chain_id,source_id,name) values ('qa-community-store','anytime-fitness','qa-community','Synthetic on-site store');
insert into auth.users(id) values ('00000000-0000-0000-0000-000000008001');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008001',true);
set local role authenticated;
-- A missing physical confirmation is rejected, even through the existing API.
do $$ begin
 begin
 insert into public.gym_equipment_reports(store_id,kind,equipment_name,comment) values ('qa-community-store','added','ダンベル','');
 raise exception 'Unchecked report accepted';
 exception when sqlstate '22023' then null; end;
end $$;
insert into public.gym_equipment_reports(store_id,kind,equipment_name,comment) values ('qa-community-store','added','ダンベル','[現地確認]Synthetic new report');
reset role;
do $$ declare cid uuid; rid uuid; begin
 select id into rid from public.gym_equipment_reports where store_id='qa-community-store';
 if not (select on_site_confirmed from public.gym_equipment_reports where id=rid) then raise exception 'Declaration not recorded'; end if;
 select candidate_id into cid from public.gym_change_evidence where source_ref=rid::text;
 perform set_config('setkeep.gym_candidate_id',cid::text,true);
 insert into public.gym_store_equipment(store_id,equipment_id,raw_name,source_kind,source) values ('qa-community-store','community:dumbbell','ダンベル','confirmed_report','{}');
 if not exists(select 1 from public.gym_store_equipment where store_id='qa-community-store') then raise exception 'Fresh confirmation cannot register'; end if;
 -- Old/official evidence must never re-publish.
 delete from public.gym_store_equipment where store_id='qa-community-store';
 update public.gym_change_evidence set observed_at='2020-01-01' where candidate_id=cid;
 begin
 insert into public.gym_store_equipment(store_id,equipment_id,raw_name,source_kind) values ('qa-community-store','community:dumbbell','ダンベル','confirmed_report');
 raise exception 'Old evidence allowed';
 exception when others then if sqlerrm='Old evidence allowed' then raise; end if; end;
end $$;

insert into auth.users(id) values ('00000000-0000-0000-0000-000000008002'),('00000000-0000-0000-0000-000000008003'),('00000000-0000-0000-0000-000000008004');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008002',true);
select public.confirm_training_equipment('qa-community-store','community-training:barbell','barbell_curl','qa-saved-1',true);
do $$ begin
 if exists(select 1 from public.gym_store_equipment where store_id='qa-community-store' and equipment_id='community-training:barbell') then raise exception 'One user published'; end if;
 if exists(select 1 from jsonb_array_elements(public.training_equipment_options('qa-community-store',array['barbell_curl'])) r cross join jsonb_array_elements(r->'options') o where o->>'equipment_id' not like 'community-training:%') then raise exception 'Training shows imported ID'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008003',true);
select public.confirm_training_equipment('qa-community-store','community-training:barbell','barbell_curl','qa-saved-2',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000008004',true);
select public.confirm_training_equipment('qa-community-store','community-training:barbell','barbell_curl','qa-saved-3',true);
do $$ begin
 if not exists(select 1 from public.gym_store_equipment where store_id='qa-community-store' and equipment_id='community-training:barbell' and source_kind='confirmed_report') then raise exception 'Fresh training confirmations failed auto-publish'; end if;
end $$;
rollback;
