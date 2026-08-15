-- =========================================================================
-- LiveChat - Supabase schema
-- Run this in the Supabase SQL editor (Project -> SQL Editor -> New query)
-- AFTER enabling the pgcrypto/uuid extension (done automatically below).
-- Then run policies.sql to enable Row Level Security.
-- =========================================================================

create extension if not exists "pgcrypto";

-- -------------------------------------------------------------------------
-- profiles: one row per auth.users row, holds public-facing user info
-- -------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique,
  display_name text,
  avatar_url text,
  about text default 'Hey there! I am using LiveChat.',
  is_online boolean not null default false,
  last_seen timestamptz default now(),
  created_at timestamptz not null default now()
);

create index if not exists idx_profiles_username on public.profiles (username);

-- -------------------------------------------------------------------------
-- conversations: one row per 1-to-1 chat
-- -------------------------------------------------------------------------
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now()
);

-- -------------------------------------------------------------------------
-- conversation_members: join table (exactly 2 rows per 1-to-1 conversation)
-- -------------------------------------------------------------------------
create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  last_read_at timestamptz not null default '1970-01-01',
  primary key (conversation_id, user_id)
);

create index if not exists idx_conversation_members_user on public.conversation_members (user_id);

-- -------------------------------------------------------------------------
-- messages
-- -------------------------------------------------------------------------
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  content text,
  message_type text not null default 'text' check (message_type in ('text', 'image')),
  attachment_url text,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  edited_at timestamptz
);

create index if not exists idx_messages_conversation on public.messages (conversation_id, created_at);
create index if not exists idx_messages_sender on public.messages (sender_id);

-- -------------------------------------------------------------------------
-- message_reads: per-user read receipts (also used to compute unread counts)
-- -------------------------------------------------------------------------
create table if not exists public.message_reads (
  message_id uuid not null references public.messages (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

create index if not exists idx_message_reads_user on public.message_reads (user_id);

-- =========================================================================
-- Trigger: auto-create a profile row whenever a new auth user signs up
-- =========================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'username', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data ->> 'username', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- =========================================================================
-- Trigger: bump conversations.last_message_at whenever a message is inserted
-- =========================================================================
create or replace function public.touch_conversation_on_message()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update public.conversations
  set last_message_at = new.created_at
  where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists on_message_inserted on public.messages;
create trigger on_message_inserted
  after insert on public.messages
  for each row execute procedure public.touch_conversation_on_message();

-- =========================================================================
-- Function: get_or_create_conversation(other_user_id)
-- Atomically finds an existing 1-to-1 conversation between the caller and
-- other_user_id, or creates one. Called via supabase.rpc() from the app.
-- =========================================================================
create or replace function public.get_or_create_conversation(other_user_id uuid)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  existing_id uuid;
  new_id uuid;
begin
  if other_user_id = auth.uid() then
    raise exception 'Cannot start a conversation with yourself';
  end if;

  select cm1.conversation_id into existing_id
  from public.conversation_members cm1
  join public.conversation_members cm2
    on cm1.conversation_id = cm2.conversation_id
  where cm1.user_id = auth.uid()
    and cm2.user_id = other_user_id
  limit 1;

  if existing_id is not null then
    return existing_id;
  end if;

  insert into public.conversations default values returning id into new_id;

  insert into public.conversation_members (conversation_id, user_id)
  values (new_id, auth.uid()), (new_id, other_user_id);

  return new_id;
end;
$$;

-- =========================================================================
-- Function: mark_conversation_read(p_conversation_id)
-- Marks every unread message in a conversation as read by the caller and
-- updates the caller's last_read_at pointer for fast unread-count queries.
-- =========================================================================
create or replace function public.mark_conversation_read(p_conversation_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.message_reads (message_id, user_id)
  select m.id, auth.uid()
  from public.messages m
  where m.conversation_id = p_conversation_id
    and m.sender_id != auth.uid()
  on conflict (message_id, user_id) do nothing;

  update public.conversation_members
  set last_read_at = now()
  where conversation_id = p_conversation_id
    and user_id = auth.uid();
end;
$$;

-- =========================================================================
-- View: conversation_overview
-- One row per conversation the CALLER belongs to, pre-joined with the other
-- participant's profile, the last message, and an unread count. Backed by
-- RLS on the underlying tables, so each user only ever sees their own rows.
-- =========================================================================
create or replace view public.conversation_overview
with (security_invoker = true) as
select distinct on (me.user_id, other.id)
  c.id as conversation_id,
  c.last_message_at,
  me.user_id as viewer_id,
  other.id as other_user_id,
  other.username as other_username,
  other.display_name as other_display_name,
  other.avatar_url as other_avatar_url,
  other.is_online as other_is_online,
  other.last_seen as other_last_seen,
  other.created_at as other_created_at,
  lm.id as last_message_id,
  lm.sender_id as last_message_sender_id,
  lm.content as last_message_content,
  lm.message_type as last_message_type,
  lm.is_deleted as last_message_is_deleted,
  lm.created_at as last_message_created_at,
  (
    select count(*)::int
    from public.messages um
    where um.conversation_id = c.id
      and um.sender_id != me.user_id
      and um.created_at > me.last_read_at
  ) as unread_count
from public.conversations c
join public.conversation_members me on me.conversation_id = c.id
join public.conversation_members other_member
  on other_member.conversation_id = c.id and other_member.user_id != me.user_id
join public.profiles other on other.id = other_member.user_id
left join lateral (
  select *
  from public.messages m
  where m.conversation_id = c.id
  order by m.created_at desc
  limit 1
) lm on true
order by me.user_id, other.id, c.last_message_at desc, c.id desc;

-- =========================================================================
-- Realtime: publish INSERT/UPDATE events for the tables the app subscribes to
-- =========================================================================
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.profiles;

-- Ensure UPDATE payloads include full row data (needed for read-status echoes)
alter table public.messages replica identity full;
alter table public.profiles replica identity full;

-- =========================================================================
-- Function: delete_conversation_for_user(p_conversation_id)
-- Removes the CALLER from a 1-to-1 conversation only. The other participant
-- keeps their copy. If nobody remains, the conversation is deleted and its
-- messages are removed by the ON DELETE CASCADE foreign key.
-- =========================================================================
create or replace function public.delete_conversation_for_user(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  member_count integer;
begin
  if not exists (
    select 1
    from public.conversation_members
    where conversation_id = p_conversation_id
      and user_id = auth.uid()
  ) then
    raise exception 'You are not a member of this conversation';
  end if;

  delete from public.conversation_members
  where conversation_id = p_conversation_id
    and user_id = auth.uid();

  select count(*) into member_count
  from public.conversation_members
  where conversation_id = p_conversation_id;

  if member_count = 0 then
    delete from public.conversations where id = p_conversation_id;
  end if;
end;
$$;

revoke all on function public.delete_conversation_for_user(uuid) from public;
grant execute on function public.delete_conversation_for_user(uuid) to authenticated;
