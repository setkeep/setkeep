begin;
-- Local implementation only. New ACL/RLS requires approval before production.
select public.lock_gym_equipment_review();
select set_config('setkeep.gym_candidate_id','',true);
select set_config('setkeep.gym_application_id','',true);
lock table public.gym_store_equipment in share row exclusive mode;
lock table public.equipment in share row exclusive mode;
create schema if not exists equipment_quarantine;
revoke all on schema equipment_quarantine from public,anon,authenticated,service_role;
create table equipment_quarantine.scope (
 store_id text primary key, started_at timestamptz not null default clock_timestamp(),
 whole_chain boolean not null
);
insert into equipment_quarantine.scope(store_id,whole_chain)
select id,chain_id in ('anytime-fitness','fastgym24','golds-gym') from public.gym_stores
where chain_id in ('anytime-fitness','fastgym24','golds-gym')
 or id='auns-gym:aunsgym_jp_d4f6b4929a2a';
create table equipment_quarantine.inventory (
 store_id text not null,equipment_id text not null,original jsonb not null,
 quarantined_at timestamptz not null default clock_timestamp(),primary key(store_id,equipment_id)
);
insert into equipment_quarantine.inventory(store_id,equipment_id,original)
select g.store_id,g.equipment_id,to_jsonb(g) from public.gym_store_equipment g
join equipment_quarantine.scope s on s.store_id=g.store_id
where g.source_kind='official' and (s.whole_chain or g.source_url like 'https://beauty.hotpepper.jp/%');
-- Production stops on count drift; only the disposable synthetic runner opts out.
do $$ declare expected record; actual integer; begin
 if current_setting('setkeep.withdrawal_qa',true)='on' then return; end if;
 for expected in select * from (values ('anytime-fitness',2389),('fastgym24',1954),('golds-gym',250),('auns-gym',7)) v(chain_id,n) loop
  select count(*) into actual from equipment_quarantine.inventory q join public.gym_stores s on s.id=q.store_id where s.chain_id=expected.chain_id;
  if actual<>expected.n then raise exception 'Withdrawal count drift for %, expected %, actual %',expected.chain_id,expected.n,actual; end if;
 end loop;
end $$;
create table equipment_quarantine.hidden_equipment (
 equipment_id text primary key,original jsonb not null
);
insert into equipment_quarantine.hidden_equipment
select e.id,to_jsonb(e) from public.equipment e
where exists(select 1 from equipment_quarantine.inventory q where q.equipment_id=e.id)
and not exists(select 1 from public.gym_store_equipment g where g.equipment_id=e.id
 and not exists(select 1 from equipment_quarantine.inventory q where q.store_id=g.store_id and q.equipment_id=g.equipment_id));
-- FK identities and histories remain intact. Original relationships are recoverable.
delete from public.gym_store_equipment g using equipment_quarantine.inventory q
where g.store_id=q.store_id and g.equipment_id=q.equipment_id;
revoke all on all tables in schema equipment_quarantine from public,anon,authenticated,service_role;
create function public.community_equipment_only(target_store text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from equipment_quarantine.scope where store_id=target_store)
 or exists(select 1 from public.gym_stores where id=target_store and chain_id in ('anytime-fitness','fastgym24','golds-gym'));
$$;
create function public.equipment_publication_allowed(target_equipment text) returns boolean
language sql stable security definer set search_path='' as $$
 select not exists(select 1 from equipment_quarantine.hidden_equipment where equipment_id=target_equipment);
$$;
revoke all on function public.community_equipment_only(text),public.equipment_publication_allowed(text) from public,anon,authenticated,service_role;
grant execute on function public.community_equipment_only(text),public.equipment_publication_allowed(text) to anon,authenticated;
create policy equipment_withdrawn_source on public.equipment as restrictive for select to anon,authenticated
 using(public.equipment_publication_allowed(id));
-- Own generic registration choices, no imported rows repurposed or relabelled.
insert into public.equipment(id,name,normalized_name,category,load_type,source) values
 ('community:chest-press','チェストプレス','チェストプレス','筋トレ','not_specified','{"origin":"setkeep_generic_registration"}'),
 ('community:lat-pulldown','ラットプルダウン','ラットプルダウン','筋トレ','not_specified','{"origin":"setkeep_generic_registration"}'),
 ('community:leg-press','レッグプレス','レッグプレス','筋トレ','not_specified','{"origin":"setkeep_generic_registration"}'),
 ('community:leg-curl','レッグカール','レッグカール','筋トレ','not_specified','{"origin":"setkeep_generic_registration"}'),
 ('community:leg-extension','レッグエクステンション','レッグエクステンション','筋トレ','not_specified','{"origin":"setkeep_generic_registration"}'),
 ('community:smith','スミスマシン','スミスマシン','筋トレ','not_specified','{"origin":"setkeep_generic_registration"}'),
 ('community:rack','パワーラック','パワーラック','フリーウェイト','free_weight','{"origin":"setkeep_generic_registration"}'),
 ('community:dumbbell','ダンベル','ダンベル','フリーウェイト','free_weight','{"origin":"setkeep_generic_registration"}'),
 ('community:bench','ベンチ','ベンチ','フリーウェイト','free_weight','{"origin":"setkeep_generic_registration"}'),
 ('community:treadmill','トレッドミル','トレッドミル','有酸素','cardio','{"origin":"setkeep_generic_registration"}');
