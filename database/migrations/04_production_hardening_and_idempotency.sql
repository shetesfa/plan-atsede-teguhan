-- ============================================================
-- የአጸደ ትጉሃን የምርት ዝግጁነት እና ማመሳከሪያ ማጠናከሪያ (Migration 04: Production Hardening & Idempotency)
-- ============================================================

-- 1. የ chat_rooms ሰንጠረዥን በዳታቤዝ-ተኮር ፈቃድ ማጠናከር
ALTER TABLE `chat_rooms`
  ADD COLUMN IF NOT EXISTS `target_department_id` VARCHAR(50) NULL AFTER `type`,
  ADD COLUMN IF NOT EXISTS `is_office_only` TINYINT(1) DEFAULT 0 AFTER `target_department_id`,
  ADD COLUMN IF NOT EXISTS `is_public` TINYINT(1) DEFAULT 0 AFTER `is_office_only`;

-- ነባሪ ክፍሎችን በትክክለኛ ፈቃድ ማዘመን
UPDATE `chat_rooms` SET `is_public` = 1 WHERE `id` IN ('room_official', 'room_leaders', 'room_docs');
UPDATE `chat_rooms` SET `is_office_only` = 1, `is_public` = 0 WHERE `id` = 'room_office';

-- 2. የ sync_queue ሰንጠረዥን በ Idempotency Scope እና Hash ማጠናከር
ALTER TABLE `sync_queue`
  ADD COLUMN IF NOT EXISTS `user_id` INT NULL AFTER `device_id`,
  ADD COLUMN IF NOT EXISTS `payload_hash` VARCHAR(64) NULL AFTER `payload`,
  ADD COLUMN IF NOT EXISTS `error_message` TEXT NULL AFTER `conflict_resolution`;

-- 3. ፈጣን ፍለጋ ኢንዴክሶችን ማከል
ALTER TABLE `sync_queue`
  ADD INDEX IF NOT EXISTS `idx_sync_user_status` (`user_id`, `status`),
  ADD INDEX IF NOT EXISTS `idx_sync_device` (`device_id`);

ALTER TABLE `chat_message_reads`
  ADD INDEX IF NOT EXISTS `idx_cmr_msg_user` (`message_id`, `user_id`);

ALTER TABLE `notification_reads`
  ADD INDEX IF NOT EXISTS `idx_nr_notif_user` (`notification_id`, `user_id`);
