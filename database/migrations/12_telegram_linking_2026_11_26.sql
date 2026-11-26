-- Migration 12 (2026-11-26): link each user's Telegram account to the
-- system, so the bot knows who is who (department-scoped views,
-- per-person reminders, password reset via a Telegram code, and
-- office approve/reject from inside Telegram).
--
-- users.telegram_chat_id: the Telegram chat id of the linked account
-- (NULL = not linked). One chat belongs to one user — enforced in
-- code on link (cleared from any other user first), not by a UNIQUE
-- index, so re-linking never fails on a stale row.
--
-- telegram_link_codes: one-time 6-digit codes the app generates for
-- the logged-in user; the user sends /start <code> to the bot and
-- the bot verifies it (bot.php link_verify). Codes are stored as
-- SHA-256 hashes only — the plain code is never stored or logged.
-- 15 minutes expiry, single use.
--
-- password_reset_codes: one-time 6-digit codes the bot requests for
-- a linked user (/reset); the user types the code + a new password
-- in the app's login screen (auth.php reset_with_code). Same rules:
-- hash only, 15 minutes, single use.
--
-- user_reminder_log: per-user reminder dedup (one reminder /
-- escalation per user per plan per day). The office reminder_log
-- stays untouched (its unique key is per plan, not per user).
--
-- TiDB-safe: one ADD COLUMN per statement; idempotent
-- (IF NOT EXISTS / CREATE TABLE IF NOT EXISTS).
ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `telegram_chat_id` VARCHAR(30) NULL;

CREATE TABLE IF NOT EXISTS `telegram_link_codes` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `user_id` INT NOT NULL,
  `code_hash` CHAR(64) NOT NULL,
  `expires_at` DATETIME NOT NULL,
  `used_at` DATETIME NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_link_codes_user` (`user_id`),
  INDEX `idx_link_codes_hash` (`code_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `password_reset_codes` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `user_id` INT NOT NULL,
  `code_hash` CHAR(64) NOT NULL,
  `expires_at` DATETIME NOT NULL,
  `used_at` DATETIME NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_reset_codes_user` (`user_id`),
  INDEX `idx_reset_codes_hash` (`code_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `user_reminder_log` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `user_id` INT NOT NULL,
  `plan_id` VARCHAR(100) NOT NULL,
  `kind` ENUM('reminder', 'escalation') NOT NULL,
  `sent_date` DATE NOT NULL,
  `sent_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_user_reminder` (`user_id`, `plan_id`, `kind`, `sent_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
