-- Migration 09 (2026-11-26): control department sees all departments (view-only).
--
-- can_view_all: when 1, the department's users may LIST all departments'
-- plans and reports (read-only) — the control (audit) department's main
-- work is controlling everyone, like the office. It does NOT grant plan
-- delete, report review, or user management (those stay super-admin /
-- dept_admin-scoped in the API). The flag lives on departments (like
-- is_super_admin) and is read fresh from the DB on every request.
--
-- TiDB-safe: one ADD COLUMN per statement; idempotent (IF NOT EXISTS).
ALTER TABLE `departments` ADD COLUMN IF NOT EXISTS `can_view_all` TINYINT(1) NOT NULL DEFAULT 0;

UPDATE `departments` SET `can_view_all` = 1 WHERE `id` = 'audit';
