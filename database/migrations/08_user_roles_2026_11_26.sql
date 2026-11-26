-- Migration 08 (2026-11-26): per-user permission role + department-admin support.
--
-- role: 'member' (default — a normal department user) or 'dept_admin'
-- (can manage — create/edit/delete — plans inside their OWN department
-- only; cannot see other departments, cannot review reports, cannot
-- manage users). Super admin stays department-based
-- (departments.is_super_admin) and is unaffected.
-- Tesfa works in the education department, so the education user is
-- given the dept_admin role here (he asked for more permission for
-- education, but NOT all-department access like the office).
--
-- TiDB-safe: one ADD COLUMN per statement; idempotent (IF NOT EXISTS).
ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `role` VARCHAR(20) NOT NULL DEFAULT 'member' AFTER `role_title`;

UPDATE `users` SET `role` = 'dept_admin' WHERE `username` = 'education';
