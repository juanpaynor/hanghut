-- Make events socially legible.
--
-- There are 84 upcoming active events and 9 upcoming hangouts. Demand is not the
-- problem and it is already being recorded — 17,121 event_interactions rows, of
-- which 3,436 "get_tickets" taps by 137 distinct users in the last 30 days — but
-- nothing reads it back, and no event carries an "interested" or "going" signal
-- anywhere in the product. So none of that intent is visible to the next person.
--
-- This adds the state table and the batched read, mirroring
-- get_hangout_social_proof so both surfaces count and say the same things.
--
-- Deliberately NOT a new event_interactions.type: that vocabulary is a contract
-- with web's organizer analytics (view · get_tickets · pick_seats ·
-- checkout_started · share — see event_analytics_service.dart, team_comms #240).

create table if not exists public.event_interests (
  event_id   uuid        not null references public.events(id) on delete cascade,
  user_id    uuid        not null references public.users(id)  on delete cascade,
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

-- "What am I interested in" is a per-user lookup; the PK already covers per-event.
create index if not exists idx_event_interests_user on public.event_interests(user_id);

alter table public.event_interests enable row level security;

-- A user may only ever touch their own row. Counts and faces are not read
-- through this policy at all — they come from the SECURITY DEFINER function
-- below, so interest stays private per-row while still being countable.
drop policy if exists "Users manage their own event interest" on public.event_interests;
create policy "Users manage their own event interest"
  on public.event_interests
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());


create or replace function public.get_event_social_proof(p_event_ids uuid[])
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(jsonb_object_agg(x.id::text, x.state), '{}'::jsonb)
  from (
    select e.id,
      jsonb_build_object(
        -- PEOPLE, not ticket rows: buyers come in pairs, so KOOLCHELLA is 369
        -- people across 733 rows. And never 'available' — that is unsold stock
        -- (51,529 of 53,956 rows), which is how this has been miscounted before.
        -- Guests are included on purpose: 740 of ~804 upcoming ticket holders
        -- have no account, so an account-only count would render the biggest
        -- event in the product as empty.
        'going_count', (
          select count(distinct coalesce(t.user_id::text, lower(trim(t.guest_email))))
            from tickets t
           where t.event_id = e.id
             and t.status in ('valid', 'used')),

        'interested_count', (
          select count(*) from event_interests ei where ei.event_id = e.id),

        -- Faces, unlike counts, can only come from account holders. Even a
        -- 369-person event yields 8 of them, so this is a bonus on top of the
        -- number and the UI must read correctly when it is empty.
        'avatars', coalesce((
          select jsonb_agg(a.url)
            from (
              select u.avatar_url as url, min(t.created_at) as first_bought
                from tickets t
                join users u on u.id = t.user_id
               where t.event_id = e.id
                 and t.status in ('valid', 'used')
                 and u.avatar_url is not null
                 and u.avatar_url <> ''
                 and not exists (
                   select 1 from blocks b
                    where (b.blocker_user_id = auth.uid() and b.blocked_user_id = u.id)
                       or (b.blocker_user_id = u.id and b.blocked_user_id = auth.uid()))
               group by u.id, u.avatar_url
               -- Earliest buyers first, so the row is stable between reads.
               order by min(t.created_at)
               limit 3
            ) a), '[]'::jsonb),

        'viewer_state', (
          select case
            -- Holding a real ticket outranks anything the viewer tapped. Matched
            -- the way get_user_tickets already does it, so a guest buyer who
            -- later signs up with the same address sees themselves as going.
            when exists (
              select 1 from tickets t
               where t.event_id = e.id
                 and t.status in ('valid', 'used')
                 and (t.user_id = auth.uid()
                      or (t.guest_email is not null
                          and lower(trim(t.guest_email)) = (
                            select lower(trim(au.email))
                              from auth.users au
                             where au.id = auth.uid()
                               and au.email_confirmed_at is not null)))
            ) then 'going'
            when exists (
              select 1 from event_interests ei
               where ei.event_id = e.id and ei.user_id = auth.uid()
            ) then 'interested'
            else 'none'
          end)
      ) as state
      from events e
     where e.id = any(p_event_ids)
  ) x;
$function$;

comment on function public.get_event_social_proof(uuid[]) is
  'Batched social proof for events, keyed by event id. Counts people (not ticket rows) and includes guest buyers; avatars are account holders only.';

grant execute on function public.get_event_social_proof(uuid[]) to authenticated;
