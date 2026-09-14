-- Additive migration for Q5. It assumes supabase/setup.sql has been applied once.
-- Existing files and existing rows are preserved.

alter table public.challenges
  add column if not exists status text not null default 'draft',
  add column if not exists visibility text not null default 'public',
  add column if not exists submission_deadline timestamptz,
  add column if not exists max_participants integer,
  add column if not exists updated_at timestamptz not null default now();

alter table public.participants
  add column if not exists last_progress_at timestamptz,
  add column if not exists withdrawn_at timestamptz;

alter table public.submissions
  add column if not exists status text not null default 'draft',
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists submitted_revision integer not null default 0;

alter table public.scores
  add column if not exists is_published boolean not null default false,
  add column if not exists calculated_at timestamptz,
  add column if not exists calculation_version text not null default 'v1';

do $$ begin
  alter table public.challenges add constraint challenges_status_check
    check (status in ('draft', 'open', 'active', 'closed', 'archived'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.challenges add constraint challenges_visibility_check
    check (visibility in ('public', 'unlisted', 'private'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.challenges add constraint challenges_max_participants_check
    check (max_participants is null or max_participants > 0);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.submissions add constraint submissions_status_check
    check (status in ('draft', 'submitted', 'under_review', 'verified', 'rejected', 'withdrawn'));
exception when duplicate_object then null; end $$;

-- Each challenge supplies the context needed to normalize different kinds of work.
create table if not exists public.challenge_rules (
  challenge_id bigint primary key references public.challenges(id) on delete cascade,
  challenge_type text not null,
  target_value numeric not null check (target_value > 0),
  target_unit text not null,
  submission_schema jsonb not null default '{}'::jsonb,
  rubric jsonb not null check (jsonb_typeof(rubric) = 'array'),
  scoring_weights jsonb not null default
    '{"completion":0.35,"quality":0.35,"verification":0.20,"peer":0.10}'::jsonb,
  peer_reviews_required smallint not null default 3 check (peer_reviews_required between 0 and 10),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((scoring_weights->>'completion')::numeric >= 0),
  check ((scoring_weights->>'quality')::numeric >= 0),
  check ((scoring_weights->>'verification')::numeric >= 0),
  check ((scoring_weights->>'peer')::numeric >= 0)
);

-- Append-only evidence makes progress auditable; participants cannot directly set a total.
create table if not exists public.progress_events (
  id bigint generated always as identity primary key,
  challenge_id bigint not null references public.challenges(id) on delete cascade,
  participant_id bigint not null references public.participants(id) on delete cascade,
  amount numeric not null check (amount > 0),
  note text,
  evidence_url text,
  recorded_at timestamptz not null default now()
);
create index if not exists progress_events_participant_recorded_idx
  on public.progress_events(participant_id, recorded_at desc);

-- A submission can be corrected while retaining every prior version for audit/review.
create table if not exists public.submission_versions (
  id bigint generated always as identity primary key,
  submission_id bigint not null references public.submissions(id) on delete cascade,
  revision integer not null check (revision > 0),
  content text,
  proof_url text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (submission_id, revision)
);

create table if not exists public.moderation_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('moderator', 'verifier', 'admin')),
  granted_at timestamptz not null default now()
);

create table if not exists public.review_assignments (
  id bigint generated always as identity primary key,
  submission_id bigint not null references public.submissions(id) on delete cascade,
  reviewer_id uuid not null references auth.users(id) on delete cascade,
  assigned_by uuid references auth.users(id),
  due_at timestamptz,
  status text not null default 'assigned' check (status in ('assigned', 'completed', 'expired', 'cancelled')),
  created_at timestamptz not null default now(),
  unique(submission_id, reviewer_id)
);

-- Reviews are allocated rather than solicited as likes. This blocks self-review and vote brigades.
create table if not exists public.submission_reviews (
  id bigint generated always as identity primary key,
  assignment_id bigint not null unique references public.review_assignments(id) on delete cascade,
  submission_id bigint not null references public.submissions(id) on delete cascade,
  reviewer_id uuid not null references auth.users(id) on delete cascade,
  rubric_scores jsonb not null check (jsonb_typeof(rubric_scores) = 'object'),
  overall_score numeric not null check (overall_score between 0 and 100),
  confidence smallint not null default 3 check (confidence between 1 and 5),
  rationale text,
  status text not null default 'submitted' check (status in ('submitted', 'accepted', 'discarded')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists submission_reviews_submission_idx
  on public.submission_reviews(submission_id) where status = 'accepted';

create table if not exists public.verification_checks (
  id bigint generated always as identity primary key,
  submission_id bigint not null references public.submissions(id) on delete cascade,
  verifier_id uuid not null references auth.users(id),
  status text not null check (status in ('pending', 'verified', 'rejected', 'flagged')),
  score numeric not null default 0 check (score between 0 and 100),
  notes text,
  created_at timestamptz not null default now()
);

-- Social interaction is deliberately separate from ranking.
create table if not exists public.submission_comments (
  id bigint generated always as identity primary key,
  submission_id bigint not null references public.submissions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.submission_reactions (
  submission_id bigint not null references public.submissions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction text not null check (reaction in ('support', 'inspiring', 'helpful')),
  created_at timestamptz not null default now(),
  primary key (submission_id, user_id, reaction)
);

create or replace function public.is_challenge_member(p_challenge_id bigint, p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.participants p
    where p.challenge_id = p_challenge_id and p.user_id = p_user_id and p.withdrawn_at is null
  );
$$;

create or replace function public.is_moderator(p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.moderation_roles where user_id = p_user_id);
$$;

-- Only active members may write progress. The legacy participants.progress is maintained as a
-- normalized 0–100 completion percentage and is never accepted directly from a client.
create or replace function public.record_progress(
  p_challenge_id bigint, p_amount numeric, p_note text default null, p_evidence_url text default null
) returns public.progress_events
language plpgsql security definer set search_path = public as $$
declare v_participant public.participants; v_target numeric; v_event public.progress_events;
begin
  if auth.uid() is null or p_amount <= 0 then raise exception 'Invalid progress request'; end if;
  select p.* into v_participant from public.participants p
    where p.challenge_id = p_challenge_id and p.user_id = auth.uid() and p.withdrawn_at is null;
  if not found then raise exception 'Join the challenge before recording progress'; end if;
  if exists (select 1 from public.challenges c where c.id = p_challenge_id and c.end_date is not null and c.end_date < current_date) then
    raise exception 'This challenge has ended';
  end if;
  select target_value into v_target from public.challenge_rules where challenge_id = p_challenge_id;
  if v_target is null then raise exception 'Challenge rules have not been configured'; end if;
  insert into public.progress_events(challenge_id, participant_id, amount, note, evidence_url)
    values (p_challenge_id, v_participant.id, p_amount, p_note, p_evidence_url) returning * into v_event;
  update public.participants set progress = least(100, round((
    select coalesce(sum(amount), 0) * 100 / v_target from public.progress_events where participant_id = v_participant.id
  ))::integer), last_progress_at = now() where id = v_participant.id;
  return v_event;
end;
$$;

create or replace function public.submit_submission(
  p_challenge_id bigint, p_content text, p_proof_url text, p_payload jsonb default '{}'::jsonb
) returns public.submissions
language plpgsql security definer set search_path = public as $$
declare v_submission public.submissions; v_revision integer;
begin
  if not public.is_challenge_member(p_challenge_id) then raise exception 'Join the challenge before submitting'; end if;
  if not exists (select 1 from public.challenges c where c.id = p_challenge_id and c.status in ('open', 'active')
    and (c.submission_deadline is null or c.submission_deadline >= now())) then raise exception 'Submissions are closed'; end if;
  insert into public.submissions(challenge_id, user_id, content, proof_url, status, submitted_at, updated_at, submitted_revision)
    values (p_challenge_id, auth.uid(), p_content, p_proof_url, 'submitted', now(), now(), 1)
  on conflict (challenge_id, user_id) do update set content = excluded.content, proof_url = excluded.proof_url,
    status = 'submitted', updated_at = now(), submitted_at = now(), submitted_revision = public.submissions.submitted_revision + 1
  returning * into v_submission;
  v_revision := v_submission.submitted_revision;
  insert into public.submission_versions(submission_id, revision, content, proof_url, payload)
    values (v_submission.id, v_revision, p_content, p_proof_url, coalesce(p_payload, '{}'::jsonb));
  return v_submission;
end;
$$;

-- Bayesian shrinkage prevents a few friendly reviewers from dominating a rank.
create or replace function public.recalculate_submission_score(p_submission_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_completion numeric; v_quality numeric; v_verification numeric; v_peer numeric; v_final numeric;
begin
  select p.progress into v_completion from public.submissions s join public.participants p
    on p.challenge_id = s.challenge_id and p.user_id = s.user_id where s.id = p_submission_id;
  select coalesce(avg(overall_score), 50) into v_quality from public.submission_reviews
    where submission_id = p_submission_id and status = 'accepted';
  select coalesce(avg(score), 0) into v_verification from public.verification_checks
    where submission_id = p_submission_id and status = 'verified';
  select (50 * 3 + coalesce(sum(overall_score * confidence), 0)) /
         (3 + coalesce(sum(confidence), 0)) into v_peer from public.submission_reviews
    where submission_id = p_submission_id and status = 'accepted';
  select v_completion * (r.scoring_weights->>'completion')::numeric +
         v_quality * (r.scoring_weights->>'quality')::numeric +
         v_verification * (r.scoring_weights->>'verification')::numeric +
         v_peer * (r.scoring_weights->>'peer')::numeric
    into v_final from public.submissions s join public.challenge_rules r on r.challenge_id = s.challenge_id
    where s.id = p_submission_id;
  insert into public.scores(submission_id, completion_score, quality_score, verification_score, peer_score, final_score, calculated_at)
    values (p_submission_id, coalesce(v_completion, 0), coalesce(v_quality, 0), coalesce(v_verification, 0), coalesce(v_peer, 50), coalesce(v_final, 0), now())
  on conflict (submission_id) do update set completion_score = excluded.completion_score, quality_score = excluded.quality_score,
    verification_score = excluded.verification_score, peer_score = excluded.peer_score, final_score = excluded.final_score,
    calculated_at = excluded.calculated_at;
end;
$$;

do $$ begin
  alter table public.scores add constraint scores_submission_id_unique unique (submission_id);
exception when duplicate_object then null; end $$;

create or replace view public.challenge_leaderboard with (security_invoker = true) as
select s.challenge_id, s.id as submission_id, s.user_id, sc.final_score,
  dense_rank() over (partition by s.challenge_id order by sc.final_score desc, sc.calculated_at asc) as rank
from public.submissions s join public.scores sc on sc.submission_id = s.id
where s.status = 'verified' and sc.is_published;

-- Replace permissive write policies with narrow policies. Service-role moderation bypasses RLS.
drop policy if exists "participants_update_own" on public.participants;
drop policy if exists "participants_insert_own" on public.participants;
drop policy if exists "submissions_insert_own" on public.submissions;
drop policy if exists "submissions_update_own" on public.submissions;
drop policy if exists "scores_select_all" on public.scores;
create policy "participants_join_open_challenge" on public.participants for insert with check (
  user_id = auth.uid() and exists (
    select 1 from public.challenges c
    where c.id = challenge_id and c.status in ('open', 'active')
      and (c.start_date is null or c.start_date <= current_date)
      and (c.end_date is null or c.end_date >= current_date)
      and (c.max_participants is null or (
        select count(*) from public.participants existing where existing.challenge_id = c.id and existing.withdrawn_at is null
      ) < c.max_participants)
  )
);
create policy "scores_select_published" on public.scores for select using (is_published or public.is_moderator());

create policy "progress_events_select_members" on public.progress_events for select
  using (public.is_challenge_member(challenge_id) or public.is_moderator());
create policy "submission_versions_select_owner_or_moderator" on public.submission_versions for select
  using (exists (select 1 from public.submissions s where s.id = submission_id and s.user_id = auth.uid()) or public.is_moderator());
create policy "review_assignments_select_owner" on public.review_assignments for select
  using (reviewer_id = auth.uid() or public.is_moderator());
create policy "reviews_select_reviewer_or_moderator" on public.submission_reviews for select
  using (reviewer_id = auth.uid() or public.is_moderator());
create policy "reviews_insert_assigned_reviewer" on public.submission_reviews for insert with check (
  reviewer_id = auth.uid() and exists (select 1 from public.review_assignments a
    join public.submissions s on s.id = a.submission_id
    where a.id = assignment_id and a.submission_id = submission_id and a.reviewer_id = auth.uid()
      and a.status = 'assigned' and s.user_id <> auth.uid())
);
create policy "comments_select_challenge_members" on public.submission_comments for select using (
  exists (select 1 from public.submissions s where s.id = submission_id and public.is_challenge_member(s.challenge_id))
);
create policy "comments_insert_own" on public.submission_comments for insert with check (
  user_id = auth.uid() and exists (select 1 from public.submissions s where s.id = submission_id and public.is_challenge_member(s.challenge_id))
);
create policy "comments_update_own" on public.submission_comments for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "comments_delete_own" on public.submission_comments for delete using (user_id = auth.uid());
create policy "reactions_select_challenge_members" on public.submission_reactions for select using (
  exists (select 1 from public.submissions s where s.id = submission_id and public.is_challenge_member(s.challenge_id))
);
create policy "reactions_insert_own" on public.submission_reactions for insert with check (
  user_id = auth.uid() and exists (select 1 from public.submissions s where s.id = submission_id and public.is_challenge_member(s.challenge_id))
);
create policy "reactions_delete_own" on public.submission_reactions for delete using (user_id = auth.uid());

alter table public.challenge_rules enable row level security;
alter table public.progress_events enable row level security;
alter table public.submission_versions enable row level security;
alter table public.moderation_roles enable row level security;
alter table public.review_assignments enable row level security;
alter table public.submission_reviews enable row level security;
alter table public.verification_checks enable row level security;
alter table public.submission_comments enable row level security;
alter table public.submission_reactions enable row level security;

revoke all on function public.recalculate_submission_score(bigint) from public;
grant execute on function public.record_progress(bigint, numeric, text, text) to authenticated;
grant execute on function public.submit_submission(bigint, text, text, jsonb) to authenticated;
grant execute on function public.recalculate_submission_score(bigint) to service_role;
