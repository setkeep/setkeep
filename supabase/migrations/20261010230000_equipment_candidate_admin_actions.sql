begin;
-- Candidate holds do not change the open grouping key or global auto rules.
alter table public.gym_change_candidates
 add column admin_held boolean not null default false,
 add column admin_hold_note text not null default '',
 add column admin_held_at timestamptz,
 add column admin_held_by uuid references auth.users(id) on delete set null,
 add column review_version bigint not null default 1;
create function public.bump_gym_candidate_review_version() returns trigger
language plpgsql set search_path='' as $$ begin
 new.review_version := old.review_version + 1; return new;
end $$;
revoke all on function public.bump_gym_candidate_review_version() from public,anon,authenticated,service_role;
create trigger gym_candidate_review_version before update on public.gym_change_candidates
 for each row execute function public.bump_gym_candidate_review_version();

-- One transaction advisory lock precedes every equipment ingestion/review path.
-- Coarse serialization deliberately avoids lock-order inversions across different
-- candidates targeting the same equipment and automatic trigger re-entry.
create function public.lock_gym_equipment_review() returns void
language sql volatile set search_path='' as $$
 select pg_advisory_xact_lock(104649, 20261010);
$$;
revoke all on function public.lock_gym_equipment_review() from public,anon,authenticated,service_role;

alter function public.ingest_gym_equipment_report(uuid) rename to ingest_gym_equipment_report_before_admin_review;
revoke all on function public.ingest_gym_equipment_report_before_admin_review(uuid) from public,anon,authenticated;
create function public.ingest_gym_equipment_report(report_id uuid) returns void
language plpgsql security definer set search_path='' as $$ begin
perform public.lock_gym_equipment_review();
perform public.ingest_gym_equipment_report_before_admin_review(report_id);
end $$;
revoke all on function public.ingest_gym_equipment_report(uuid) from public,anon,authenticated;

alter function public.confirm_training_equipment(text,text,text,text,boolean,uuid) rename to confirm_training_equipment_before_admin_review;
revoke all on function public.confirm_training_equipment_before_admin_review(text,text,text,text,boolean,uuid) from public,anon,authenticated;
create function public.confirm_training_equipment(target_store text,target_equipment text,target_exercise text,record_key text,performed boolean,expected_user uuid default auth.uid()) returns void
language plpgsql security definer set search_path='' as $$ begin
perform public.lock_gym_equipment_review();
perform public.confirm_training_equipment_before_admin_review(target_store,target_equipment,target_exercise,record_key,performed,expected_user);
end $$;
revoke all on function public.confirm_training_equipment(text,text,text,text,boolean,uuid) from public,anon,authenticated;
grant execute on function public.confirm_training_equipment(text,text,text,text,boolean,uuid) to authenticated;

alter function public.capture_official_observation(uuid,uuid,text,text,text,jsonb,boolean) rename to capture_official_observation_before_admin_review;
revoke all on function public.capture_official_observation_before_admin_review(uuid,uuid,text,text,text,jsonb,boolean) from public,anon,authenticated;
create function public.capture_official_observation(source_id uuid,snapshot_id uuid,change text,subject text,equipment_id text,proposal jsonb,review_required boolean) returns uuid
language plpgsql security definer set search_path='' as $$ begin
if change not like 'store_%' then perform public.lock_gym_equipment_review(); end if;
return public.capture_official_observation_before_admin_review(source_id,snapshot_id,change,subject,equipment_id,proposal,review_required);
end $$;
revoke all on function public.capture_official_observation(uuid,uuid,text,text,text,jsonb,boolean) from public,anon,authenticated;

alter function public.reevaluate_gym_change_candidate(uuid) rename to reevaluate_gym_change_candidate_before_admin_review;
revoke all on function public.reevaluate_gym_change_candidate_before_admin_review(uuid) from public,anon,authenticated;
create function public.reevaluate_gym_change_candidate(target_id uuid) returns void
language plpgsql security definer set search_path='' as $$ begin
-- Store workflows keep their existing 429 lock order, separate from equipment.
if exists(select 1 from public.gym_change_candidates where id=target_id and entity_type='store') then
 perform public.reevaluate_gym_change_candidate_before_admin_review(target_id); return;
