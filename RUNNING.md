# Run Common Ground

1. Create `.env` from `.env.example` and set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`. Use only the browser-safe anonymous key—never a service-role key.
2. In Supabase SQL Editor, apply `supabase/setup.sql` once to create the original tables.
3. Apply the migrations in this order:
   - `supabase/migrations/20260915000000_fair_challenge_platform.sql`
   - `supabase/migrations/20260915001000_frontend_defaults.sql`
4. Install the dependencies listed in `package.json` and run `npm run dev`.

The file `supabase/20260915000000_fair_challenge_platform.sql` is not in the migrations directory. Do not apply it in addition to the matching migration file, or the same changes may be attempted twice.

## Review and scoring workflow

The participant-facing UI is complete. Review assignment, verification, score recalculation, and publication are intentionally privileged operations. Run those from a protected server or Supabase Edge Function using the service role, never from the browser.

1. Assign a reviewer in `review_assignments`.
2. Accept or discard their `submission_reviews`.
3. Add a `verification_checks` row.
4. Invoke `recalculate_submission_score(submission_id)`.
5. Set `scores.is_published` to `true` when the result is ready for the leaderboard.
