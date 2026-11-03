-- EventHub public schema: exactly three application tables.
-- Supabase's auth.users is a separate system table and remains required for login.
create extension if not exists pgcrypto;

create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  role text not null default 'student' check (role in ('student', 'organiser')),
  name text,
  usn text unique,
  mobile text,
  department text,
  saved_event_ids uuid[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  organiser_id uuid not null references public.users(id) on delete cascade,
  organiser_name text not null,
  title text not null,
  category text not null,
  description text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  location text not null,
  mode text not null default 'Offline' check (mode in ('Offline', 'Online', 'Hybrid')),
  max_participants integer not null check (max_participants > 0),
  registrations_count integer not null default 0 check (registrations_count >= 0),
  image_url text,
  created_at timestamptz not null default now(),
  constraint event_time_order check (ends_at > starts_at)
);

create table if not exists public.registrations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint one_registration_per_student unique (event_id, user_id)
);

create index if not exists events_starts_at_idx on public.events(starts_at);
create index if not exists events_category_idx on public.events(category);
create index if not exists registrations_user_id_idx on public.registrations(user_id);

alter table public.users enable row level security;
alter table public.events enable row level security;
alter table public.registrations enable row level security;

create or replace function public.current_eventhub_role()
returns text language sql stable security definer set search_path = '' as $$
  select u.role from public.users u where u.id = (select auth.uid())
$$;

create or replace function public.organiser_can_view_user(target_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.current_eventhub_role() = 'organiser' and exists (
    select 1 from public.registrations r
    join public.events e on e.id = r.event_id
    where r.user_id = target_user_id and e.organiser_id = (select auth.uid())
  )
$$;

revoke all on function public.current_eventhub_role() from public, anon;
revoke all on function public.organiser_can_view_user(uuid) from public, anon;
grant execute on function public.current_eventhub_role() to authenticated;
grant execute on function public.organiser_can_view_user(uuid) to authenticated;

drop policy if exists "Users visible to owner and event organisers" on public.users;
create policy "Users visible to owner and event organisers" on public.users for select to authenticated using (
  id = (select auth.uid()) or (select public.organiser_can_view_user(id))
);
drop policy if exists "Users can create their own student account" on public.users;
create policy "Users can create their own student account" on public.users for insert to authenticated with check (
  id = (select auth.uid()) and role = 'student'
);
drop policy if exists "Users can update their own profile" on public.users;
create policy "Users can update their own profile" on public.users for update to authenticated using (
  id = (select auth.uid())
) with check (id = (select auth.uid()));

create or replace function public.force_student_signup_role()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.role = 'student';
  return new;
end;
$$;
drop trigger if exists users_force_student_role on public.users;
create trigger users_force_student_role before insert on public.users
for each row execute function public.force_student_signup_role();

drop policy if exists "Events are public to read" on public.events;
create policy "Events are public to read" on public.events for select using (true);
drop policy if exists "Organisers can publish events" on public.events;
create policy "Organisers can publish events" on public.events for insert to authenticated with check (
  organiser_id = (select auth.uid()) and (select public.current_eventhub_role()) = 'organiser'
);
drop policy if exists "Organisers can update their events" on public.events;
create policy "Organisers can update their events" on public.events for update to authenticated using (
  organiser_id = (select auth.uid())
) with check (organiser_id = (select auth.uid()));
drop policy if exists "Organisers can delete their events" on public.events;
create policy "Organisers can delete their events" on public.events for delete to authenticated using (
  organiser_id = (select auth.uid())
);

drop policy if exists "Students and organisers can read relevant registrations" on public.registrations;
create policy "Students and organisers can read relevant registrations" on public.registrations for select to authenticated using (
  user_id = (select auth.uid()) or exists (
    select 1 from public.events e where e.id = event_id and e.organiser_id = (select auth.uid())
  )
);
drop policy if exists "Students can register themselves" on public.registrations;
create policy "Students can register themselves" on public.registrations for insert to authenticated with check (
  user_id = (select auth.uid()) and (select public.current_eventhub_role()) = 'student' and exists (
    select 1 from public.events e where e.id = event_id and e.registrations_count < e.max_participants
  )
);
drop policy if exists "Students can cancel their own registration" on public.registrations;
create policy "Students can cancel their own registration" on public.registrations for delete to authenticated using (
  user_id = (select auth.uid())
);

create or replace function public.update_event_registration_count()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    update public.events set registrations_count = registrations_count + 1 where id = new.event_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.events set registrations_count = greatest(registrations_count - 1, 0) where id = old.event_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists registrations_update_event_count on public.registrations;
create trigger registrations_update_event_count after insert or delete on public.registrations
for each row execute function public.update_event_registration_count();

grant usage on schema public to anon, authenticated;
grant select on public.events to anon, authenticated;
grant insert, update, delete on public.events to authenticated;
grant select, insert on public.users to authenticated;
revoke update on public.users from authenticated;
grant update (email, name, usn, mobile, department, saved_event_ids, updated_at) on public.users to authenticated;
grant select, insert, delete on public.registrations to authenticated;

