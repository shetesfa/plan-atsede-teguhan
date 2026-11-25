-- 07 — chat_messages.updated_at (2026-11-25)
-- Live-test finding: chat.php PUT (edit) and DELETE both run
--   UPDATE chat_messages SET ... updated_at = NOW() ...
-- but the chat_messages table has NO updated_at column, so every
-- edit/delete crashes with HTTP 500 (empty body, display_errors Off).
-- This adds the missing column; the code already expects it.
-- TiDB-safe: one ADD COLUMN, IF NOT EXISTS (idempotent).
ALTER TABLE `chat_messages`
  ADD COLUMN IF NOT EXISTS `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`;
