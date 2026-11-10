-- ============================================================
-- የአጸደ ትጉሃን የፍልሰት 04 ሮልባክ ስክሪፕት (Rollback Migration 04)
-- ============================================================

ALTER TABLE `chat_rooms`
  DROP COLUMN IF EXISTS `target_department_id`,
  DROP COLUMN IF EXISTS `is_office_only`,
  DROP COLUMN IF EXISTS `is_public`;

ALTER TABLE `sync_queue`
  DROP INDEX IF EXISTS `idx_sync_user_status`,
  DROP INDEX IF EXISTS `idx_sync_device`,
  DROP COLUMN IF EXISTS `user_id`,
  DROP COLUMN IF EXISTS `payload_hash`,
  DROP COLUMN IF EXISTS `error_message`;

ALTER TABLE `chat_message_reads`
  DROP INDEX IF EXISTS `idx_cmr_msg_user`;

ALTER TABLE `notification_reads`
  DROP INDEX IF EXISTS `idx_nr_notif_user`;
