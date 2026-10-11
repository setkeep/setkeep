-- Phase 1 integration and RLS test. Every fixture is rolled back.
begin;
-- Isolate phase-1 evaluation from the phase-2 application trigger. The
-- transaction rollback restores the trigger before this test returns.
alter table public.gym_change_candidates disable trigger gym_candidate_auto_apply;
insert into auth.users(id) values
 ('00000000-0000-4000-9001-000000000001'),
 ('00000000-0000-4000-9001-000000000002'),
 ('00000000-0000-4000-9001-000000000003'),
 ('00000000-0000-4000-9001-000000000004'),
 ('00000000-0000-4000-9001-000000000005'),
 ('00000000-0000-4000-9001-000000000006'),
 ('00000000-0000-4000-9001-000000000007'),
 ('00000000-0000-4000-9001-000000000008');
insert into public.app_admins(user_id) values ('00000000-0000-4000-9001-000000000008');
insert into public.gym_chains(id,name) values ('qa-candidate-chain','QA変更候補');
insert into public.gym_stores(id,chain_id,source_id,name)
values ('qa-candidate-store','qa-candidate-chain','one','試験店');
insert into public.equipment(id,name,normalized_name,category,needs_review) values
 ('qa-candidate-added','QAパワーラック','qaパワーラック','フリーウェイト',false),
 ('qa-candidate-removed','QA撤去マシン','qa撤去マシン','マシン',false);
insert into public.gym_store_equipment(store_id,equipment_id,raw_name,source_kind)
values ('qa-candidate-store','qa-candidate-removed','QA撤去マシン','confirmed_report');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-9001-000000000001';
insert into public.gym_equipment_reports(store_id,kind,equipment_name,comment)
values ('qa-candidate-store','added','ＱＡ　パワーラック','1回目');
insert into public.gym_equipment_reports(store_id,kind,equipment_name,comment)
values ('qa-candidate-store','added','QAパワーラック','追加の観察');
do $$ begin
 if exists(select 1 from public.gym_change_candidates) then
   raise exception 'Candidate visible to ordinary user';
 end if;
 if exists(select 1 from public.admin_gym_change_candidates) then
   raise exception 'Admin candidate view visible to ordinary user';
 end if;
 begin
   update public.gym_change_candidates set status='auto_applied'
   where store_id='qa-candidate-store';
   raise exception 'Candidate UPDATE was allowed';
 exception when insufficient_privilege then null; end;
 begin
   insert into public.gym_change_evidence(candidate_id,source_type,direction,weight,observed_at)
   values (gen_random_uuid(),'user_report','support',1,now());
   raise exception 'Evidence INSERT was allowed';
 exception when insufficient_privilege then null; end;
 begin
   update public.gym_auto_rule_config set min_unique_reporters=1 where change_type='added';
   raise exception 'Rule UPDATE was allowed';
 exception when insufficient_privilege then null; end;
 begin
   update public.gym_auto_decisions set decision='auto_applied';
   raise exception 'Decision UPDATE was allowed';
 exception when insufficient_privilege then null; end;
end $$;

set local request.jwt.claim.sub = '00000000-0000-4000-9001-000000000002';
insert into public.gym_equipment_reports(store_id,kind,equipment_name)
values ('qa-candidate-store','added','QAパワーラック');
set local request.jwt.claim.sub = '00000000-0000-4000-9001-000000000003';
insert into public.gym_equipment_reports(store_id,kind,equipment_name)
values ('qa-candidate-store','added','QAパワーラック');

set local request.jwt.claim.sub = '00000000-0000-4000-9001-000000000001';
insert into public.gym_equipment_reports(store_id,equipment_id,kind)
values ('qa-candidate-store','qa-candidate-removed','removed');
set local request.jwt.claim.sub = '00000000-0000-4000-9001-000000000002';
insert into public.gym_equipment_reports(store_id,equipment_id,kind)
values ('qa-candidate-store','qa-candidate-removed','removed');
set local request.jwt.claim.sub = '00000000-0000-4000-9001-000000000003';
insert into public.gym_equipment_reports(store_id,equipment_id,kind)
values ('qa-candidate-store','qa-candidate-removed','removed');

