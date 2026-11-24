-- Kay2-Do shared database (Supabase / Postgres).
-- Run this once in your Supabase project: Dashboard → SQL Editor → New query →
-- paste this whole file → Run. Running it again is safe.
--
-- Both apps (web/ and apple/) use these tables. Everything is protected by
-- row-level security: you only ever see lists you are a member of.
--
-- Roles on a list:
--   owner        everything, including inviting people and deleting the list
--   editor       change any task, the categories, the list name and weekly theme
--   contributor  add tasks; change or check off tasks they own, are on, or created

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- tables

create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  email        text,
  display_name text not null default '' check (char_length(display_name) <= 80),
  created_at   timestamptz not null default now()
);

create table if not exists public.lists (
  id         uuid primary key default gen_random_uuid(),
  name       text not null default 'Kay2-Do' check (char_length(name) between 1 and 60),
  week_of    date,
  theme      text not null default '' check (char_length(theme) <= 140),
  because    text not null default '' check (char_length(because) <= 140),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- The weekly quote. Blank quote = the built-in pick for the week
-- (web/quotes.js, apple/Kay2Do/Quotes.swift); show_quote hides it.
alter table public.lists add column if not exists quote text not null default ''
  check (char_length(quote) <= 400);
alter table public.lists add column if not exists quote_by text not null default ''
  check (char_length(quote_by) <= 120);
alter table public.lists add column if not exists show_quote boolean not null default true;

-- Background picture (web and Mac only): '' none, 'library:<id>' for a built-in
-- picture (web/backgrounds.js), or 'upload:<list id>/<file>' for a photo in the
-- private "backgrounds" storage bucket below.
alter table public.lists add column if not exists background text not null default ''
  check (background = '' or background ~ '^(library|upload):[A-Za-z0-9._/-]{1,200}$');
alter table public.lists add column if not exists background_style text not null default 'balanced'
  check (background_style in ('subtle', 'balanced', 'vivid'));
-- Completed tasks stay on the list, crossed out, until they're removed: by hand
-- ('manual'), or automatically completed_days after they were checked off ('auto').
-- The hourly job at the end of this file does the automatic removal.
alter table public.lists add column if not exists completed_mode text not null default 'manual'
  check (completed_mode in ('manual', 'auto'));
alter table public.lists add column if not exists completed_days integer not null default 7
  check (completed_days between 1 and 365);

create table if not exists public.list_members (
  list_id   uuid not null references public.lists (id) on delete cascade,
  user_id   uuid not null references auth.users (id) on delete cascade,
  role      text not null check (role in ('owner', 'editor', 'contributor')),
  joined_at timestamptz not null default now(),
  primary key (list_id, user_id)
);

-- People invited by email who haven't signed in yet.
create table if not exists public.invites (
  id         uuid primary key default gen_random_uuid(),
  list_id    uuid not null references public.lists (id) on delete cascade,
  email      text not null check (email = lower(email) and position('@' in email) > 1),
  role       text not null check (role in ('editor', 'contributor')),
  invited_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (list_id, email)
);

create table if not exists public.categories (
  id         uuid primary key default gen_random_uuid(),
  list_id    uuid not null references public.lists (id) on delete cascade,
  key        text not null check (key ~ '^[a-z0-9-]{1,40}$'),
  label      text not null check (char_length(label) between 1 and 40),
  color      int  not null default 0 check (color between 0 and 7),
  sort_order int  not null default 0,
  created_at timestamptz not null default now(),
  unique (list_id, key)
);

-- owner:  null, {"id": "<user uuid>"} or {"name": "<name or email>"}
-- shared: a JSON array of the same shapes (other people on the task)
create table if not exists public.tasks (
  id           uuid primary key default gen_random_uuid(),
  list_id      uuid not null references public.lists (id) on delete cascade,
  category_key text,
  title        text not null check (char_length(title) between 1 and 300),
  notes        text not null default '' check (char_length(notes) <= 4000),
  done         boolean not null default false,
  priority     boolean not null default false,
  due          date,
  owner        jsonb check (owner is null or jsonb_typeof(owner) = 'object'),
  shared       jsonb not null default '[]'::jsonb check (jsonb_typeof(shared) = 'array'),
  created_by   uuid default auth.uid() references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  done_at      timestamptz,
  done_by      uuid references auth.users (id) on delete set null,
  updated_at   timestamptz not null default now()
);

-- Snoozed tasks are greyed out until snoozed_until. When that passes, the person
-- who snoozed it (snoozed_by) gets a reminder and the apps clear both fields.
alter table public.tasks add column if not exists snoozed_until timestamptz;
alter table public.tasks add column if not exists snoozed_by uuid references auth.users (id) on delete set null;

create index if not exists tasks_list_idx on public.tasks (list_id);
create index if not exists categories_list_idx on public.categories (list_id);
create index if not exists members_user_idx on public.list_members (user_id);

-- ---------------------------------------------------------------- helpers

-- Your role on a list, or null. SECURITY DEFINER so policies can call it
-- without recursing through list_members' own policy.
create or replace function public.list_role(p_list uuid)
returns text language sql stable security definer set search_path = public as $$
  select role from public.list_members where list_id = p_list and user_id = auth.uid()
$$;

create or replace function public.task_involves_me(p_owner jsonb, p_shared jsonb)
returns boolean language sql stable as $$
  select auth.uid() is not null and (
    coalesce(p_owner ->> 'id', '') = auth.uid()::text
    or coalesce(p_shared, '[]'::jsonb) @> jsonb_build_array(jsonb_build_object('id', auth.uid()::text))
  )
$$;

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists tasks_touch on public.tasks;
create trigger tasks_touch before update on public.tasks
  for each row execute function public.touch_updated_at();
drop trigger if exists lists_touch on public.lists;
create trigger lists_touch before update on public.lists
  for each row execute function public.touch_updated_at();

-- A profile row for every account, filled from the sign-up email.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, lower(new.email), coalesce(split_part(new.email, '@', 1), ''))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Accounts created before this file was run.
insert into public.profiles (id, email, display_name)
select id, lower(email), coalesce(split_part(email, '@', 1), '') from auth.users
on conflict (id) do nothing;

