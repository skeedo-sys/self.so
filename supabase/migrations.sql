
-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- 1. Profiles Table
-- Stores user profile information and subscription tier details.
create table public.profiles (
  id uuid references auth.users not null primary key,
  username text unique,
  full_name text,
  avatar_url text,
  website text,
  bio text,
  plan_tier text check (plan_tier in ('free', 'pro', 'enterprise')) default 'free',
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable RLS for Profiles
alter table public.profiles enable row level security;

create policy "Public profiles are viewable by everyone." 
  on public.profiles for select using (true);

create policy "Users can insert their own profile." 
  on public.profiles for insert with check (auth.uid() = id);

create policy "Users can update own profile." 
  on public.profiles for update using (auth.uid() = id);

-- 2. Posts Table
-- Stores tweets, threads (linked via parent_post_id if needed, or structured content), and drafts.
create table public.posts (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references public.profiles(id) not null,
  content text,
  media_urls text[], -- Array of image/video URLs
  scheduled_at timestamp with time zone,
  published_at timestamp with time zone,
  status text check (status in ('draft', 'scheduled', 'published', 'failed', 'queue')) default 'draft',
  
  -- Engagement metrics snapshot
  likes_count int default 0,
  retweets_count int default 0,
  replies_count int default 0,
  impressions_count int default 0,
  
  -- Evergreen logic
  is_evergreen boolean default false,
  evergreen_collection_id uuid, -- Foreign key added later
  
  -- Thread logic
  thread_id uuid, -- Group ID for a thread
  position_in_thread int default 0,
  
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable RLS for Posts
alter table public.posts enable row level security;

create policy "Users can view own posts." 
  on public.posts for select using (auth.uid() = user_id);

create policy "Users can create own posts." 
  on public.posts for insert with check (auth.uid() = user_id);

create policy "Users can update own posts." 
  on public.posts for update using (auth.uid() = user_id);

create policy "Users can delete own posts." 
  on public.posts for delete using (auth.uid() = user_id);

-- 3. Evergreen Collections Table
-- Groups posts that should be recycled.
create table public.evergreen_collections (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references public.profiles(id) not null,
  name text not null,
  color text default '#607AFB',
  schedule_pattern jsonb, -- e.g. {"days": ["mon", "wed"], "time": "09:00"}
  is_active boolean default true,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Add foreign key reference back to posts table
alter table public.posts 
  add constraint fk_evergreen_collection 
  foreign key (evergreen_collection_id) 
  references public.evergreen_collections(id)
  on delete set null;

-- Enable RLS for Evergreen Collections
alter table public.evergreen_collections enable row level security;

create policy "Users can manage their evergreen collections." 
  on public.evergreen_collections for all using (auth.uid() = user_id);

-- 4. Templates Table
-- Stores reusable thread structures.
create table public.templates (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references public.profiles(id), -- Nullable if it's a system template
  is_system boolean default false,
  title text not null,
  description text,
  category text,
  content_structure jsonb, -- Array of strings representing tweet structure
  icon_name text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable RLS for Templates
alter table public.templates enable row level security;

create policy "Users can view system templates and their own." 
  on public.templates for select 
  using (is_system = true or auth.uid() = user_id);

create policy "Users can create their own templates." 
  on public.templates for insert 
  with check (auth.uid() = user_id);

create policy "Users can update their own templates." 
  on public.templates for update 
  using (auth.uid() = user_id);

-- 5. User Settings Table
-- Stores application preferences.
create table public.user_settings (
  user_id uuid references public.profiles(id) primary key,
  auto_retweet boolean default false,
  quiet_hours_start time,
  quiet_hours_end time,
  scheduling_sensitivity text default 'balanced',
  timezone text default 'UTC',
  connected_accounts jsonb default '{}'::jsonb -- Store auth tokens/status for X, LinkedIn, etc.
);

-- Enable RLS for Settings
alter table public.user_settings enable row level security;

create policy "Users can manage their own settings." 
  on public.user_settings for all using (auth.uid() = user_id);

-- 6. Analytics Snapshots (Optional but recommended for SaaS)
-- Stores daily/weekly aggregated metrics.
create table public.analytics_snapshots (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references public.profiles(id) not null,
  date date not null,
  platform text not null, -- 'twitter', 'linkedin'
  followers_count int,
  impressions_count int,
  engagement_rate numeric,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable RLS for Analytics
alter table public.analytics_snapshots enable row level security;

create policy "Users can view their own analytics." 
  on public.analytics_snapshots for select using (auth.uid() = user_id);

