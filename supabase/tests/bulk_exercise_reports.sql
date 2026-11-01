-- Synthetic local-only data, rolled back at the end. No migration required.
begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000071');
insert into public.gym_chains(id,name) values ('qa-bulk','QA bulk');
insert into public.gym_stores(id,chain_id,source_id,name)
values ('qa-bulk-store','qa-bulk','one','QA bulk');
set local request.jwt.claim.sub='00000000-0000-4000-8000-000000000071';
set local role authenticated;
insert into public.gym_exercise_reports(store_id,exercise_id,report_kind,comment)
values ('qa-bulk-store','bench_press','missing_exercise','共通コメント'),
       ('qa-bulk-store','barbell_squat','missing_exercise','共通コメント');
-- Simulate retry after a committed response was lost; pending rows are reused.
insert into public.gym_exercise_reports(store_id,exercise_id,report_kind,comment)
values ('qa-bulk-store','bench_press','missing_exercise','再試行'),
       ('qa-bulk-store','barbell_squat','missing_exercise','再試行');
do $$ begin
 if (select count(*) from public.gym_exercise_reports where store_id='qa-bulk-store')<>2
 then raise exception 'Retry duplicated existing reports';end if;
 if exists(select 1 from public.gym_exercise_reports where store_id='qa-bulk-store' and (status<>'pending' or comment<>'共通コメント'))
 then raise exception 'Retry changed original report contents';end if;
 -- A failure on the second row must roll back the first row too.
 begin
  insert into public.gym_exercise_reports(store_id,exercise_id,report_kind)
  values ('qa-bulk-store','dumbbell_curl','missing_exercise'),
         ('qa-bulk-store','leg_press','invalid_kind');
  raise exception 'Invalid row accepted';
 exception when check_violation then null;end;
 if exists(select 1 from public.gym_exercise_reports where exercise_id='dumbbell_curl')
 then raise exception 'Failed batch partially committed';end if;
end $$;
-- Bring the user to 19 reports, then test a two-row batch at the existing cap.
insert into public.gym_exercise_reports(store_id,exercise_id,report_kind)
select 'qa-bulk-store','qa-bulk-'||n,'missing_exercise' from generate_series(1,17) n;
do $$ begin
 begin
  insert into public.gym_exercise_reports(store_id,exercise_id,report_kind)
  values ('qa-bulk-store','dumbbell_curl','missing_exercise'),
         ('qa-bulk-store','leg_press','missing_exercise');
  raise exception 'Rate limit not enforced';
 exception when raise_exception then
  if sqlerrm<>'Please wait before reporting again' then raise;end if;
 end;
 if (select count(*) from public.gym_exercise_reports where store_id='qa-bulk-store')<>19
 then raise exception 'Rate-limited batch partially committed';end if;
end $$;
-- Age synthetic reports, then retry the same complete batch successfully.
reset role;
insert into public.app_admins(user_id) values ('00000000-0000-4000-8000-000000000071');
update public.gym_exercise_reports set created_at=now()-interval '11 minutes' where store_id='qa-bulk-store';
delete from public.app_admins where user_id='00000000-0000-4000-8000-000000000071';
set local role authenticated;
insert into public.gym_exercise_reports(store_id,exercise_id,report_kind)
values ('qa-bulk-store','dumbbell_curl','missing_exercise'),
       ('qa-bulk-store','leg_press','missing_exercise');
-- Old single-target and free-form report contracts remain unchanged.
insert into public.gym_exercise_reports(store_id,exercise_id,report_kind)
values ('qa-bulk-store','bench_press','incorrect_exercise');
insert into public.gym_exercise_reports(store_id,report_kind,comment)
values ('qa-bulk-store','other','確認してください');
do $$ begin
 if (select count(*) from public.gym_exercise_reports where store_id='qa-bulk-store')<>23
 then raise exception 'Retry or legacy report failed';end if;
 if exists(select 1 from public.gym_store_equipment where store_id='qa-bulk-store')
 then raise exception 'Report modified shared equipment';end if;
end $$;
rollback;
select 'bulk reports: atomicity, rate limit, retry, deduplication, legacy compatibility passed' result;
