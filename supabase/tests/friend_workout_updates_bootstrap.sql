-- Minimal auth stand-in. Only for a fresh local cluster, never production.
create role anon nologin;
create role authenticated nologin;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
grant usage on schema auth,public to anon,authenticated;
grant execute on function auth.uid() to anon,authenticated;
