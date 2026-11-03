-- MIGRATION: public.profiles + public.saved_events -> public.users
-- Run only after review. It copies profile/bookmark data, reconnects foreign keys,
-- then drops the two old application tables. Supabase auth.users is not touched.
begin;

create table public.users (
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

insert into public.users (id, email, role, name, usn, mobile, department, created_at, updated_at)
select id, email, role, name, usn, mobile, department, created_at, updated_at
from public.profiles;

update public.users u
set saved_event_ids = coalesce(
  (select array_agg(s.event_id order by s.created_at) from public.saved_events s where s.user_id = u.id),
  '{}'::uuid[]
);

alter table public.events drop constraint if exists events_organiser_id_fkey;
alter table public.events add constraint events_organiser_id_fkey
  foreign key (organiser_id) references public.users(id) on delete cascade;

alter table public.registrations drop constraint if exists registrations_user_id_fkey;
alter table public.registrations add constraint registrations_user_id_fkey
  foreign key (user_id) references public.users(id) on delete cascade;

alter table public.users enable row level security;

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

grant select, insert on public.users to authenticated;
revoke update on public.users from authenticated;
grant update (email, name, usn, mobile, department, saved_event_ids, updated_at) on public.users to authenticated;

-- These are the only two application tables removed by this migration.
drop table public.saved_events;
drop table public.profiles;
drop function if exists public.organiser_can_view_profile(uuid);

commit;

