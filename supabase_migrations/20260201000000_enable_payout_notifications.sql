-- Enable pg_net extension if not already enabled
create extension if not exists "pg_net";

-- Function to call the Edge Function
create or replace function public.handle_new_payout()
returns trigger as $$
declare
  -- TODO: Replace with your actual Anon Key or Service Role Key
  -- It is recommended to use Supabase Dashboard > Database > Webhooks for secure secret management
  service_key text := 'YOUR_SUPABASE_SERVICE_ROLE_KEY_HERE'; 
  func_url text := 'https://rahhezqtkpvkialnduft.supabase.co/functions/v1/send-payout-confirmation';
begin
  perform
    net.http_post(
      url := func_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_key
      ),
      body := jsonb_build_object(
        'type', TG_OP,
        'table', TG_TABLE_NAME,
        'schema', TG_TABLE_SCHEMA,
        'record', row_to_json(NEW)
      )
    );
  return new;
end;
$$ language plpgsql;

-- Trigger definition
drop trigger if exists on_payout_created on public.payouts;

create trigger on_payout_created
  after insert on public.payouts
  for each row execute procedure public.handle_new_payout();
