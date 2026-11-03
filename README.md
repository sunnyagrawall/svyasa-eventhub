# EventHub

A responsive event discovery and hosting portal for students and campus organisers.

## Try it now

Open `index.html` in a browser. Without Supabase credentials, EventHub runs in demo mode and stores test accounts, events, saved events, user profiles, and registrations in that browser's local storage. New accounts are always students. Organiser access cannot be self-selected.

## Connect Supabase

1. Create a Supabase project.
2. Open the SQL Editor and run `supabase-schema.sql`. It creates exactly three EventHub tables in `public`: `users`, `events`, and `registrations`. Supabase's built-in `auth.users` is separate and required for login.
3. Put your project's **Project URL** and **anon/public key** into `config.js`. These are public browser credentials; never use a service-role key in this site.
4. In Supabase Authentication settings, enable Email and Password. Configure the allowed redirect URLs if you enable email confirmation.
5. Serve the folder over HTTP (for example, with `npx serve .` from this directory) and open the served `index.html`.

The login form includes **Forgot password?**. Supabase sends a recovery email and returns the student to EventHub to set a new password. For the local server used during development, add `http://localhost:8765/**` under **Authentication → URL Configuration → Redirect URLs**. Use the matching deployed site URL for production.

When both settings in `config.js` are present, the app uses Supabase Auth and stores student profiles and saved event IDs in `public.users`, events in `public.events`, and signups in `public.registrations`. The schema enables row-level security. Public visitors can browse events; only administrator-assigned organisers can publish events and see attendee details; student accounts can register once per event and see their registrations. Organiser accounts cannot register as student participants. A database trigger keeps registration counts current.

For an existing EventHub database that has `profiles` and `saved_events`, review `migrate-to-three-tables.sql` before running it. It copies profiles and bookmarks into `users`, reconnects event and registration references, then drops the two old tables. Do not run the fresh-install schema over an existing project as a migration.

If registration shows `infinite recursion detected in policy for relation "registrations"`, run `fix-registration-rls-recursion.sql` in Supabase **SQL Editor**, then refresh EventHub. This refreshes the user/registration access helpers without changing existing data.

### Assign organiser access

1. Have the person create an account and complete their student profile first.
2. In Supabase **Table Editor → users**, find their verified account and change `role` from `student` to `organiser`.
3. Or run this in the SQL Editor, replacing the address with the approved user's email:

```sql
update public.users
set role = 'organiser'
where email = 'approved.organiser@svyasa.edu.in';
```

The user's next login opens the organiser dashboard. Do not grant the organiser role based only on a self-request.

If you already used the earlier EventHub build, its signup screen allowed people to select Organiser. Review existing `organiser` rows before launch and reset any unapproved account to `student`; then promote only the approved organisers with the update above:

```sql
update public.users
set role = 'student'
where role = 'organiser';
```

Each event stores one `location` value, such as `P3 Building, 6th Floor, Room 601` or `Online`. The event form asks for that location in one field, and students can filter by the saved location. The separate building, floor, and room columns were removed from `public.events`; existing combined location text stays in place.

## Included flows

- Email/password signup and login. New accounts always receive the student role.
- Administrator-assigned organiser accounts with a separate event-management dashboard.
- Required profile setup: USN, name, mobile number, email address and department.
- Event search, category, format and single-location filters, plus popularity/date sorting for the S-VYASA City Campus.
- Event details and student registration.
- Organiser event publishing with date, time, format, location and participant limit.
- Saved events, a student registrations list and an organiser attendee list with CSV export.

Demo data and demo passwords are browser-local and are not suitable for production. Supabase email confirmation may require the student to confirm their email before logging in.