end if;
perform public.lock_gym_equipment_review();
if exists(select 1 from public.gym_change_candidates where id=target_id and admin_held) then return; end if;
perform public.reevaluate_gym_change_candidate_before_admin_review(target_id);
end $$;
revoke all on function public.reevaluate_gym_change_candidate(uuid) from public,anon,authenticated;

alter function public.reevaluate_gym_equipment_candidate(uuid) rename to reevaluate_gym_equipment_candidate_before_admin_review;
revoke all on function public.reevaluate_gym_equipment_candidate_before_admin_review(uuid) from public,anon,authenticated;
create function public.reevaluate_gym_equipment_candidate(target_id uuid) returns void
language plpgsql security definer set search_path='' as $$ begin
perform public.lock_gym_equipment_review();
if exists(select 1 from public.gym_change_candidates where id=target_id and admin_held) then return; end if;
perform public.reevaluate_gym_equipment_candidate_before_admin_review(target_id);
end $$;
revoke all on function public.reevaluate_gym_equipment_candidate(uuid) from public,anon,authenticated;

alter function public.apply_gym_change_candidate(uuid) rename to apply_gym_change_candidate_before_admin_review;
revoke all on function public.apply_gym_change_candidate_before_admin_review(uuid) from public,anon,authenticated;
create function public.apply_gym_change_candidate(target_id uuid) returns void
language plpgsql security definer set search_path='' as $$ begin
-- Store workflows keep their existing 429 lock order, separate from equipment.
if exists(select 1 from public.gym_change_candidates where id=target_id and entity_type='store') then
 perform public.apply_gym_change_candidate_before_admin_review(target_id); return;
end if;
perform public.lock_gym_equipment_review();
if exists(select 1 from public.gym_change_candidates where id=target_id and admin_held) then return; end if;
perform public.apply_gym_change_candidate_before_admin_review(target_id);
end $$;
revoke all on function public.apply_gym_change_candidate(uuid) from public,anon,authenticated;

alter function public.apply_gym_presence_candidate(uuid) rename to apply_gym_presence_candidate_before_admin_review;
revoke all on function public.apply_gym_presence_candidate_before_admin_review(uuid) from public,anon,authenticated;
create function public.apply_gym_presence_candidate(target_id uuid) returns void
language plpgsql security definer set search_path='' as $$ begin
perform public.lock_gym_equipment_review();
if exists(select 1 from public.gym_change_candidates where id=target_id and admin_held) then return; end if;
perform public.apply_gym_presence_candidate_before_admin_review(target_id);
end $$;
revoke all on function public.apply_gym_presence_candidate(uuid) from public,anon,authenticated;

alter function public.apply_gym_state_candidate(uuid) rename to apply_gym_state_candidate_before_admin_review;
revoke all on function public.apply_gym_state_candidate_before_admin_review(uuid) from public,anon,authenticated;
create function public.apply_gym_state_candidate(target_id uuid) returns void
language plpgsql security definer set search_path='' as $$ begin
perform public.lock_gym_equipment_review();
if exists(select 1 from public.gym_change_candidates where id=target_id and admin_held) then return; end if;
perform public.apply_gym_state_candidate_before_admin_review(target_id);
end $$;
revoke all on function public.apply_gym_state_candidate(uuid) from public,anon,authenticated;

