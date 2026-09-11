-- sync_v1: cross-device sync of the voicings library, practice settings and
-- per-device stats buckets.
--
-- Every row is owned by one user and readable/writable only by that user
-- (RLS below). The app talks to these tables with the publishable key plus
-- the signed-in user's JWT; the service-role key never ships in the app.
-- Deleting the auth user (delete_account edge function) cascades here.

create table public.library_items (
  user_id    uuid not null references auth.users(id) on delete cascade,
  id         text not null check (length(id) <= 64),
  kind       text not null check (kind in ('voicing', 'folder', 'tag')),
  data       jsonb not null check (length(data::text) < 4096),
  position   double precision not null default 0,
  updated_at timestamptz not null default now(),
  deleted    boolean not null default false,
  primary key (user_id, id)
);
create index library_items_user_updated
  on public.library_items (user_id, updated_at);

-- One row per synced preference; newest updated_at wins per key.
create table public.user_settings (
  user_id    uuid not null references auth.users(id) on delete cascade,
  key        text not null check (length(key) <= 64),
  value      text not null check (length(value) < 4096),
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);

-- Each device uploads its own counters; clients sum the buckets on read, so
-- nothing is ever merged server-side and a repeated push can't double count.
create table public.device_stats (
  user_id    uuid not null references auth.users(id) on delete cascade,
  device_id  text not null check (length(device_id) <= 64),
  key        text not null check (length(key) <= 64),
  data       jsonb not null check (length(data::text) < 16384),
  updated_at timestamptz not null default now(),
  primary key (user_id, device_id, key)
);

-- Clock clamp: updated_at comes from the device, so a device whose clock is
-- wrong could otherwise win every merge. Anything more than 5 minutes ahead
-- of the server is pulled back to the server's idea of now.
create or replace function public.clamp_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := least(coalesce(new.updated_at, now()),
                          now() + interval '5 minutes');
  return new;
end
$$;

create trigger library_items_clamp before insert or update
  on public.library_items for each row execute function public.clamp_updated_at();
create trigger user_settings_clamp before insert or update
  on public.user_settings for each row execute function public.clamp_updated_at();
create trigger device_stats_clamp before insert or update
  on public.device_stats for each row execute function public.clamp_updated_at();

-- Owner-only access. No friend read: this data is private to the account.
alter table public.library_items enable row level security;
alter table public.user_settings enable row level security;
alter table public.device_stats  enable row level security;

create policy "own library_items" on public.library_items
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own user_settings" on public.user_settings
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own device_stats" on public.device_stats
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

revoke all on public.library_items, public.user_settings, public.device_stats
  from anon;
grant select, insert, update, delete
  on public.library_items, public.user_settings, public.device_stats
  to authenticated;
