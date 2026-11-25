-- ============================================================
-- Migration 06 — Deep-audit fixes (2026-11-25)
--   * users.must_change_password — force the 10 seed passwords
--     to be changed on first login (the app had no screen for it).
--   * plans postpone persistence — the app kept postpone state
--     only in memory; the server stored just the new date.
--   * plans.due_date — real Gregorian due date computed from the
--     Ethiopian execution_time text (server-side parser port),
--     so reminders and overdue detection use a real date.
--   * reminder_log — one reminder / escalation per plan per day,
--     so the scheduler never spams the leaders' chat.
-- TiDB rules: one ADD COLUMN per ALTER, no inline UNIQUE.
-- Safe to run on the live atsede_db: all columns are nullable
-- or have defaults; old code ignores them.
-- ============================================================

-- 1. Force password change on first login (seed passwords).
ALTER TABLE `users`
  ADD COLUMN IF NOT EXISTS `must_change_password` TINYINT(1) DEFAULT 1 AFTER `status`;

-- 2. Postpone persistence on plans.
ALTER TABLE `plans`
  ADD COLUMN IF NOT EXISTS `original_execution_time` VARCHAR(500) NULL AFTER `execution_time`;
ALTER TABLE `plans`
  ADD COLUMN IF NOT EXISTS `postponed_date` VARCHAR(100) NULL AFTER `original_execution_time`;
ALTER TABLE `plans`
  ADD COLUMN IF NOT EXISTS `postpone_reason` TEXT NULL AFTER `postponed_date`;
ALTER TABLE `plans`
  ADD COLUMN IF NOT EXISTS `is_postponed` TINYINT(1) DEFAULT 0 AFTER `postpone_reason`;
ALTER TABLE `plans`
  ADD COLUMN IF NOT EXISTS `postponed_at` DATETIME NULL AFTER `is_postponed`;

-- 3. Real due date (Gregorian) parsed from execution_time.
ALTER TABLE `plans`
  ADD COLUMN IF NOT EXISTS `due_date` DATE NULL AFTER `target_date`;

-- 4. Reminder / escalation log (one per plan per kind per day).
CREATE TABLE IF NOT EXISTS `reminder_log` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `plan_id` VARCHAR(100) NOT NULL,
  `kind` ENUM('reminder', 'escalation') NOT NULL,
  `sent_date` DATE NOT NULL,
  `sent_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_reminder` (`plan_id`, `kind`, `sent_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