reset role;
do $$ declare c record; begin
 select * into c from public.gym_change_candidates
 where store_id='qa-candidate-store' and change_type='added';
 if c.status <> 'auto_ready' or c.unique_reporters <> 3
    or c.support_score <> 3 or c.equipment_id <> 'qa-candidate-added'
 then raise exception 'Three distinct added reporters must be auto_ready'; end if;
 if (select count(*) from public.gym_change_evidence where candidate_id=c.id) <> 4 then
   raise exception 'Distinct report history was lost'; end if;
 if (select count(*) from public.gym_change_candidates
     where store_id='qa-candidate-store' and change_type='added') <> 1 then
   raise exception 'Added candidate was duplicated'; end if;
 if not exists(select 1 from public.gym_auto_decisions d where d.candidate_id=c.id
     and d.decision='auto_ready' and d.algorithm_version='v1'
     and (d.rule_snapshot->>'min_unique_reporters')::integer=3) then
   raise exception 'Decision snapshot missing'; end if;
 select * into c from public.gym_change_candidates
 where store_id='qa-candidate-store' and change_type='removed';
 if c.status <> 'collecting' or c.unique_reporters <> 3 then
   raise exception 'Three removed reporters must remain collecting'; end if;
end $$;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-9001-000000000004';
insert into public.gym_equipment_reports(store_id,equipment_id,kind)
values ('qa-candidate-store','qa-candidate-removed','removed');
set local request.jwt.claim.sub = '00000000-0000-4000-9001-000000000005';
insert into public.gym_equipment_reports(store_id,equipment_id,kind,equipment_name)
values ('qa-candidate-store','qa-candidate-removed','wrong_name','QA正しい名称');
set local request.jwt.claim.sub = '00000000-0000-4000-9001-000000000006';
insert into public.gym_equipment_reports(store_id,kind,comment)
values ('qa-candidate-store','other','その他の問題');
set local request.jwt.claim.sub = '00000000-0000-4000-9001-000000000007';
insert into public.gym_equipment_reports(store_id,equipment_id,kind)
values ('qa-candidate-store','qa-candidate-removed','not_present');
set local request.jwt.claim.sub = '00000000-0000-4000-9001-000000000005';
insert into public.gym_equipment_reports(store_id,kind,equipment_name)
values ('qa-candidate-store','added','QA未登録マシン');
set local request.jwt.claim.sub = '00000000-0000-4000-9001-000000000006';
insert into public.gym_equipment_reports(store_id,kind,equipment_name)
values ('qa-candidate-store','added','QA未登録マシン');
set local request.jwt.claim.sub = '00000000-0000-4000-9001-000000000007';
insert into public.gym_equipment_reports(store_id,kind,equipment_name)
values ('qa-candidate-store','added','QA未登録マシン');

