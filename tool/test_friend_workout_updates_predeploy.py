#!/usr/bin/env python3
"""Fresh Unix-socket-only synthetic PostgreSQL; cannot target a remote DB."""
import argparse
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scratch-parent', type=Path, required=True)
    parser.add_argument('--pg-bin', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    run = Path(tempfile.mkdtemp(prefix='predeploy-', dir=args.scratch_parent))
    socket = Path(tempfile.mkdtemp(prefix='fr-predeploy-', dir='/tmp'))
    data = run / 'postgres'
    pg = args.pg_bin
    env = {k: v for k, v in os.environ.items() if not k.startswith('PG')}
    env.pop('DATABASE_URL', None)
    port = '56433'
    results = []
    log = (run / 'tests.log').open('w')
    started = False

    def command(argv, expected=0):
        completed = subprocess.run([str(x) for x in argv], env=env, capture_output=True, text=True)
        log.write(completed.stdout + completed.stderr)
        log.flush()
        if expected == 0 and completed.returncode != 0:
            raise RuntimeError(f'Command failed ({completed.returncode}): {argv[0]}; see {run / "tests.log"}')
        if expected != 0 and completed.returncode == 0:
            raise RuntimeError('Expected guarded failure did not occur')
        return completed

    def psql(sql=None, files=(), expected=0, db='postgres'):
        argv = [pg / 'psql', '-X', '-h', socket, '-p', port, '-d', db, '-v', 'ON_ERROR_STOP=1']
        for file in files:
            argv += ['-f', file]
        if sql is not None:
            argv += ['-c', sql]
        return command(argv, expected)

    def passed(label):
        results.append(label)
        print('PASS:', label, flush=True)

    def intact():
        psql(sql="do $$ begin if public.fixture_state()<>(select payload from public.fixture_snapshot) then raise exception 'Baseline changed'; end if; end $$;")

    verification = root / 'supabase/verification'
    rollback = root / 'supabase/rollback/20261102090000_friend_workout_updates.sql'
    migration = root / 'supabase/migrations/20261102090000_friend_workout_updates.sql'
    prepared = run / 'apply-only-20261102090000.sql'
    prepared.write_text(runpy.run_path(str(root / 'tool/prepare_friend_workout_updates.py'))['prepare'](root))
    try:
        command([pg / 'initdb', '-D', data, '-A', 'trust', '--no-locale', '--encoding=UTF8'])
        command([pg / 'pg_ctl', '-D', data, '-l', run / 'postgres.log', '-o',
                 f'-k {socket} -p {port} -c listen_addresses=', 'start'])
        started = True
        psql(files=[root / 'supabase/tests/friend_workout_updates_bootstrap.sql',
                    root / 'supabase/migrations/20261004100000_friends_mvp.sql',
                    root / 'supabase/tests/friend_workout_updates_fixture.sql',
                    verification / 'friend_workout_updates_preflight.sql',
                    verification / 'friend_workout_updates_catalog.sql',
                    verification / 'friend_workout_updates_history.sql'])
        passed('fresh fixture and read-only preflight/catalog/history')
        psql(files=[prepared, verification / 'friend_workout_updates_postflight.sql',
                    root / 'supabase/tests/friend_workout_updates_security.sql'])
        intact()
        passed('apply transaction, exact history, ACL/RLS and positive/negative role tests')
        psql(files=[prepared], expected=1)
        intact()
        passed('duplicate apply refuses without changing existing data/schema')

        # Restore just this test-modified routine from the unchanged source.
        source = migration.read_text()
        routine = re.search(r'create function public.latest_updated_friend_workouts\(\).*?\$\$;', source, re.S).group(0)
        psql(sql="create or replace function public.latest_updated_friend_workouts() returns setof public.friend_workouts language sql stable security invoker as 'select * from public.friend_workouts where false';")
        failure = psql(files=[rollback], expected=1)
        if 'Candidate function drift' not in failure.stderr:
            raise RuntimeError('Unexpected drift rejection reason')
        psql(sql=routine.replace('create function', 'create or replace function', 1))
        psql(files=[verification / 'friend_workout_updates_postflight.sql'])
        intact()
        passed('rollback rejects function drift before dropping anything')

        psql(sql='create index fixture_other_update_index on public.friend_workouts(updated_at);')
        failure = psql(files=[rollback], expected=1)
        if 'Unrelated dependency' not in failure.stderr:
            raise RuntimeError('Unexpected dependency rejection reason')
        psql(sql='drop index public.fixture_other_update_index;')
        intact()
        passed('rollback refuses an unrelated auto-droppable column dependency')

        psql(sql="update supabase_migrations.schema_migrations set name='different-source' where version='20261102090000';")
        failure = psql(files=[rollback], expected=1)
        if 'Migration history differs' not in failure.stderr:
            raise RuntimeError('Unexpected history rejection reason')
        psql(sql="update supabase_migrations.schema_migrations set name='friend_workout_updates' where version='20261102090000';")
        intact()
        passed('rollback never deletes a mismatched migration-history row')

        lock_env = dict(env, PGAPPNAME='friend_roster_lock_fixture')
        holder = subprocess.Popen([str(pg / 'psql'), '-X', '-h', str(socket), '-p', port,
            '-d', 'postgres', '-c', 'begin; lock table public.friend_profiles in access share mode; select pg_sleep(20); rollback;'],
            env=lock_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(50):
                result = psql(sql="select count(*) from pg_locks l join pg_stat_activity a using(pid) where a.application_name='friend_roster_lock_fixture' and l.relation='public.friend_profiles'::regclass and l.granted;")
                if re.search(r'\n\s*1\s*\n', result.stdout):
                    break
                time.sleep(0.05)
            else:
                raise RuntimeError('Synthetic lock did not start')
            failure = psql(files=[rollback], expected=1)
            if 'lock timeout' not in failure.stderr:
                raise RuntimeError('Expected rollback lock timeout')
        finally:
            # This backend belongs to the fresh Unix-only fixture cluster.
            # Stopping only psql would leave pg_sleep holding the server lock.
            psql(sql="select pg_terminate_backend(pid) from pg_stat_activity where application_name='friend_roster_lock_fixture';")
            holder.wait(timeout=5)
        psql(files=[verification / 'friend_workout_updates_postflight.sql'])
        intact()
        passed('2s lock timeout rolls back every prior DDL step atomically')

        psql(files=[rollback, verification / 'friend_workout_updates_rolled_back.sql'])
        intact()
        psql(sql="do $$ begin if exists(select 1 from supabase_migrations.schema_migrations where version='20261102090000') then raise exception 'History remains'; end if; end $$;")
        passed('rollback removes only candidate schema/history, retaining all baseline content and authorization')
        psql(files=[rollback], expected=1)
        intact()
        passed('repeated rollback refuses; does not guess or cascade')
        psql(files=[verification / 'friend_workout_updates_preflight.sql', prepared,
                    verification / 'friend_workout_updates_postflight.sql',
                    root / 'supabase/tests/friend_workout_updates_security.sql', rollback])
        intact()
        passed('apply, rollback, reapply and rollback all preserve baseline')

        # Existing suites use a clean separate synthetic database.
        command([pg / 'createdb', '-h', socket, '-p', port, 'regression'])
        bootstrap = run / 'bootstrap-existing-roles.sql'
        bootstrap.write_text('\n'.join(line for line in (root / 'supabase/tests/friend_workout_updates_bootstrap.sql').read_text().splitlines() if not line.startswith('create role ')))
        history = run / 'history.sql'
        history.write_text('create schema supabase_migrations; create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[]);')
        psql(db='regression', files=[bootstrap, root / 'supabase/migrations/20261004100000_friends_mvp.sql', history,
                    prepared, root / 'supabase/tests/friend_workout_updates.sql', root / 'supabase/tests/friends_mvp.sql', rollback])
        passed('existing timestamp and friends MVP SQL regressions pass with the prepared transaction')
        (run / 'result.json').write_text(json.dumps({'passed_stages':results,'production_connected':False,'server_stopped':False},indent=2))
    finally:
        if started:
            command([pg / 'pg_ctl', '-D', data, '-m', 'fast', 'stop'])
        shutil.rmtree(socket)
        log.close()
    result_path = run / 'result.json'
    result = json.loads(result_path.read_text())
    result['server_stopped'] = True
    result_path.write_text(json.dumps(result,indent=2))
    print(json.dumps({'result':str(result_path),'passed_stages':len(results),'server_stopped':True}),flush=True)


if __name__ == '__main__':
    main()
