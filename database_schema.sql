-- 1. Profiles (Managed by Supabase Auth)
-- This table is optional if you just use auth.users, but good for the future.
-- For Nebula, we rely on auth.users linking.

-- 2. Favorites Table
create table public.favorites (
  id uuid not null default gen_random_uuid (),
  user_id uuid not null references auth.users (id) on delete cascade,
  track_id text not null,
  title text not null,
  artist text not null,
  thumbnail_url text not null,
  duration_seconds integer not null default 0,
  created_at timestamp with time zone not null default now(),
  constraint favorites_pkey primary key (id),
  constraint favorites_user_track_key unique (user_id, track_id)
);

-- RLS for Favorites
alter table public.favorites enable row level security;

create policy "Users can view their own favorites" on public.favorites
  for select using ((select auth.uid()) = user_id);

create policy "Users can insert their own favorites" on public.favorites
  for insert with check ((select auth.uid()) = user_id);

create policy "Users can delete their own favorites" on public.favorites
  for delete using ((select auth.uid()) = user_id);


-- 3. Playlists Table
create table public.playlists (
  id uuid not null default gen_random_uuid (),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  created_at timestamp with time zone not null default now(),
  constraint playlists_pkey primary key (id)
);

-- RLS for Playlists
alter table public.playlists enable row level security;

create policy "Users can view their own playlists" on public.playlists
  for select using ((select auth.uid()) = user_id);

create policy "Users can insert their own playlists" on public.playlists
  for insert with check ((select auth.uid()) = user_id);

create policy "Users can update their own playlists" on public.playlists
  for update using ((select auth.uid()) = user_id);

create policy "Users can delete their own playlists" on public.playlists
  for delete using ((select auth.uid()) = user_id);


-- 4. Playlist Tracks (Association Table)
create table public.playlist_tracks (
  id uuid not null default gen_random_uuid (),
  playlist_id uuid not null references public.playlists (id) on delete cascade,
  track_id text not null,
  title text not null,
  artist text not null,
  thumbnail_url text not null,
  duration_seconds integer not null default 0,
  added_at timestamp with time zone not null default now(),
  constraint playlist_tracks_pkey primary key (id)
);

-- RLS for Playlist Tracks
-- We check if the parent playlist belongs to the user
alter table public.playlist_tracks enable row level security;

create policy "Users can manage tracks in their playlists" on public.playlist_tracks
  for all using (
    exists (
      select 1 from public.playlists
      where id = playlist_tracks.playlist_id
      and user_id = (select auth.uid())
    )
  );

-- 5. Performance Indexes (Fixes Supabase Warnings)
-- Supabase warns if RLS is enabled but the filtering columns are not indexed.
create index favorites_user_id_idx on public.favorites (user_id);
create index playlists_user_id_idx on public.playlists (user_id);
create index playlist_tracks_playlist_id_idx on public.playlist_tracks (playlist_id);