-- Existing report INSERT permission is unchanged; the explicit UI declaration is
-- consumed by a BEFORE trigger. Clients cannot set the trusted derived flag.
alter table public.gym_equipment_reports add column on_site_confirmed boolean not null default false;
create function public.check_community_equipment_report() returns trigger
language plpgsql security definer set search_path='' as $$ begin
 if public.community_equipment_only(new.store_id) and new.kind='added' then
  if new.comment not like '[現地確認]%' then raise exception 'On-site confirmation required' using errcode='22023'; end if;
  new.on_site_confirmed:=true;
  new.comment:=substring(new.comment from length('[現地確認]')+1);
 end if;
 return new;
end $$;
revoke all on function public.check_community_equipment_report() from public,anon,authenticated,service_role;
create trigger a_community_equipment_report before insert on public.gym_equipment_reports
 for each row execute function public.check_community_equipment_report();
create function public.guard_equipment_publication() returns trigger
language plpgsql security definer set search_path='' as $$
declare boundary timestamptz; cid uuid:=nullif(current_setting('setkeep.gym_candidate_id',true),'')::uuid;
begin
 if not public.community_equipment_only(new.store_id) then return new; end if;
 if new.source_kind='official' then
  -- Existing non-Hot-Pepper rows at the one AUN'S store remain unchanged.
  if exists(select 1 from public.gym_stores s where s.id=new.store_id and s.chain_id='auns-gym')
   and coalesce(new.source_url,'') not like 'https://beauty.hotpepper.jp/%'
   and not exists(select 1 from equipment_quarantine.inventory q where q.store_id=new.store_id and q.equipment_id=new.equipment_id)
  then return new; end if;
  return null;
 end if;
 select started_at into boundary from equipment_quarantine.scope where store_id=new.store_id;
 boundary:=coalesce(boundary,(select min(started_at) from equipment_quarantine.scope));
 if tg_op='UPDATE' and not exists(select 1 from equipment_quarantine.inventory q where q.store_id=old.store_id and q.equipment_id=old.equipment_id)
  and old.source_kind<>'official' then return new; end if;
 if not public.equipment_publication_allowed(new.equipment_id)
 or new.equipment_id not like 'community:%' and new.equipment_id not like 'community-training:%'
 then raise exception 'Independent community equipment ID required'; end if;
 if cid is null or not exists(
  select 1 from public.gym_change_candidates c join public.gym_change_evidence ev on ev.candidate_id=c.id
  join public.gym_equipment_reports r on r.id::text=ev.source_ref
  where c.id=cid and c.store_id=new.store_id and c.created_at>=boundary and c.change_type='added'
   and ev.source_type='user_report' and r.on_site_confirmed and r.created_at>=boundary)
 and not exists(select 1 from public.gym_change_candidates c
 join public.gym_change_evidence ev on ev.candidate_id=c.id
 join public.gym_training_equipment_confirmations t on t.candidate_id=c.id and t.user_id=ev.user_id
 where c.id=cid and c.store_id=new.store_id and c.created_at>=boundary and c.change_type='added'
 and ev.source_type='training_confirmation' and ev.observed_at>=boundary
 and t.active and t.first_seen_at>=boundary and t.equipment_id=new.equipment_id)
 or exists(select 1 from public.gym_change_evidence ev where ev.candidate_id=cid
  and (ev.source_type='official' or ev.observed_at<boundary)) then
  raise exception 'New on-site report required; archived evidence cannot republish equipment';
 end if;
 return new;
end $$;
revoke all on function public.guard_equipment_publication() from public,anon,authenticated,service_role;
create trigger a_equipment_publication_guard before insert or update on public.gym_store_equipment
 for each row execute function public.guard_equipment_publication();
create function public.guard_withdrawn_equipment_master() returns trigger
language plpgsql security definer set search_path='' as $$ begin
 if not public.equipment_publication_allowed(new.id)
 or coalesce(new.source->>'master_file','') ~* '(エニタイム|ANYTIME|FASTGYM24|GOLDSGYM)'
 or new.id like any(array['anytime-fitness:%','fastgym24:%','golds-gym:%'])
 then return null; end if; return new;
