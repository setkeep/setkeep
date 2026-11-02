#!/usr/bin/env python3
"""Prepare one reviewable SQL transaction. Never connects to any database."""
from pathlib import Path
import argparse
import hashlib
import re


def prepare(root: Path) -> str:
    source_path = root / 'supabase/migrations/20261102090000_friend_workout_updates.sql'
    source = source_path.read_text()
    start = re.search(r'^begin;\n', source, re.M)
    end = re.search(r'^commit;\s*$', source, re.M)
    if not start or not end or source.count('$friend_roster_source$'):
        raise ValueError('Unexpected migration framing')
    digest = hashlib.md5(source.encode()).hexdigest()
    body = source[start.end():end.start()]
    return f"""-- PREPARED ONLY. Production execution requires exact separate approval.
-- Source MD5: {digest}; target only 20261102090000.
begin;
set local lock_timeout='2s';
set local statement_timeout='60s';
do $$ begin
 if to_regclass('supabase_migrations.schema_migrations') is null then
  raise exception 'Migration history unavailable; stop'; end if;
 if exists(select 1 from supabase_migrations.schema_migrations where version='20261102090000') then
  raise exception 'Target history already exists; inspect instead of rerunning'; end if;
end $$;
{body}
insert into supabase_migrations.schema_migrations(version,name,statements)
values('20261102090000','friend_workout_updates',array[$friend_roster_source${source}$friend_roster_source$]);
notify pgrst,'reload schema';
commit;
"""


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    # Refuse to silently replace a reviewed batch.
    with args.output.open('x') as output:
        output.write(prepare(root))
    print(f'Prepared only: {args.output}')
