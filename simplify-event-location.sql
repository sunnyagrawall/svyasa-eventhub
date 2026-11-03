-- Keep event location as one readable text field and remove its redundant components.
begin;

drop index if exists public.events_venue_idx;
alter table public.events
  drop column if exists venue_building,
  drop column if exists venue_floor,
  drop column if exists room_number;

commit;

