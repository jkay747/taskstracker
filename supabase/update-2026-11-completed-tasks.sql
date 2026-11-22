-- Kay2-Do update, November 2026: keep completed tasks, crossed out, and remove them
-- by hand or automatically. Run once in Supabase → SQL Editor. Safe to run again.

-- Completed tasks stay on the list, crossed out, until they're removed: by hand
-- ('manual'), or automatically completed_days after they were checked off ('auto').
-- The hourly job at the end of this file does the automatic removal.
alter table public.lists add column if not exists completed_mode text not null default 'manual'
  check (completed_mode in ('manual', 'auto'));
alter table public.lists add column if not exists completed_days integer not null default 7
  check (completed_days between 1 and 365);
-- ---------------------------------------------------------------- removing completed tasks

-- Deletes checked-off tasks on lists set to remove them automatically, once they've
-- been done for the list's number of days. Run hourly by pg_cron (below).
create or replace function public.remove_expired_completed()
returns integer language sql security definer set search_path = public as $$
  with gone as (
    delete from public.tasks t
    using public.lists l
    where t.list_id = l.id
      and l.completed_mode = 'auto'
      and t.done
      and coalesce(t.done_at, t.updated_at) < now() - make_interval(days => l.completed_days)
    returning 1
  )
  select count(*)::integer from gone;
$$;
revoke all on function public.remove_expired_completed() from public, anon, authenticated;

do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('kay2do-remove-completed', '7 * * * *', 'select public.remove_expired_completed()');
exception when others then
  raise notice 'Completed tasks will not be removed on a schedule (%). Turn on pg_cron under Database > Extensions, then run this again. The apps still hide them when they are due.', sqlerrm;
end $$;
