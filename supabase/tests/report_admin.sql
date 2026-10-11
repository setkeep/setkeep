begin;
insert into auth.users(id) values ('00000000-0000-4000-9000-000000000001'),('00000000-0000-4000-9000-000000000002'),('00000000-0000-4000-9000-000000000003');
insert into public.app_admins(user_id) values ('00000000-0000-4000-9000-000000000003');
insert into public.gym_chains(id,name) values ('qa-admin','QA管理');
insert into public.gym_stores(id,chain_id,source_id,name) values ('qa-admin-store','qa-admin','one','店舗');
set local request.jwt.claim.sub='00000000-0000-4000-9000-000000000001';
set local role authenticated;
insert into public.gym_exercise_reports(store_id,exercise_id,report_kind) values ('qa-admin-store','bench_press','missing_exercise'),('qa-admin-store','barbell_squat','incorrect_exercise');
insert into public.gym_equipment_reports(store_id,kind,equipment_name) values ('qa-admin-store','added','QAベンチ');
do $$ begin
 if public.is_report_admin() then raise exception 'User is admin';end if;
 begin insert into public.app_admins(user_id) values(auth.uid());raise exception 'Self promotion succeeded';exception when insufficient_privilege then null;end;
 begin perform public.list_admin_reports('exercise');raise exception 'User used admin API';exception when insufficient_privilege then null;end;
 update public.gym_exercise_reports set status='reviewing' where store_id='qa-admin-store';
 if found then raise exception 'User updated exercise report';end if;
 begin update public.gym_equipment_reports set status='reviewing' where store_id='qa-admin-store';
 raise exception 'Direct equipment review allowed';exception when insufficient_privilege then null;end;
end $$;
set local request.jwt.claim.sub='00000000-0000-4000-9000-000000000002';
do $$ begin
 if exists(select 1 from public.admin_reports where store_id='qa-admin-store') then raise exception 'Foreign reports exposed';end if;
end $$;
set local request.jwt.claim.sub='00000000-0000-4000-9000-000000000003';
do $$ declare r record; payload jsonb; begin
 if not public.is_report_admin() then raise exception 'Admin denied';end if;
 if (select count(*) from public.admin_reports where store_id='qa-admin-store')<>3 then raise exception 'Admin cannot read all';end if;
 payload=public.list_admin_reports('equipment','pending','QA管理');
 if not exists(select 1 from jsonb_array_elements(payload->'rows') e where e->>'entered_name'='QAベンチ') then raise exception 'Search/name missing';end if;
 for r in select * from public.admin_reports where store_id='qa-admin-store' loop
 perform public.update_admin_report(r.report_type,r.id,'pending','reviewing','確認開始');
 perform public.update_admin_report(r.report_type,r.id,'reviewing',case when r.target_id='barbell_squat' then 'rejected' else 'applied' end,'確認済み');
 end loop;
 if exists(select 1 from public.admin_reports where store_id='qa-admin-store' and (status not in ('applied','rejected') or admin_note<>'確認済み' or reviewed_by<>auth.uid() or reviewed_at is null)) then raise exception 'Review fields failed';end if;
 if exists(select 1 from public.gym_store_equipment where store_id='qa-admin-store') then raise exception 'Master modified';end if;
 begin update public.gym_exercise_reports set comment='改変' where store_id='qa-admin-store';raise exception 'Immutable content changed';exception when insufficient_privilege then null;end;
 select * into r from public.admin_reports where store_id='qa-admin-store' limit 1;
 begin perform public.update_admin_report(r.report_type,r.id,'pending','reviewing','stale');raise exception 'Stale update allowed';exception when raise_exception then if sqlerrm='Stale update allowed' then raise;end if;end;
end $$;
rollback;
select 'admin/owner/other-user RLS, review transitions, audit, search and immutable master passed' result;
