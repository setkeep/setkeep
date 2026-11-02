-- Run only after confirming these history columns/types from catalog.sql.
-- No statements/body content is returned, only version/name/source hash.
begin read only;
set local statement_timeout='15s';
select version,name,md5(coalesce(array_to_string(statements,E'\n'),'')) as source_md5
from supabase_migrations.schema_migrations where version in(
 '20261004100000','20261004140000','20261004200000','20261004220000',
 '20261005100000','20261005110000','20261006140000','20261006170000','20261102090000')
order by version;
rollback;
