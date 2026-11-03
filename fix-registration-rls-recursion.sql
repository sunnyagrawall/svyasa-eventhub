-- Repairs the role/profile visibility helpers for the three-table schema.
-- Use migrate-to-three-tables.sql first if the project still has profiles/saved_events.
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

drop policy if exists "Organisers can publish events" on public.events;
create policy "Organisers can publish events" on public.events for insert to authenticated with check (
  organiser_id = (select auth.uid()) and (select public.current_eventhub_role()) = 'organiser'
);

drop policy if exists "Students can register themselves" on public.registrations;
create policy "Students can register themselves" on public.registrations for insert to authenticated with check (
  user_id = (select auth.uid())
  and (select public.current_eventhub_role()) = 'student'
  and exists (
    select 1 from public.events e where e.id = event_id and e.registrations_count < e.max_participants
  )
);

