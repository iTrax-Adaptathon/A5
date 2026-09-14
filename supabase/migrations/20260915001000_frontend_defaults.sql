-- Additive frontend support: every newly created challenge gets a safe, editable default rubric.
-- This keeps creation simple while ensuring record_progress has a normalized target.

create or replace function public.create_default_challenge_rules()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.challenge_rules (challenge_id, challenge_type, target_value, target_unit, rubric)
  values (new.id, coalesce(new.category, 'general'), 100, 'percent',
    '[{"key":"evidence","label":"Evidence quality","weight":1}]'::jsonb)
  on conflict (challenge_id) do nothing;
  return new;
end;
$$;

drop trigger if exists challenges_create_default_rules on public.challenges;
create trigger challenges_create_default_rules
  after insert on public.challenges
  for each row execute function public.create_default_challenge_rules();

create policy "challenge_rules_select_public" on public.challenge_rules
  for select using (true);
