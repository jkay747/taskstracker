-- Kay2-Do update, November 2026: snooze tasks. Run once in Supabase → SQL Editor.
-- Safe to run again.

-- A snoozed task is greyed out until snoozed_until. When that time passes, the
-- person who snoozed it (snoozed_by) gets a reminder and the apps clear both fields.
alter table public.tasks add column if not exists snoozed_until timestamptz;
alter table public.tasks add column if not exists snoozed_by uuid references auth.users (id) on delete set null;
