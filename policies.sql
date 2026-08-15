-- =========================================================================
-- LiveChat - Row Level Security policies
-- Run AFTER schema.sql. Every table is locked down by default; these
-- policies open only the exact access patterns the app needs.
-- =========================================================================

alter table public.profiles enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_reads enable row level security;

-- -------------------------------------------------------------------------
-- profiles
-- Anyone authenticated can read all profiles (needed for user search / chat
-- headers). Users may only insert/update their OWN row.
-- -------------------------------------------------------------------------
drop policy if exists "profiles are readable by authenticated users" on public.profiles;
create policy "profiles are readable by authenticated users"
  on public.profiles for select
  to authenticated
  using (true);

drop policy if exists "users can insert their own profile" on public.profiles;
create policy "users can insert their own profile"
  on public.profiles for insert
  to authenticated
  with check (id = auth.uid());

drop policy if exists "users can update their own profile" on public.profiles;
create policy "users can update their own profile"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- -------------------------------------------------------------------------
-- conversation_members (helper used by policies below, defined first)
-- A user may read a conversation_members row if they themselves are a
-- member of that same conversation (lets them see the OTHER participant).
-- -------------------------------------------------------------------------
drop policy if exists "members can read their conversation memberships" on public.conversation_members;
create policy "members can read their conversation memberships"
  on public.conversation_members for select
  to authenticated
  using (
    conversation_id in (
      select conversation_id from public.conversation_members where user_id = auth.uid()
    )
  );

-- Direct inserts are blocked; membership rows are only created by the
-- SECURITY DEFINER function get_or_create_conversation().
drop policy if exists "no direct inserts into conversation_members" on public.conversation_members;
create policy "no direct inserts into conversation_members"
  on public.conversation_members for insert
  to authenticated
  with check (false);

drop policy if exists "users can update their own membership row" on public.conversation_members;
create policy "users can update their own membership row"
  on public.conversation_members for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- -------------------------------------------------------------------------
-- conversations
-- A user may read a conversation only if they belong to it.
-- Direct inserts are blocked; rows are only created via the SECURITY
-- DEFINER function get_or_create_conversation().
-- -------------------------------------------------------------------------
drop policy if exists "members can read their conversations" on public.conversations;
create policy "members can read their conversations"
  on public.conversations for select
  to authenticated
  using (
    id in (
      select conversation_id from public.conversation_members where user_id = auth.uid()
    )
  );

drop policy if exists "no direct inserts into conversations" on public.conversations;
create policy "no direct inserts into conversations"
  on public.conversations for insert
  to authenticated
  with check (false);

-- -------------------------------------------------------------------------
-- messages
-- Read/write only allowed for members of the parent conversation. Senders
-- may only insert messages as themselves, and may only "delete" (soft
-- delete, via UPDATE is_deleted) their own messages.
-- -------------------------------------------------------------------------
drop policy if exists "members can read messages in their conversations" on public.messages;
create policy "members can read messages in their conversations"
  on public.messages for select
  to authenticated
  using (
    conversation_id in (
      select conversation_id from public.conversation_members where user_id = auth.uid()
    )
  );

drop policy if exists "members can send messages as themselves" on public.messages;
create policy "members can send messages as themselves"
  on public.messages for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and conversation_id in (
      select conversation_id from public.conversation_members where user_id = auth.uid()
    )
  );

drop policy if exists "senders can edit or soft-delete their own messages" on public.messages;
create policy "senders can edit or soft-delete their own messages"
  on public.messages for update
  to authenticated
  using (sender_id = auth.uid())
  with check (sender_id = auth.uid());

-- -------------------------------------------------------------------------
-- message_reads
-- A user may read receipts for conversations they belong to, and may only
-- ever insert a read receipt for themselves.
-- -------------------------------------------------------------------------
drop policy if exists "members can read receipts in their conversations" on public.message_reads;
create policy "members can read receipts in their conversations"
  on public.message_reads for select
  to authenticated
  using (
    message_id in (
      select m.id from public.messages m
      join public.conversation_members cm on cm.conversation_id = m.conversation_id
      where cm.user_id = auth.uid()
    )
  );

drop policy if exists "users can mark messages read for themselves" on public.message_reads;
create policy "users can mark messages read for themselves"
  on public.message_reads for insert
  to authenticated
  with check (user_id = auth.uid());

-- -------------------------------------------------------------------------
-- Storage: chat-media bucket (profile photos + attachments)
-- Create the bucket first in Dashboard -> Storage -> "New bucket" named
-- "chat-media" and mark it PUBLIC (read), then run the policies below.
-- -------------------------------------------------------------------------
drop policy if exists "authenticated users can upload to chat-media" on storage.objects;
create policy "authenticated users can upload to chat-media"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'chat-media');

drop policy if exists "authenticated users can update their own chat-media files" on storage.objects;
create policy "authenticated users can update their own chat-media files"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'chat-media' and owner = auth.uid())
  with check (bucket_id = 'chat-media' and owner = auth.uid());

drop policy if exists "anyone can view chat-media files" on storage.objects;
create policy "anyone can view chat-media files"
  on storage.objects for select
  to public
  using (bucket_id = 'chat-media');

-- The delete-chat action is intentionally exposed only through the
-- SECURITY DEFINER function delete_conversation_for_user().
