# Fair challenge migration

`20260915000000_fair_challenge_platform.sql` is additive: it does not edit or delete any existing project file or database row.

Apply `supabase/setup.sql` first if this is a new database, then apply this migration through the Supabase SQL Editor or your normal migration deployment process. The migration adds:

- configurable goals, submission schemas, rubrics, and score weights per challenge;
- append-only progress evidence and normalized completion;
- versioned submissions, allocated peer review, and verification records;
- a Bayesian-shrunk peer score, separate social reactions/comments, and a published-only leaderboard;
- RLS policies which prevent client-side score updates and require assigned, non-self reviewers.

The application should use `record_progress(...)` and `submit_submission(...)` RPCs instead of direct writes to `participants.progress` or `submissions`. A trusted server/moderation process assigns reviews, accepts or discards them, records verification checks, calls `recalculate_submission_score(submission_id)`, and sets `scores.is_published = true` only after review is complete.