end $$;
revoke all on function public.guard_withdrawn_equipment_master() from public,anon,authenticated,service_role;
create trigger a_withdrawn_equipment_master before insert or update on public.equipment
 for each row execute function public.guard_withdrawn_equipment_master();
create table equipment_quarantine.candidates(candidate_id uuid primary key,original jsonb not null);
insert into equipment_quarantine.candidates
select c.id,to_jsonb(c) from public.gym_change_candidates c
where c.entity_type='equipment' and public.community_equipment_only(c.store_id)
 and c.status in ('collecting','needs_review','auto_ready');
revoke all on equipment_quarantine.candidates from public,anon,authenticated,service_role;
-- Resolve pre-cutover open equipment candidates so a new report cannot join the
-- old grouping key. Preserve evidence and snapshots, never reinterpret them.
update public.gym_change_candidates c set status='rejected',resolved_at=clock_timestamp(),updated_at=clock_timestamp()
where c.entity_type='equipment' and public.community_equipment_only(c.store_id)
 and c.status in ('collecting','needs_review','auto_ready');

insert into public.equipment(id,name,normalized_name,category,load_type,source)
select 'community-training:'||r.canonical_id,min(r.label),min(r.label),'利用者確認','not_specified',
 jsonb_build_object('origin','setkeep_reviewed_training_concept','canonical_id',r.canonical_id)
from public.gym_training_equipment_rules r where r.canonical_id is not null group by r.canonical_id;
insert into public.equipment_exercise_mapping(equipment_id,exercise_id,rationale)
select distinct e.id,m.exercise_id,'SETKEEPの既存レビュー済み共通設備能力に対応。店舗での存在は新しい現地確認のみで判定。'
from public.equipment e join public.canonical_equipment_exercise_mapping m on m.canonical_id=e.source->>'canonical_id'
where e.id like 'community-training:%';
insert into public.canonical_equipment_matchers(canonical_id,name_key,category,load_type)
select e.source->>'canonical_id',public.canonical_equipment_key(e.name),e.category,e.load_type
from public.equipment e where e.id like 'community-training:%' on conflict do nothing;
insert into public.equipment_canonical_mapping(equipment_id,canonical_id,matcher_id,review_basis)
select e.id,m.canonical_id,m.id,'既存レビュー済みトレーニング確認ルールの一般設備概念。サイト由来の店舗在庫・機種情報は使用しない。'
from public.equipment e join public.canonical_equipment_matchers m on m.canonical_id=e.source->>'canonical_id'
and m.name_key=public.canonical_equipment_key(e.name) and m.category=e.category and m.load_type=e.load_type
where e.id like 'community-training:%';
insert into public.gym_training_equipment_rules(exercise_id,equipment_id,canonical_id,label,basis)
select r.exercise_id,'community-training:'||r.canonical_id,r.canonical_id,min(r.label),min(r.basis)
from public.gym_training_equipment_rules r where r.canonical_id is not null and r.equipment_id not like 'community-training:%'
group by r.exercise_id,r.canonical_id;

create or replace function public.training_equipment_options(target_store text,exercise_ids text[]) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501';end if;
 if cardinality(exercise_ids)>100 then raise exception 'Too many exercises';end if;
 if not exists(select 1 from public.gym_stores where id=target_store and active and operational_status='active') then return '[]';end if;
 return coalesce((select jsonb_agg(x) from(
 select r.exercise_id,jsonb_agg(jsonb_build_object('equipment_id',r.equipment_id,'label',r.label,
 'known',public.training_equipment_present(target_store,r.equipment_id) or exists(
 select 1 from public.gym_training_equipment_confirmations t where t.user_id=auth.uid() and t.store_id=target_store
 and t.equipment_id=r.equipment_id and t.active and t.last_seen_at>=now()-make_interval(days=>(select evidence_window_days from public.gym_auto_rule_config where change_type='added'))
 )) order by r.label) options
 from public.gym_training_equipment_rules r join public.equipment e on e.id=r.equipment_id and not e.needs_review
 where r.exercise_id=any(exercise_ids)
 and ((public.community_equipment_only(target_store) and r.equipment_id like 'community-training:%')
 or (not public.community_equipment_only(target_store) and (
 (r.equipment_id not like 'community-training:%' and public.equipment_publication_allowed(r.equipment_id))
 or (r.equipment_id like 'community-training:%' and not exists(
 select 1 from public.gym_training_equipment_rules original where original.exercise_id=r.exercise_id
 and original.canonical_id=r.canonical_id and original.equipment_id not like 'community-training:%'
 and public.equipment_publication_allowed(original.equipment_id)))))) group by r.exercise_id)x),'[]');
end$$;

commit;