create or replace function public.rollback_gym_equipment_candidate(target_id uuid, reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  c public.gym_change_candidates%rowtype;
  a public.gym_auto_applications%rowtype;
  current_row public.gym_store_equipment%rowtype;
  original public.gym_store_equipment%rowtype;
begin
  perform public.lock_gym_equipment_review();
  if not public.is_report_admin() then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  if nullif(trim(reason), '') is null then raise exception 'Rollback reason required'; end if;
  select * into c from public.gym_change_candidates where id = target_id for update;
  if not found or c.status not in ('auto_applied','admin_applied') then
    raise exception 'Candidate is not applied';
  end if;
  select * into a from public.gym_auto_applications
    where candidate_id = target_id for update;
  if not found or a.rolled_back_at is not null then
    raise exception 'Application is already rolled back';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(a.store_id || ':' || a.equipment_id, 422));
  select * into current_row from public.gym_store_equipment
    where store_id = a.store_id and equipment_id = a.equipment_id for update;
  if not found or to_jsonb(current_row) <> a.after_data then
    raise exception 'Master changed since application; review manually';
  end if;
  perform set_config('setkeep.gym_candidate_id', c.id::text, true);
  perform set_config('setkeep.gym_application_id', a.id::text, true);
  if a.before_data is null then
    delete from public.gym_store_equipment
      where store_id = a.store_id and equipment_id = a.equipment_id;
  else
    select * into original from jsonb_populate_record(
      null::public.gym_store_equipment, a.before_data);
    update public.gym_store_equipment set
      quantity = original.quantity, available = original.available,
      raw_name = original.raw_name, source_url = original.source_url,
      checked_at = original.checked_at, source = original.source,
      updated_at = original.updated_at,
      unavailable_quantity = original.unavailable_quantity,
      source_kind = original.source_kind,
      presence_status = original.presence_status
    where store_id = a.store_id and equipment_id = a.equipment_id;
    select * into current_row from public.gym_store_equipment
      where store_id = a.store_id and equipment_id = a.equipment_id;
    if to_jsonb(current_row) <> a.before_data then
      raise exception 'Rollback did not restore the original Master row';
    end if;
  end if;
  update public.gym_auto_applications set
    rolled_back_at = now(), rollback_reason = trim(reason),
    rolled_back_by = auth.uid() where id = a.id;
  update public.gym_change_candidates set
    status = 'rolled_back', resolved_at = coalesce(resolved_at, now()),
    updated_at = now() where id = c.id;
  insert into public.gym_auto_decisions
    (candidate_id, decision, reason_code, score_snapshot, rule_snapshot, algorithm_version)
  values (c.id, 'rolled_back', 'admin_rollback',
    jsonb_build_object('application_id', a.id, 'rollback_reason', trim(reason)),
    (select to_jsonb(r) from public.gym_auto_rule_config r where r.change_type = c.change_type),
    c.algorithm_version);
  perform set_config('setkeep.gym_candidate_id', '', true);
  perform set_config('setkeep.gym_application_id', '', true);
end $$;

create or replace function public.review_report_guard() returns trigger
language plpgsql set search_path = '' as $$
declare marked_id uuid := nullif(current_setting('setkeep.gym_candidate_id', true), '')::uuid;
begin
  if tg_table_name = 'gym_equipment_reports'
    and current_user = 'postgres' and marked_id is not null
    and old.status in ('pending', 'reviewing') and new.status = 'applied'
    and exists (
      select 1 from public.gym_change_candidates c
      join public.gym_change_evidence e on e.candidate_id = c.id
      where c.id = marked_id and (c.status = 'auto_applied' or (c.status='admin_applied' and public.is_report_admin()))
        and e.source_type = 'user_report' and e.source_ref = old.id::text
    )
  then
    new.reviewed_by = case when exists(select 1 from public.gym_change_candidates where id=marked_id and status='admin_applied') then auth.uid() else null end;
    new.reviewed_at = now();
    return new;
  end if;
  if not public.is_report_admin() then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  if new.status <> old.status and not (
    (old.status = 'pending' and new.status in ('reviewing', 'rejected'))
    or (old.status = 'reviewing' and new.status in ('applied', 'rejected'))
  ) then raise exception 'Invalid report transition'; end if;
  if new.status = 'rejected' and length(trim(new.admin_note)) = 0 then
    raise exception 'Rejection note required';
  end if;
  new.reviewed_by = auth.uid();
  new.reviewed_at = now();
  return new;
end $$;

