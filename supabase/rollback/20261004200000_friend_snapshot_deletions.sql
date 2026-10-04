-- Restore the previous client first. Remove only this RPC/ordering metadata;
-- deleted snapshots are not restored and source workouts/visibility stay intact.
begin;
drop function public.sync_friend_workouts(uuid,jsonb,text[],uuid,bigint,boolean);
drop table public.friend_snapshot_versions;
commit;
