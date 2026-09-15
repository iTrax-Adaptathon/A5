# Common Ground — Community Challenge Platform

A web app where users create, join, and complete community challenges, submit
evidence of their progress, and get ranked through a scoring system designed
to resist popularity-contest voting and easily-gamed points.

Built for iTrax Adaptathon — Q5: Community Challenge Platform.

## Why this exists

Community challenge apps are easy to build but hard to keep fair — engagement
mechanics often collapse into popularity contests or get gamed by a few
motivated users. This project's core design goal is evaluating submissions
fairly across **heterogeneous challenge types** (a fitness challenge and a
creative-writing challenge can't be scored the same way) without letting raw
vote counts or friend-group brigading decide the leaderboard.

## Tech stack

| Layer | Technology | Why |
|---|---|---|
| Frontend | React 18 + Vite | Fast dev server, component-based UI, no build config needed |
| Routing | React Router | Multi-page SPA (browse, create, detail, leaderboard, profile) without full reloads |
| Backend | Supabase (Postgres + PostgREST + Auth) | Database, auto-generated REST API, and authentication with no custom server to write or host |
| Styling | Plain CSS (`src/styles.css`) | Hand-written, no framework currently wired up |

## Project structure

```
├── src/
│   ├── main.jsx          # React entry point
│   ├── App.jsx            # All routes, pages, and components
│   ├── supabase.js        # Supabase client setup
│   └── styles.css         # App styling
├── supabase/
│   ├── setup.sql                          # Base schema (run first)
│   └── migrations/
│       ├── 20260915000000_fair_challenge_platform.sql  # Scoring engine, rubrics, RLS
│       ├── 20260915001000_frontend_defaults.sql        # Auto-default rubric trigger
│       └── 20260915002000_challenge_management.sql     # Edit/delete own challenges
├── index.html
├── vite.config.js
└── package.json
```

## Getting started

### 1. Set up environment variables

Copy `.env.example` to `.env` and fill in your Supabase project's values:

```
VITE_SUPABASE_URL=https://<your-project-ref>.supabase.co
VITE_SUPABASE_ANON_KEY=<your-anon-public-key>
```

Use only the browser-safe **anon** key — never the service-role key here.

> **Note:** `VITE_SUPABASE_URL` must be the bare project URL only
> (`https://xxxx.supabase.co`), with no path suffix like `/rest/v1/`.
> The Supabase client appends the correct paths itself.

### 2. Set up the database

In the Supabase SQL Editor, run these files **in order**, each as its own
query, waiting for each to succeed before running the next:

1. `supabase/setup.sql`
2. `supabase/migrations/20260915000000_fair_challenge_platform.sql`
3. `supabase/migrations/20260915001000_frontend_defaults.sql`
4. `supabase/migrations/20260915002000_challenge_management.sql`

Then, under **Project Settings → Data API → Exposed schemas**, confirm
`public` is checked so the API can see the tables. If you add tables later
and the app can't find them, run this in the SQL Editor to refresh the cache:

```sql
NOTIFY pgrst, 'reload schema';
```

### 3. Install and run

```bash
npm install
npm run dev
```

## Scripts

| Command | Purpose |
|---|---|
| `npm run dev` | Start the local dev server with hot reload |
| `npm run build` | Build a production bundle into `dist/` |
| `npm run preview` | Serve the production build locally to sanity-check it |

## Data model

| Table | Purpose |
|---|---|
| `profiles` | One row per user, extending Supabase Auth |
| `challenges` | Challenges: title, description, category, difficulty, dates, status |
| `challenge_rules` | Per-challenge scoring weights, target goal, and rubric — this is what lets different challenge types be scored fairly |
| `participants` | Who joined which challenge, and their progress |
| `progress_events` | Append-only log of progress updates (not a directly-editable field, to prevent faking completion) |
| `submissions` | A participant's final submitted result + proof |
| `submission_versions` | Version history of edited submissions |
| `review_assignments` / `submission_reviews` | Peer review, assigned rather than open, so reviewers can't be chosen/brigaded by the submitter |
| `verification_checks` | Evidence verification records |
| `scores` | Final computed score per submission, broken into completion / quality / verification / peer components |

Participants interact with progress and submissions only through the
`record_progress(...)` and `submit_submission(...)` RPC functions — never by
writing directly to `participants.progress` or `submissions`, which keeps an
auditable trail and prevents users from just setting their own completion
percentage.

## Scoring & fairness design

Each submission's `final_score` is a weighted combination of four
independently-computed components (weights are configurable per challenge
via `challenge_rules`):

- **Completion** — did they meet the challenge's stated, objective goal
- **Quality** — rubric-scored, using criteria defined per challenge at
  creation time, not a single generic rating
- **Verification** — whether submitted proof was checked/confirmed
- **Peer** — community judgment, deliberately capped in influence using
  **Bayesian shrinkage** (pulled toward a neutral baseline until enough
  confident reviews accumulate), so a handful of motivated voters can't
  swing a ranking

Social interactions (comments, reactions) are intentionally kept separate
from scoring — they're for engagement, not rank.

Score computation and publication are privileged operations, restricted to a
trusted server context (service role / Supabase Edge Function), never
callable directly from the browser:

1. Assign a reviewer via `review_assignments`
2. Accept or discard their entry in `submission_reviews`
3. Add a `verification_checks` row
4. Call `recalculate_submission_score(submission_id)`
5. Set `scores.is_published = true` once ready for the leaderboard

## Known issues / TODO

- `tailwindcss` is listed as a dependency but has no config file wired up —
  either configure it (`tailwind.config.js` + `postcss.config.js`) or remove
  the dependency
- No admin/moderator UI yet for the review-and-publish workflow described
  above — currently done by hand via the SQL Editor or a script
- `community-challenge/` folder is currently empty/unused