create table public.gym_equipment_review_operations (
 operation_id uuid primary key,
 candidate_id uuid not null references public.gym_change_candidates(id),
 actor_id uuid references auth.users(id) on delete set null,
 action text not null check(action in ('apply','reject','hold','release','rollback')),
 request jsonb not null,
 result jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table public.gym_equipment_review_operations enable row level security;
revoke all on public.gym_equipment_review_operations from public,anon,authenticated,service_role;
grant select on public.gym_equipment_review_operations to authenticated;
create policy equipment_review_operations_admin_read on public.gym_equipment_review_operations
 for select to authenticated using(public.is_report_admin());

-- Read only; excludes reporter identifiers and free text. selected_equipment_id
-- lets the admin inspect the existing master before confirming a name-only added report.
create function public.get_admin_equipment_candidate(target_id uuid, selected_equipment_id text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.gym_change_candidates%rowtype; g public.gym_store_equipment%rowtype; eid text;
begin
 if not public.is_report_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 select * into c from public.gym_change_candidates where id=target_id and entity_type='store_equipment';
 if not found then raise exception 'Equipment candidate required' using errcode='22023'; end if;
 eid:=coalesce(selected_equipment_id,c.equipment_id);
 if selected_equipment_id is not null and (c.change_type<>'added' or c.status not in ('collecting','needs_review','auto_ready')) and selected_equipment_id is distinct from c.equipment_id then
 raise exception 'Equipment mismatch' using errcode='22023'; end if;
 select * into g from public.gym_store_equipment where store_id=c.store_id and equipment_id=eid;
 return jsonb_build_object('candidate_id',c.id,'store_id',c.store_id,'equipment_id',c.equipment_id,
 'selected_equipment_id',eid,'change_type',c.change_type,'proposed_value',c.proposed_value-'comment',
 'status',c.status,'review_version',c.review_version,'admin_held',c.admin_held,
 'admin_hold_note',c.admin_hold_note,'first_seen_at',c.first_seen_at,'last_seen_at',c.last_seen_at,
 'support_score',c.support_score,'oppose_score',c.oppose_score,'unique_reporters',c.unique_reporters,
 'master_present',g.store_id is not null,'master_updated_at',g.updated_at,
 'current_data',case when g.store_id is not null then to_jsonb(g)-'source' else null end);
end $$;
revoke all on function public.get_admin_equipment_candidate(uuid,text) from public,anon,service_role;
grant execute on function public.get_admin_equipment_candidate(uuid,text) to authenticated;

create function public.review_gym_equipment_candidate(
 target_id uuid, action text, expected_status text, expected_version bigint,
 operation_id uuid, note text, expected_master_present boolean,
 expected_master_updated_at timestamptz,
 selected_equipment_id text default null, mapping_confirmed boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 c public.gym_change_candidates%rowtype; g public.gym_store_equipment%rowtype;
 after_row public.gym_store_equipment%rowtype; prior public.gym_equipment_review_operations%rowtype;
 request_value jsonb; result_value jsonb; eid text; application_id uuid:=gen_random_uuid();
 has_row boolean; qty int; unavailable int; kind text; updated_status text;
begin
 if not public.is_report_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 if operation_id is null or action is null or action not in ('apply','reject','hold','release','rollback')
 or expected_status is null or expected_version is null or expected_master_present is null
 or note is null or length(trim(note)) not between 1 and 4000 then
 raise exception 'Invalid review request; reason required' using errcode='22023'; end if;
 request_value:=jsonb_build_object('candidate_id',target_id,'action',action,'expected_status',expected_status,
 'expected_version',expected_version,'note',trim(note),'expected_master_present',expected_master_present,
 'expected_master_updated_at',expected_master_updated_at,'selected_equipment_id',selected_equipment_id,
 'mapping_confirmed',mapping_confirmed);
 perform public.lock_gym_equipment_review();
 select * into prior from public.gym_equipment_review_operations o where o.operation_id=review_gym_equipment_candidate.operation_id;
 if found then
 if prior.actor_id is distinct from auth.uid() or prior.request is distinct from request_value then
 raise exception 'Operation ID reused with different request' using errcode='22023'; end if;
 return prior.result;
 end if;
 select * into c from public.gym_change_candidates where id=target_id and entity_type='store_equipment' for update;
 if not found then raise exception 'Equipment candidate required' using errcode='22023'; end if;
 if c.status is distinct from expected_status or c.review_version is distinct from expected_version then
 raise exception 'Candidate changed; reload required' using errcode='40001'; end if;
 eid:=coalesce(selected_equipment_id,c.equipment_id);
 if (c.change_type<>'added' or action='rollback') and selected_equipment_id is not null and selected_equipment_id is distinct from c.equipment_id then
 raise exception 'Equipment mismatch' using errcode='22023'; end if;
 -- Same lock ordering as automatic/ingestion paths: workflow, candidate, equipment.
 perform pg_advisory_xact_lock(hashtextextended(c.store_id||':'||coalesce(eid,c.candidate_key),422));
 select * into g from public.gym_store_equipment where store_id=c.store_id and equipment_id=eid for update;
 has_row:=found;
 if has_row is distinct from expected_master_present or (has_row and g.updated_at is distinct from expected_master_updated_at)
 or (not has_row and expected_master_updated_at is not null) then
 raise exception 'Master changed; reload required' using errcode='40001'; end if;
 if action='rollback' then
 perform public.rollback_gym_equipment_candidate(c.id,trim(note));
 else
 if c.status not in ('collecting','needs_review','auto_ready') then
 raise exception 'Candidate already resolved' using errcode='40001'; end if;
 if action='hold' then
 update public.gym_change_candidates set admin_held=true,admin_hold_note=trim(note),
 admin_held_at=clock_timestamp(),admin_held_by=auth.uid(),updated_at=clock_timestamp() where id=c.id;
 elsif action='release' then
 if not c.admin_held then raise exception 'Candidate is not held' using errcode='22023'; end if;
 update public.gym_change_candidates set admin_held=false,admin_hold_note='',admin_held_at=null,admin_held_by=null,
 updated_at=clock_timestamp() where id=c.id;
 -- Explicit release resumes normal evaluation and may automatically apply now.
 perform public.reevaluate_gym_change_candidate(c.id);
 perform public.apply_gym_change_candidate(c.id);
 elsif action='reject' then
 update public.gym_change_candidates set status='rejected',resolved_at=clock_timestamp(),updated_at=clock_timestamp() where id=c.id;
 update public.gym_equipment_reports r set status='rejected',admin_note=trim(note)
 from public.gym_change_evidence e where e.candidate_id=c.id and e.source_type='user_report'
 and e.source_ref=r.id::text and r.status in ('pending','reviewing');
 elsif action='apply' then
 if c.admin_held then raise exception 'Release hold before applying' using errcode='22023'; end if;
 if c.change_type not in ('added','removed','not_present','quantity_changed','temporarily_unavailable','available_again') then
 raise exception 'This type needs separate master review' using errcode='22023'; end if;
 if eid is null or not exists(select 1 from public.equipment where id=eid and not needs_review) then
 raise exception 'Reviewed equipment ID required' using errcode='22023'; end if;
 if c.change_type='added' and (selected_equipment_id is null or mapping_confirmed is distinct from true) then
 raise exception 'Explicit equipment mapping confirmation required' using errcode='22023'; end if;
 if not exists(select 1 from public.gym_stores where id=c.store_id and active) then
 raise exception 'Store must be active' using errcode='22023'; end if;
 if c.change_type<>'added' and not has_row then raise exception 'Master required' using errcode='22023'; end if;
 if c.change_type in ('quantity_changed','temporarily_unavailable','available_again') and g.presence_status<>'present' then
 raise exception 'Equipment is removed' using errcode='22023'; end if;
 kind:=case when c.change_type='not_present' then 'removed' else c.change_type end;
 update public.gym_change_candidates set equipment_id=eid,status='admin_applied',resolved_at=clock_timestamp(),updated_at=clock_timestamp() where id=c.id;
 perform set_config('setkeep.gym_candidate_id',c.id::text,true);
 perform set_config('setkeep.gym_application_id',application_id::text,true);
 if kind='added' and not has_row then
 insert into public.gym_store_equipment(store_id,equipment_id,raw_name,available,presence_status,source_kind,checked_at,updated_at,source)
 select c.store_id,eid,name,true,'present','admin',clock_timestamp(),clock_timestamp(),
 jsonb_build_object('candidate_id',c.id,'manual_applied',true) from public.equipment where id=eid;
 elsif kind='added' then
 update public.gym_store_equipment set presence_status='present',available=true,
 unavailable_quantity=case when quantity is null then null else 0 end,source_kind='admin',checked_at=clock_timestamp(),updated_at=clock_timestamp()
 where store_id=c.store_id and equipment_id=eid;
 elsif kind='removed' then
 update public.gym_store_equipment set presence_status='removed',available=false,source_kind='admin',checked_at=clock_timestamp(),updated_at=clock_timestamp()
 where store_id=c.store_id and equipment_id=eid;
 elsif kind='quantity_changed' then
 qty:=(c.proposed_value->>'reported_quantity')::int;
 if qty is null or qty not between 1 and 100 or coalesce(g.unavailable_quantity,0)>qty then
 raise exception 'Invalid total quantity' using errcode='22023'; end if;
 update public.gym_store_equipment set quantity=qty,source_kind='admin',checked_at=clock_timestamp(),updated_at=clock_timestamp()
 where store_id=c.store_id and equipment_id=eid;
 else
 if kind='available_again' then unavailable:=case when g.quantity is null then null else 0 end;
 elsif c.proposed_value->>'unavailable_scope'='all' then unavailable:=g.quantity;
 elsif c.proposed_value->>'unavailable_scope'='partial' then
 unavailable:=(c.proposed_value->>'reported_unavailable_quantity')::int;
 if g.quantity is null or unavailable is null or unavailable<1 or unavailable>=g.quantity then
 raise exception 'Invalid partial quantity' using errcode='22023'; end if;
 else raise exception 'Invalid unavailability scope' using errcode='22023'; end if;
 update public.gym_store_equipment set available=(kind='available_again' or c.proposed_value->>'unavailable_scope'='partial'),
 unavailable_quantity=unavailable,source_kind='admin',checked_at=clock_timestamp(),updated_at=clock_timestamp()
 where store_id=c.store_id and equipment_id=eid;
 end if;
 select * into strict after_row from public.gym_store_equipment where store_id=c.store_id and equipment_id=eid;
 insert into public.gym_auto_applications(id,candidate_id,store_id,equipment_id,change_type,before_data,after_data,application_type)
 values(application_id,c.id,c.store_id,eid,kind,case when has_row then to_jsonb(g) else null end,to_jsonb(after_row),'admin');
 update public.gym_equipment_reports r set status='applied',admin_note=trim(note)
 from public.gym_change_evidence e where e.candidate_id=c.id and e.source_type='user_report'
 and e.source_ref=r.id::text and r.status in ('pending','reviewing');
 perform set_config('setkeep.gym_candidate_id','',true);
 perform set_config('setkeep.gym_application_id','',true);
 end if;
 end if;
 result_value:=public.get_admin_equipment_candidate(c.id,eid);
 insert into public.gym_equipment_review_operations(operation_id,candidate_id,actor_id,action,request,result)
 values(operation_id,c.id,auth.uid(),action,request_value,result_value);
 select status into updated_status from public.gym_change_candidates where id=c.id;
 insert into public.gym_auto_decisions(candidate_id,decision,reason_code,score_snapshot,rule_snapshot,algorithm_version)
 values(c.id,updated_status,'admin_'||action,jsonb_build_object('operation_id',operation_id,'note',trim(note),'actor_id',auth.uid()),'{}','admin-v1');
 return result_value;
end $$;
revoke all on function public.review_gym_equipment_candidate(uuid,text,text,bigint,uuid,text,boolean,timestamptz,text,boolean) from public,anon,service_role;
grant execute on function public.review_gym_equipment_candidate(uuid,text,text,bigint,uuid,text,boolean,timestamptz,text,boolean) to authenticated;

-- Preserve rank protection except the exact audited rollback snapshot.
create or replace function public.protect_gym_equipment_source() returns trigger
language plpgsql set search_path='' as $$
declare ranks text[]:=array['unconfirmed_report','confirmed_report','official','admin'];
 marked_id uuid:=nullif(current_setting('setkeep.gym_candidate_id',true),'')::uuid;
 app_id uuid:=nullif(current_setting('setkeep.gym_application_id',true),'')::uuid;
begin
 if array_position(ranks,new.source_kind)<array_position(ranks,old.source_kind) then
 if current_user='postgres' and marked_id is not null and exists(
 select 1 from public.gym_change_candidates c where c.id=marked_id and c.store_id=new.store_id
 and c.equipment_id=new.equipment_id and c.status in ('auto_ready','auto_applied')) then return new; end if;
 if current_user='postgres' and public.is_report_admin() and exists(
 select 1 from public.gym_auto_applications a join public.gym_change_candidates c on c.id=a.candidate_id
 where a.id=app_id and c.id=marked_id and c.status in ('auto_applied','admin_applied')
 and a.rolled_back_at is null and a.before_data=to_jsonb(new) and a.after_data=to_jsonb(old)) then return new; end if;
 return old;
 end if;
 return new;
end $$;
-- Force report review through the RPC so the workflow lock is acquired before
-- any report row lock. Existing Flutter already uses this RPC.
alter function public.update_admin_report(text,uuid,text,text,text) rename to update_admin_report_before_admin_review;
revoke all on function public.update_admin_report_before_admin_review(text,uuid,text,text,text) from public,anon,authenticated;
revoke update(status,admin_note) on public.gym_equipment_reports from authenticated;
create function public.update_admin_report(report_type_value text,report_id uuid,expected_status text,new_status text,note text)
returns void language plpgsql security definer set search_path='' as $$ begin
 if not public.is_report_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 perform public.lock_gym_equipment_review();
 perform public.update_admin_report_before_admin_review(report_type_value,report_id,expected_status,new_status,note);
end $$;
revoke all on function public.update_admin_report(text,uuid,text,text,text) from public,anon;
grant execute on function public.update_admin_report(text,uuid,text,text,text) to authenticated;

create function public.list_admin_equipment_candidates(page_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rows_value jsonb;
begin
 if not public.is_report_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 select coalesce(jsonb_agg(x.data order by x.last_seen_at desc,x.id),'[]') into rows_value from (
 select c.id,c.last_seen_at,public.get_admin_equipment_candidate(c.id)||jsonb_build_object(
 'store_name',concat_ws(' ',ch.name,s.name),'equipment_name',coalesce(e.display_name,e.name,c.proposed_value->>'equipment_name'),
 'report_count',(select count(*) from public.gym_change_evidence ev where ev.candidate_id=c.id and ev.source_type='user_report'),
 'application_id',a.id,'applied_at',a.applied_at,'application_type',a.application_type,'rolled_back_at',a.rolled_back_at) data
 from public.gym_change_candidates c join public.gym_stores s on s.id=c.store_id join public.gym_chains ch on ch.id=s.chain_id
 left join public.equipment e on e.id=c.equipment_id left join public.gym_auto_applications a on a.candidate_id=c.id
 where c.entity_type='store_equipment' order by c.last_seen_at desc,c.id limit 50 offset greatest(page_offset,0))x;
 return jsonb_build_object('rows',rows_value);
end $$;
revoke all on function public.list_admin_equipment_candidates(integer) from public,anon,service_role;
grant execute on function public.list_admin_equipment_candidates(integer) to authenticated;

create or replace function public.capture_official_observation_before_admin_review(source_id uuid,snapshot_id uuid,change text,subject text,equipment_id text,proposal jsonb,review_required boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare s public.gym_official_sources%rowtype;target uuid;weight numeric;identity text;begin
 select * into strict s from public.gym_official_sources where id=source_id;
 if s.store_id is null then raise exception 'Pilot requires registered store';end if;
 if change like 'store_%' then perform pg_advisory_xact_lock(hashtextextended(s.store_id,429));
 else perform pg_advisory_xact_lock(hashtextextended(s.store_id||':'||change||':'||subject,421));end if;
 select c.id into target from public.gym_change_candidates c where c.store_id=s.store_id and c.change_type=change and c.candidate_key=subject
 and c.status in ('collecting','needs_review','auto_ready') for update;
 if target is null then insert into public.gym_change_candidates(entity_type,store_id,equipment_id,change_type,candidate_key,proposed_value)
 values(case when change like 'store_%' then 'store' else 'store_equipment' end,s.store_id,equipment_id,change,subject,proposal) returning id into target;end if;
 identity:='official:'||source_id||':'||target;
 select official_weight into strict weight from public.gym_auto_rule_config where change_type=change;
 insert into public.gym_change_evidence(candidate_id,source_type,source_ref,direction,weight,observed_at,source_url,data)
 values(target,'official',identity,'support',weight,(select fetched_at from public.gym_official_source_snapshots where id=snapshot_id),s.url,jsonb_build_object('source_id',source_id,'snapshot_id',snapshot_id,'requires_review',review_required,'parser_version',s.current_parser_version)||proposal)
 on conflict(source_type,source_ref) where source_ref is not null do update set observed_at=excluded.observed_at,weight=excluded.weight,data=excluded.data;
 insert into public.gym_official_snapshot_candidates values(snapshot_id,target) on conflict do nothing;
 update public.gym_change_candidates set last_seen_at=now() where id=target;
 perform public.reevaluate_gym_change_candidate(target);
 -- Reevaluate opposite open candidates as protection, never only the new side.
 perform public.reevaluate_gym_change_candidate(c.id) from public.gym_change_candidates c where c.store_id=s.store_id and c.id<>target
 and c.status in ('collecting','needs_review','auto_ready') and ((change like 'store_%' and c.entity_type='store') or c.equipment_id=capture_official_observation_before_admin_review.equipment_id);
 return target;
end $$;


notify pgrst,'reload schema';
commit;
