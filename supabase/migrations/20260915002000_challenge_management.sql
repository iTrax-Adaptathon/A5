-- Challenge creators may edit or delete only their own challenges.
-- Deleting a challenge cascades to participants, progress, submissions, and reviews.

drop policy if exists "challenges_update_own" on public.challenges;
create policy "challenges_update_own" on public.challenges for update
  using (auth.uid() = creator_id)
  with check (auth.uid() = creator_id);

create policy "challenges_delete_own" on public.challenges for delete
  using (auth.uid() = creator_id);
