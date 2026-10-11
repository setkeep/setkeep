"""Synthetic local PostgreSQL concurrency QA. No linked Supabase connection.
Requires the equipment migrations + admin review migration in an isolated DB.
All fixtures live under qa-concurrent-*; use a disposable database.
"""
import subprocess, json, os
SOCKET=os.environ['SETKEEP_REVIEW_PG_SOCKET']
assert SOCKET.startswith('/tmp/') or SOCKET.startswith('/var/folders/'), 'Disposable local socket required'
BASE=['psql','-h',SOCKET,'-p',os.environ['SETKEEP_REVIEW_PG_PORT'],'-U','postgres','-d',os.environ['SETKEEP_REVIEW_PG_DB'],'-v','ON_ERROR_STOP=1','-Atq']
ADMIN="set local role authenticated; set local request.jwt.claim.sub='00000000-0000-4000-9011-000000000009';"
def run(sql,ok=True):
 p=subprocess.run(BASE,input=sql,text=True,capture_output=True)
 if ok and p.returncode:raise AssertionError(p.stderr)
 return p

def claim(i):return f"set local role authenticated; set local request.jwt.claim.sub='00000000-0000-4000-9011-{i:012d}';"

def snap(store):
 return json.loads(run(f"begin;{ADMIN}select public.get_admin_equipment_candidate(id) from public.gym_change_candidates where store_id='{store}' order by created_at desc limit 1;commit;").stdout.strip())
def action(s,act,op,selected=None):
 def lit(v):return 'null' if v is None else "'"+str(v).replace("'","''")+"'"
 return 'select public.review_gym_equipment_candidate('+','.join([
 lit(s['candidate_id']),lit(act),lit(s['status']),str(s['review_version']),lit(op),"'Synthetic concurrency'",
 str(s['master_present']).lower(),lit(s['master_updated_at']),lit(selected),'true' if selected else 'false'])+');'
def race(first,second,second_code=None):
 # READY is emitted only after the first mutation holds its transaction locks.
 p=subprocess.Popen(BASE,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 p.stdin.write("begin;set local statement_timeout='4s';"+first+"\n\\echo READY\nselect pg_sleep(0.4);commit;\n");p.stdin.close();p.stdin=None
 lines=[]
 for line in p.stdout:
  lines.append(line)
  if line.strip()=='READY':break
 q=run("\\set VERBOSITY verbose\nbegin;set local statement_timeout='4s';"+second+"commit;",ok=second_code is None)
 out,err=p.communicate(timeout=6)
 assert p.returncode==0,err
 if second_code:assert q.returncode and second_code in q.stderr,q.stderr
 assert 'deadlock' not in err.lower()+q.stderr.lower(),err+q.stderr

run("""
insert into auth.users(id) select ('00000000-0000-4000-9011-'||lpad(i::text,12,'0'))::uuid from generate_series(1,9)i;
insert into public.app_admins(user_id) values('00000000-0000-4000-9011-000000000009');
insert into public.gym_chains(id,name) values('qa-concurrent-chain','Synthetic concurrency');
insert into public.gym_stores(id,chain_id,source_id,name) select 'qa-concurrent-'||i,'qa-concurrent-chain',i::text,'Synthetic' from generate_series(1,5)i;
insert into public.equipment(id,name,normalized_name,category) values('qa-concurrent-machine','Synthetic concurrent machine','syntheticconcurrentmachine','qa');
insert into public.gym_store_equipment(store_id,equipment_id,quantity,raw_name,source_kind) values('qa-concurrent-1','qa-concurrent-machine',4,'Synthetic','official'),('qa-concurrent-2','qa-concurrent-machine',4,'Synthetic','official');
insert into public.gym_change_candidates(store_id,equipment_id,change_type,candidate_key,proposed_value,status)
select 'qa-concurrent-'||i,'qa-concurrent-machine','quantity_changed','qa-concurrent-machine:quantity:5','{"reported_quantity":5}','needs_review' from generate_series(1,2)i;
""")
s=snap('qa-concurrent-1');op='00000000-0000-4000-9011-000000000101'
race(ADMIN+action(s,'hold',op),ADMIN+action(s,'apply','00000000-0000-4000-9011-000000000102'), '40001')
print('PASS concurrent hold wins / stale manual apply rejected')
s=snap('qa-concurrent-2');op='00000000-0000-4000-9011-000000000103'
race(ADMIN+action(s,'apply',op),ADMIN+action(s,'apply',op))
assert run("select count(*) from public.gym_auto_applications where store_id='qa-concurrent-2';").stdout.strip()=='1'
assert run(f"select count(*) from public.gym_equipment_review_operations where operation_id='{op}';").stdout.strip()=='1'
print('PASS concurrent identical operation / one application and audit row')

def report(store,i):return claim(i)+f"insert into public.gym_equipment_reports(store_id,kind,equipment_name) values('{store}','added','Synthetic concurrent machine');"
run('begin;'+report('qa-concurrent-3',1)+'commit;')
s=snap('qa-concurrent-3')
race(ADMIN+action(s,'hold','00000000-0000-4000-9011-000000000104'),report('qa-concurrent-3',2)+report('qa-concurrent-3',3))
assert run("select count(*) from public.gym_store_equipment where store_id='qa-concurrent-3';").stdout.strip()=='0'
assert run("select count(*) from public.gym_change_candidates where store_id='qa-concurrent-3' and admin_held;").stdout.strip()=='1'
s=snap('qa-concurrent-3');run('begin;'+ADMIN+action(s,'release','00000000-0000-4000-9011-000000000105')+'commit;')
assert snap('qa-concurrent-3')['status']=='auto_applied'
print('PASS held ingestion blocks auto / explicit release resumes auto')
run('begin;'+report('qa-concurrent-4',1)+'commit;');s=snap('qa-concurrent-4')
race(ADMIN+action(s,'apply','00000000-0000-4000-9011-000000000106','qa-concurrent-machine'),report('qa-concurrent-4',2)+report('qa-concurrent-4',3))
assert run("select count(*) from public.gym_auto_applications where store_id='qa-concurrent-4';").stdout.strip()=='1'
print('PASS manual apply wins before threshold reports / no duplicate application')
run('begin;'+report('qa-concurrent-5',1)+report('qa-concurrent-5',2)+'commit;');s=snap('qa-concurrent-5')
race(report('qa-concurrent-5',3),ADMIN+action(s,'apply','00000000-0000-4000-9011-000000000107','qa-concurrent-machine'),'40001')
assert run("select count(*) from public.gym_auto_applications where store_id='qa-concurrent-5';").stdout.strip()=='1'
print('PASS automatic apply wins / stale manual request rejected')