-- ---------------------------------------------------------------- functions the apps call

-- Makes a new list with you as owner and the four starter categories.
create or replace function public.create_list(p_name text default 'Kay2-Do')
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_list uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  insert into public.lists (name, created_by)
  values (coalesce(nullif(trim(p_name), ''), 'Kay2-Do'), auth.uid())
  returning id into v_list;
  insert into public.list_members (list_id, user_id, role) values (v_list, auth.uid(), 'owner');
  insert into public.categories (list_id, key, label, color, sort_order) values
    (v_list, 'home', 'Home', 0, 0),
    (v_list, 'work', 'Work', 1, 1),
    (v_list, 'estate', 'Estate Planning', 2, 2),
    (v_list, 'longterm', 'Long Term', 3, 3);
  return v_list;
end $$;

-- Owner only. Adds the person right away if they already have an account,
-- otherwise records an invite that is picked up when they first sign in.
-- Returns 'added' or 'invited'.
create or replace function public.invite_member(p_list uuid, p_email text, p_role text default 'contributor')
returns text language plpgsql security definer set search_path = public, auth as $$
declare
  v_email text := lower(trim(p_email));
  v_user uuid;
begin
  if public.list_role(p_list) is distinct from 'owner' then
    raise exception 'Only the list owner can invite people';
  end if;
  if p_role not in ('editor', 'contributor') then raise exception 'Unknown role %', p_role; end if;
  if position('@' in v_email) < 2 then raise exception 'That email address is not complete'; end if;

  select id into v_user from auth.users where lower(email) = v_email limit 1;
  if v_user is not null then
    insert into public.list_members (list_id, user_id, role) values (p_list, v_user, p_role)
    on conflict (list_id, user_id) do update set role = excluded.role
      where public.list_members.role <> 'owner';
    perform public.link_email_to_user(p_list, v_email, v_user);
    return 'added';
  end if;
  insert into public.invites (list_id, email, role, invited_by) values (p_list, v_email, p_role, auth.uid())
  on conflict (list_id, email) do update set role = excluded.role;
  return 'invited';
