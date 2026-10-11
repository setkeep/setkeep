#!/usr/bin/env python3
"""Run synthetic equipment admin QA in a new socket-only disposable PostgreSQL.
No Supabase CLI, connection strings, credentials or linked project access.
Requires PostgreSQL 17 tools on PATH. Never reuses an existing database/server.
"""
from pathlib import Path
import os,re,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
def main():
 with tempfile.TemporaryDirectory(prefix='setkeep-review-',dir='/tmp') as tmp:
  data=Path(tmp)/'data';sock=Path(tmp)/'socket';sock.mkdir()
  def command(args,**kwargs):
   p=subprocess.run(args,text=True,capture_output=True,**kwargs)
   if p.returncode:raise RuntimeError(p.stderr[-2000:])
   return p
  command(['initdb','-D',str(data),'-U','postgres','-A','trust'])
  command(['pg_ctl','-D',str(data),'-l',str(Path(tmp)/'postgres.log'),'-o',f'-k {sock} -p 55439 -h ""','start'])
  try:
   base=['psql','-h',str(sock),'-p','55439','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-q']
   def sql(text):return command(base,input=text)
   sql("create role anon; create role authenticated; create role service_role; create schema auth; create schema extensions; create table auth.users(id uuid primary key); create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$; grant usage on schema auth to authenticated,anon; alter default privileges for role postgres in schema public grant all on tables to anon,authenticated,service_role; alter default privileges for role postgres in schema public grant execute on functions to anon,authenticated,service_role;")
   files=[f for f in sorted((ROOT/'supabase/migrations').glob('*.sql')) if f.name[:8] in ('20260923','20260924','20260929') and not f.name.startswith('202609290031')]
   for f in files:
    sql(f.read_text())
    if f==files[0]:
     ids=set()
     for src in files:ids.update(re.findall(r"'([a-z0-9-]+:fp_eq_[a-z0-9_]+)'",src.read_text()))
     # Initial external imports are not part of migrations. Stub only FK seed
     # references, without connecting to production or copying user data.
     sql('insert into public.equipment(id,name,normalized_name,category) values '+','.join("('%s','Synthetic seed','synthetic','qa')"%i for i in sorted(ids))+' on conflict do nothing;')
   sql((ROOT/'supabase/migrations/20261010230000_equipment_candidate_admin_actions.sql').read_text())
   print('PASS fresh local migration')
   for name in ['gym_equipment_admin_review.sql','report_admin.sql','gym_places_details.sql','gym_change_candidates.sql','gym_auto_application.sql','gym_equipment_state_reports.sql','training_equipment_confirmation.sql','gym_official_sources.sql','gym_store_lifecycle.sql']:
    command(base+['-f',str(ROOT/'supabase/tests'/name)])
    print('PASS '+name)
   sql("""create table qa_store_snapshot as select count(*) n,md5(string_agg(to_jsonb(s)::text,'' order by id)) h from public.gym_stores s; create table qa_other_inventory as select store_id,equipment_id,to_jsonb(g) original from public.gym_store_equipment g where not exists(select 1 from public.gym_stores s where s.id=g.store_id and (s.chain_id in ('anytime-fitness','fastgym24','golds-gym') or s.id='auns-gym:aunsgym_jp_d4f6b4929a2a'));""")
   sql("create table qa_existing_routine_acl as select oid,proacl from pg_proc where pronamespace='public'::regnamespace; create table qa_existing_relation_acl as select oid,relacl from pg_class where relnamespace='public'::regnamespace;")
   sql("set setkeep.withdrawal_qa='on';\n"+(ROOT/'supabase/migrations/20261011000100_equipment_source_withdrawal.sql').read_text())
   command(base+['-f',str(ROOT/'supabase/tests/equipment_source_withdrawal.sql')])
   print('PASS equipment_source_withdrawal.sql')
   env=os.environ.copy();env.update(SETKEEP_REVIEW_PG_SOCKET=str(sock),SETKEEP_REVIEW_PG_PORT='55439',SETKEEP_REVIEW_PG_DB='postgres')
   p=command(['python3',str(ROOT/'tool/equipment_review/test_equipment_review_concurrency.py')],env=env)
   print(p.stdout.strip())
  finally:
   command(['pg_ctl','-D',str(data),'-m','fast','stop'])
if __name__=='__main__':main()