reset role;
do $$ declare removed_candidate uuid; begin
 select id into removed_candidate from public.gym_change_candidates
 where store_id='qa-candidate-store' and change_type='removed';
 if (select status from public.gym_change_candidates where id=removed_candidate) <> 'auto_ready'
 then raise exception 'Four distinct removed reporters must be auto_ready'; end if;
 if not exists(select 1 from public.gym_change_candidates
   where store_id='qa-candidate-store' and change_type='wrong_name' and status='needs_review')
 then raise exception 'Wrong name must need review'; end if;
 if not exists(select 1 from public.gym_change_candidates
   where store_id='qa-candidate-store' and change_type='other' and status='needs_review')
 then raise exception 'Other must need review'; end if;
 if not exists(select 1 from public.gym_change_candidates
   where store_id='qa-candidate-store' and change_type='not_present' and status<>'auto_ready')
 then raise exception 'Not-present must not imply removal'; end if;
 if not exists(select 1 from public.gym_change_candidates
   where store_id='qa-candidate-store' and change_type='added'
     and candidate_key=public.gym_search_text('QA未登録マシン')
     and status='needs_review' and unique_reporters=3 and equipment_id is null)
 then raise exception 'Unknown equipment must need review even with three reporters'; end if;
 if not exists(select 1 from public.gym_store_equipment
   where store_id='qa-candidate-store' and equipment_id='qa-candidate-removed' and available)
 then raise exception 'Master changed at auto_ready'; end if;
 if exists(select 1 from public.gym_store_equipment
   where store_id='qa-candidate-store' and equipment_id='qa-candidate-added')
 then raise exception 'Added equipment was automatically inserted'; end if;

 insert into public.gym_change_evidence
   (candidate_id,source_type,source_ref,direction,weight,observed_at,data)
 values (removed_candidate,'official','qa-candidate-opposition','oppose',1,now(),'{}');
 perform public.reevaluate_gym_change_candidate(removed_candidate);
 if not exists(select 1 from public.gym_change_candidates where id=removed_candidate
   and status='needs_review' and oppose_score=1)
 then raise exception 'Conflicting evidence must need review'; end if;
 if not exists(select 1 from public.gym_auto_decisions
   where candidate_id=removed_candidate and reason_code='conflicting_evidence')
 then raise exception 'Conflicting decision was not audited'; end if;
end $$;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-9001-000000000008';
do $$ begin
 if not public.is_report_admin() then raise exception 'Admin fixture failed'; end if;
 if (select count(*) from public.gym_change_candidates
   where store_id='qa-candidate-store') <> 6 then
   raise exception 'Admin cannot see candidates'; end if;
 if (select count(*) from public.gym_change_evidence e join public.gym_change_candidates c
     on c.id=e.candidate_id where c.store_id='qa-candidate-store') <> 15 then
   raise exception 'Admin cannot see all evidence'; end if;
 if (select count(*) from public.admin_gym_change_candidates
     where store_id='qa-candidate-store' and store_name='QA変更候補 試験店') <> 6 then
   raise exception 'Candidate admin view does not resolve store names'; end if;
end $$;

-- Rejecting a report removes its vote without deleting the Evidence audit row.
select public.update_admin_report('equipment',id,status,'rejected','QA不正確')
from public.gym_equipment_reports where store_id='qa-candidate-store' and kind='added'
  and user_id='00000000-0000-4000-9001-000000000003';
reset role;
do $$ declare old_id uuid; begin
 select id into old_id from public.gym_change_candidates
 where store_id='qa-candidate-store' and change_type='added'
   and candidate_key=public.gym_search_text('QAパワーラック');
 if not exists(select 1 from public.gym_change_candidates
   where id=old_id and status='collecting' and unique_reporters=2
     and support_score=2)
 then raise exception 'Rejected report still contributes to candidate score'; end if;
 if (select count(*) from public.gym_change_evidence where candidate_id=old_id) <> 4
 then raise exception 'Rejected report Evidence audit was removed'; end if;
 if not exists(select 1 from public.gym_auto_decisions
   where candidate_id=old_id and reason_code='insufficient_support')
 then raise exception 'Rejection reevaluation was not audited'; end if;
 update public.gym_change_candidates set status='admin_applied',resolved_at=now()
 where id=old_id;
end $$;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-9001-000000000004';
insert into public.gym_equipment_reports(store_id,kind,equipment_name)
values ('qa-candidate-store','added','QAパワーラック');
reset role;
do $$ begin
 if (select count(*) from public.gym_change_candidates
   where store_id='qa-candidate-store' and change_type='added'
     and candidate_key=public.gym_search_text('QAパワーラック')) <> 2
 then raise exception 'Resolved candidate did not permit a new occurrence'; end if;
 if not exists(select 1 from public.gym_change_candidates
   where store_id='qa-candidate-store' and change_type='added'
     and candidate_key=public.gym_search_text('QAパワーラック')
     and status='collecting' and unique_reporters=1)
 then raise exception 'New occurrence did not start collecting'; end if;
end $$;
rollback;
select 'candidate aggregation, thresholds, opposition, audit, master immutability and RLS passed' as result;
