create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text,
  created_at timestamptz default now()
);

create table if not exists challenges (
  id bigint generated always as identity primary key,
  title text not null,
  description text,
  category text,
  difficulty text default 'medium',
  creator_id uuid references auth.users(id),
  start_date date,
  end_date date,
  created_at timestamptz default now()
);

create table if not exists participants (
  id bigint generated always as identity primary key,
  challenge_id bigint references challenges(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  progress integer default 0,
  joined_at timestamptz default now(),
  unique(challenge_id, user_id)
);

create table if not exists submissions (
  id bigint generated always as identity primary key,
  challenge_id bigint references challenges(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  content text,
  proof_url text,
  submitted_at timestamptz default now(),
  unique(challenge_id, user_id)
);

create table if not exists scores (
  id bigint generated always as identity primary key,
  submission_id bigint references submissions(id) on delete cascade,
  completion_score numeric default 0,
  quality_score numeric default 0,
  verification_score numeric default 0,
  peer_score numeric default 0,
  final_score numeric default 0
);

alter table profiles enable row level security;
alter table challenges enable row level security;
alter table participants enable row level security;
alter table submissions enable row level security;
alter table scores enable row level security;

create policy "profiles_select_all"
on profiles for select
using (true);

create policy "profiles_insert_own"
on profiles for insert
with check (auth.uid() = id);

create policy "profiles_update_own"
on profiles for update
using (auth.uid() = id);

create policy "challenges_select_all"
on challenges for select
using (true);

create policy "challenges_insert_authenticated"
on challenges for insert
with check (auth.uid() = creator_id);

create policy "challenges_update_own"
on challenges for update
using (auth.uid() = creator_id);

create policy "participants_select_all"
on participants for select
using (true);

create policy "participants_insert_own"
on participants for insert
with check (auth.uid() = user_id);

create policy "participants_update_own"
on participants for update
using (auth.uid() = user_id);

create policy "submissions_select_all"
on submissions for select
using (true);

create policy "submissions_insert_own"
on submissions for insert
with check (auth.uid() = user_id);

create policy "submissions_update_own"
on submissions for update
using (auth.uid() = user_id);

create policy "scores_select_all"
on scores for select
using (true);