end $$;

-- Tasks that named someone by email before they joined now point at their account.
create or replace function public.link_email_to_user(p_list uuid, p_email text, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_name jsonb := jsonb_build_object('name', p_email);
  v_id   jsonb := jsonb_build_object('id', p_user::text);
begin
  update public.tasks set owner = v_id
   where list_id = p_list and lower(owner ->> 'name') = p_email;
  update public.tasks t set shared = (
      select coalesce(jsonb_agg(distinct x), '[]'::jsonb) from (
        select case when lower(e ->> 'name') = p_email then v_id else e end as x
        from jsonb_array_elements(t.shared) e
      ) s
      where x is distinct from t.owner
    )
   where list_id = p_list
     and exists (select 1 from jsonb_array_elements(t.shared) e where lower(e ->> 'name') = p_email);
end $$;
revoke execute on function public.link_email_to_user(uuid, text, uuid) from public, anon, authenticated;

-- Called by both apps after sign-in: joins every list your email was invited to.
create or replace function public.accept_invites()
returns int language plpgsql security definer set search_path = public, auth as $$
declare
  v_email text;
  v_inv record;
  v_n int := 0;
begin
  if auth.uid() is null then return 0; end if;
  select lower(email) into v_email from auth.users where id = auth.uid();
  if v_email is null then return 0; end if;
  for v_inv in select * from public.invites where email = v_email loop
    insert into public.list_members (list_id, user_id, role) values (v_inv.list_id, auth.uid(), v_inv.role)
    on conflict (list_id, user_id) do nothing;
    perform public.link_email_to_user(v_inv.list_id, v_email, auth.uid());
    delete from public.invites where id = v_inv.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- Everyone on a list (members and pending invites), for pickers and the People panel.
create or replace function public.list_people(p_list uuid)
returns table (user_id uuid, email text, display_name text, role text, pending boolean)
language sql stable security definer set search_path = public as $$
  select m.user_id, p.email, coalesce(nullif(p.display_name, ''), split_part(p.email, '@', 1)), m.role, false
    from public.list_members m left join public.profiles p on p.id = m.user_id
   where m.list_id = p_list and public.list_role(p_list) is not null
  union all
  select null, i.email, i.email, i.role, true
    from public.invites i
   where i.list_id = p_list and public.list_role(p_list) is not null
$$;

grant execute on function public.create_list(text), public.invite_member(uuid, text, text),
  public.accept_invites(), public.list_people(uuid), public.list_role(uuid) to authenticated;

-- ---------------------------------------------------------------- row-level security

alter table public.profiles     enable row level security;
alter table public.lists        enable row level security;
alter table public.list_members enable row level security;
alter table public.invites      enable row level security;
alter table public.categories   enable row level security;
alter table public.tasks        enable row level security;

drop policy if exists "own profile read" on public.profiles;
create policy "own profile read" on public.profiles for select to authenticated using (id = auth.uid());
drop policy if exists "own profile write" on public.profiles;
create policy "own profile write" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "members read lists" on public.lists;
create policy "members read lists" on public.lists for select to authenticated
  using (public.list_role(id) is not null);
drop policy if exists "managers update lists" on public.lists;
create policy "managers update lists" on public.lists for update to authenticated
  using (public.list_role(id) in ('owner', 'editor')) with check (public.list_role(id) in ('owner', 'editor'));
drop policy if exists "owner deletes list" on public.lists;
create policy "owner deletes list" on public.lists for delete to authenticated
  using (public.list_role(id) = 'owner');

drop policy if exists "members read members" on public.list_members;
create policy "members read members" on public.list_members for select to authenticated
  using (public.list_role(list_id) is not null);
drop policy if exists "owner changes roles" on public.list_members;
create policy "owner changes roles" on public.list_members for update to authenticated
  using (public.list_role(list_id) = 'owner' and user_id <> auth.uid())
  with check (role in ('editor', 'contributor'));
drop policy if exists "owner removes or member leaves" on public.list_members;
create policy "owner removes or member leaves" on public.list_members for delete to authenticated
  using ((public.list_role(list_id) = 'owner' and user_id <> auth.uid())
         or (user_id = auth.uid() and role <> 'owner'));

drop policy if exists "owner manages invites" on public.invites;
create policy "owner manages invites" on public.invites for all to authenticated
  using (public.list_role(list_id) = 'owner') with check (public.list_role(list_id) = 'owner');

drop policy if exists "members read categories" on public.categories;
create policy "members read categories" on public.categories for select to authenticated
  using (public.list_role(list_id) is not null);
drop policy if exists "managers write categories" on public.categories;
create policy "managers write categories" on public.categories for all to authenticated
  using (public.list_role(list_id) in ('owner', 'editor'))
  with check (public.list_role(list_id) in ('owner', 'editor'));

drop policy if exists "members read tasks" on public.tasks;
create policy "members read tasks" on public.tasks for select to authenticated
  using (public.list_role(list_id) is not null);
drop policy if exists "members add tasks" on public.tasks;
create policy "members add tasks" on public.tasks for insert to authenticated
  with check (public.list_role(list_id) in ('owner', 'editor')
              or (public.list_role(list_id) = 'contributor' and created_by = auth.uid()));
drop policy if exists "people on a task change it" on public.tasks;
create policy "people on a task change it" on public.tasks for update to authenticated
  using (public.list_role(list_id) in ('owner', 'editor')
         or (public.list_role(list_id) = 'contributor'
             and (created_by = auth.uid() or public.task_involves_me(owner, shared))))
  with check (public.list_role(list_id) is not null);
drop policy if exists "managers or creator delete tasks" on public.tasks;
create policy "managers or creator delete tasks" on public.tasks for delete to authenticated
  using (public.list_role(list_id) in ('owner', 'editor')
         or (public.list_role(list_id) = 'contributor' and created_by = auth.uid()));

-- ---------------------------------------------------------------- uploaded background photos

-- Your role on the list a stored file belongs to; files live at '<list id>/<name>'.
create or replace function public.list_role_for_object(p_name text)
returns text language sql stable security definer set search_path = public as $$
  select case when split_part(p_name, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then public.list_role(split_part(p_name, '/', 1)::uuid) end
$$;
grant execute on function public.list_role_for_object(text) to authenticated;

-- A private bucket: everyone on a list can see its photos; owners and editors
-- can add and remove them. Up to 10 MB each (the apps shrink photos first).
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('backgrounds', 'backgrounds', false, 10485760, array['image/jpeg', 'image/png', 'image/webp'])
    on conflict (id) do update
      set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

    execute 'drop policy if exists "kay2do backgrounds read" on storage.objects';
    execute 'create policy "kay2do backgrounds read" on storage.objects for select to authenticated
      using (bucket_id = ''backgrounds'' and public.list_role_for_object(name) is not null)';
    execute 'drop policy if exists "kay2do backgrounds add" on storage.objects';
    execute 'create policy "kay2do backgrounds add" on storage.objects for insert to authenticated
      with check (bucket_id = ''backgrounds'' and public.list_role_for_object(name) in (''owner'', ''editor''))';
    execute 'drop policy if exists "kay2do backgrounds change" on storage.objects';
    execute 'create policy "kay2do backgrounds change" on storage.objects for update to authenticated
      using (bucket_id = ''backgrounds'' and public.list_role_for_object(name) in (''owner'', ''editor''))';
    execute 'drop policy if exists "kay2do backgrounds remove" on storage.objects';
    execute 'create policy "kay2do backgrounds remove" on storage.objects for delete to authenticated
      using (bucket_id = ''backgrounds'' and public.list_role_for_object(name) in (''owner'', ''editor''))';
  end if;
end $$;

-- ---------------------------------------------------------------- live updates

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.tasks;        exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.categories;   exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.lists;        exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.list_members; exception when duplicate_object then null; end;
  end if;
end $$;

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
