begin;
insert into public.gym_chains(id,name,search_aliases) values ('qa-detail','テストチェーン',array['試験ジム']);
insert into public.gym_stores(id,chain_id,source_id,name,city,station,equipment_status,active) values
 ('qa-exact','qa-detail','a','松戸','住所だけの市','駅だけの駅','not_collected',true),
 ('qa-prefix','qa-detail','b','松戸東口',null,null,'partial',true),
 ('qa-partial','qa-detail','c','新松戸',null,null,'published',true),
 ('qa-closed','qa-detail','d','閉店松戸',null,null,'published',false);
insert into public.equipment(id,name,normalized_name,category) values
 ('qa-rack','ラック','ラック','フリーウェイト'),('qa-bench','ベンチ','ベンチ','フリーウェイト');
insert into public.gym_store_equipment(store_id,equipment_id,raw_name,quantity,unavailable_quantity) values
 ('qa-exact','qa-rack','ラック',3,1),('qa-exact','qa-bench','ベンチ',null,null);
insert into public.equipment_exercise_mapping(equipment_id,exercise_id,rationale) values
 ('qa-rack','barbell_squat','QA'),('qa-bench','barbell_squat','QA duplicate');
insert into public.exercise_equipment_rules(id,exercise_id) values ('qa-rule','bench_press');
insert into public.exercise_equipment_rule_items values ('qa-rule','qa-rack'),('qa-rule','qa-bench');
set local role anon;
do $$ declare names text[]; doc jsonb; begin
 select array_agg(j->>'id') into names from public.search_gym_stores_v2('松戸',0,'qa-detail') j;
 if names<>array['qa-exact','qa-prefix','qa-partial'] then raise exception 'Rank/closed mismatch %',names; end if;
 if not exists(select 1 from public.search_gym_stores_v2('住所だけの市') j where j->>'id'='qa-exact') or
    exists(select 1 from public.search_gym_stores_v2('駅だけの駅')) then raise exception 'Location search mismatch'; end if;
 if not exists(select 1 from public.search_gym_stores_v2('試験ジム')) then raise exception 'Chain alias missing'; end if;
 if (select count(*) from public.gym_store_exercise_ids('qa-exact'))<>2 then raise exception 'Duplicates or missing rule'; end if;
 doc:=public.gym_store_detail('qa-exact');
 if jsonb_array_length(doc->'equipment')<>2 or jsonb_array_length(doc->'evidence')<>3
 then raise exception 'Detail/evidence mismatch'; end if;
end $$;
reset role;
update public.gym_store_equipment set unavailable_quantity=3 where store_id='qa-exact' and equipment_id='qa-rack';
do $$ begin
 if exists(select 1 from public.gym_store_exercise_ids('qa-exact') where exercise_id='bench_press')
 then raise exception 'All broken equipment satisfied rule'; end if;
end $$;
update public.gym_store_equipment set unavailable_quantity=1 where store_id='qa-exact' and equipment_id='qa-rack';
update public.gym_store_equipment set available=false where store_id='qa-exact' and equipment_id='qa-bench';
do $$ begin
 if exists(select 1 from public.gym_store_exercise_ids('qa-exact') where exercise_id='bench_press')
 then raise exception 'Unavailable equipment satisfied rule'; end if;
end $$;
update public.gym_store_equipment set source_kind='admin' where store_id='qa-exact' and equipment_id='qa-rack';
update public.gym_store_equipment set source_kind='official',quantity=5 where store_id='qa-exact' and equipment_id='qa-rack';
do $$ begin
 if (select quantity from public.gym_store_equipment where store_id='qa-exact' and equipment_id='qa-rack')<>3
 then raise exception 'Lower source overwrote admin'; end if;
end $$;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000008');
set local request.jwt.claim.sub='00000000-0000-4000-8000-000000000008';
set local role authenticated;
insert into public.gym_equipment_reports(store_id,equipment_id,kind,comment) values ('qa-exact','qa-rack','other','確認してください');
insert into public.gym_equipment_reports(store_id,equipment_id,kind,comment) values ('qa-exact','qa-rack','other','確認してください');
do $$ begin
 if (select count(*) from public.gym_equipment_reports where store_id='qa-exact')<>1 then raise exception 'Duplicate open reports'; end if;
end $$;
reset role;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000009');
insert into public.app_admins(user_id) values ('00000000-0000-4000-8000-000000000009');
set local request.jwt.claim.sub='00000000-0000-4000-8000-000000000009';
set local role authenticated;
select public.update_admin_report('equipment',id,status,'rejected','QA確認済み') from public.gym_equipment_reports where store_id='qa-exact';
set local request.jwt.claim.sub='00000000-0000-4000-8000-000000000008';
set local role authenticated;
insert into public.gym_equipment_reports(store_id,equipment_id,kind,comment) values ('qa-exact','qa-rack','other','確認してください');
do $$ begin
 if (select count(*) from public.gym_equipment_reports where store_id='qa-exact')<>2 then raise exception 'New change suppressed'; end if;
end $$;
reset role;
delete from public.gym_store_equipment where store_id='qa-exact' and equipment_id='qa-bench';
do $$ begin
 if not exists(select 1 from public.equipment where id='qa-bench') then raise exception 'Master deleted'; end if;
 if not exists(select 1 from public.gym_equipment_changes where store_id='qa-exact' and operation='DELETE')
 then raise exception 'Missing removal history'; end if;
end $$;
rollback;
select 'gym detail/search/evidence/availability/reports/history passed' as result;
