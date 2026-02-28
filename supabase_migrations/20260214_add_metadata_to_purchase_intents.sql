-- Add metadata column to purchase_intents table if it doesn't exist
do $$
begin
  if not exists (select 1 from information_schema.columns where table_name = 'purchase_intents' and column_name = 'metadata') then
    alter table purchase_intents add column metadata jsonb default '{}'::jsonb;
  end if;
end $$;
