-- ==============================================
-- FIX: User Synchronization Trigger
-- Addresses the race condition where public.users is not ready
-- when partner registration occurs immediately after sign up.
-- ==============================================

-- 1. Create a robust handler function that runs LOCALLY and SYNCHRONOUSLY
create or replace function public.handle_new_user()
returns trigger as $$
declare
  _display_name text;
  _provider text;
begin
  -- Extract display name from metadata, fallback to email prefix
  _display_name := coalesce(
    new.raw_user_meta_data->>'display_name',
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'name',
    split_part(new.email, '@', 1)
  );

  -- Attempt to determine provider (optional, default to email)
  _provider := 'email';
  -- Note: Determining provider accurately requires parsing 'identities' which is complex in PL/pgSQL
  -- We'll rely on defaults or updates for now.

  insert into public.users (
    id,
    email,
    display_name,
    role,
    status,
    created_at,
    updated_at
  )
  values (
    new.id,
    new.email,
    _display_name,
    'user',
    'active',
    now(),
    now()
  )
  on conflict (id) do update set
    email = excluded.email,
    updated_at = now();

  return new;
end;
$$ language plpgsql security definer;

-- 2. Create the trigger on auth.users
-- This ensures that when a user is signed up, the public profile is created
-- within the SAME transaction, preventing the race condition.

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 3. Backfill script (Optional)
-- Ensures any users that might have been missed (due to the race) are created
insert into public.users (id, email, display_name)
select 
  id, 
  email, 
  coalesce(raw_user_meta_data->>'display_name', split_part(email, '@', 1))
from auth.users
where id not in (select id from public.users);
