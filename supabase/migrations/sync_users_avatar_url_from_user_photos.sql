-- users.avatar_url was dead: 0 of 514 rows populated, yet 25+ client files and
-- 3 RPCs (get_event_attendees, get_experience_booking, get_stories_in_viewport)
-- read it as the source of truth. Twenty other RPCs had a user_photos fallback
-- patched into them one at a time instead of fixing the column.
--
-- Make the column true: derive it from the user's primary photo and keep it in
-- sync on every change. The existing per-RPC fallbacks become redundant but
-- stay harmless.
--
-- Applied to rahhezqtkpvkialnduft 2026-10-01, with the backfill below.

create or replace function public.sync_user_avatar_from_photos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user uuid := coalesce(new.user_id, old.user_id);
begin
  update public.users u
     set avatar_url = (
           select p.photo_url
             from public.user_photos p
            where p.user_id = target_user
              and p.photo_url is not null
              and p.photo_url <> ''
            -- Same precedence the app uses: primary first, then the explicit
            -- ordering it writes, then oldest.
            order by p.is_primary desc nulls last,
                     p.sort_order asc nulls last,
                     p.uploaded_at asc
            limit 1
         )
   where u.id = target_user;
  return null;
end;
$$;

comment on function public.sync_user_avatar_from_photos() is
  'Keeps users.avatar_url equal to the user''s primary user_photos row. Fired by user_photos_sync_avatar.';

drop trigger if exists user_photos_sync_avatar on public.user_photos;

create trigger user_photos_sync_avatar
after insert or update or delete on public.user_photos
for each row execute function public.sync_user_avatar_from_photos();

-- One-time backfill for the 227 users who already had a photo while
-- avatar_url sat empty. Same precedence as the trigger.
update public.users u
   set avatar_url = sub.photo_url
  from (
    select distinct on (p.user_id) p.user_id, p.photo_url
      from public.user_photos p
     where p.photo_url is not null and p.photo_url <> ''
     order by p.user_id,
              p.is_primary desc nulls last,
              p.sort_order asc nulls last,
              p.uploaded_at asc
  ) sub
 where u.id = sub.user_id
   and coalesce(u.avatar_url, '') <> sub.photo_url;
