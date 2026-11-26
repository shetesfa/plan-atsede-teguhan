<?php
// ============================================================
// የዐጸደ ትጉሃን ቦት ኤፒአይ (Telegram Bot API — 2026-11-26)
// ------------------------------------------------------------
// Server-to-server ONLY: the Telegram bot service calls this
// endpoint to link users, look up who a Telegram chat belongs
// to, read LIVE department-scoped plans, send password-reset
// codes and let the office approve/reject reports from inside
// Telegram. The Flutter app NEVER calls this endpoint, and no
// user JWT is accepted here.
//
// Auth: header `X-Bot-Proxy-Secret` (or `proxy_secret` field)
// equal to the BOT_PROXY_SECRET env var — the SAME secret the
// bot service holds in Render (see api/scheduler.php,
// api/import_plans.php). Without it: 401.
//
// Actions (POST JSON {"action": "...", ...}):
//   link_verify   {code, chat_id}            — link a Telegram chat to a user
//   user_by_chat  {chat_id}                  — who owns this chat (if linked)
//   plans_for     {chat_id}                  — LIVE plans for that user's department
//   recent_for    {chat_id}                  — plans due in the next 7 days (+overdue)
//   plans_summary {chat_id}                  — LIVE counts, dept-scoped (linked only)
//   plans_list    {department_id?, chat_id}   — LIVE plan list, dept-scoped (linked only)
//   plans_count   {}                         — LIVE total + per-dept counts (server-side only, no chat_id)
//   plans_all     {department_id?}           — LIVE full plan list, all depts (server-side only, no chat_id)
//   departments   {}                         — live department list (id, name)
//   plan_progress {plan_id, progress, chat_id} — update progress from Telegram
//   reset_request {username}                 — create a reset code (bot sends it)
//   reset_verify  {user_id, code, new_password} — verify code + set new password
//   report_review {report_id, action, chat_id, comment?} — office approve/reject
//
// Codes are 6 digits, valid 15 minutes, single use, stored as
// SHA-256 hashes only — the plain code is never stored or logged.
// ============================================================

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/ethiopian_date.php';

date_default_timezone_set('Africa/Addis_Ababa');

$input = getJsonInput();

$expected = (string)(getenv('BOT_PROXY_SECRET') ?: '');
if ($expected === '') {
    jsonError('የቦት ምስጢር (BOT_PROXY_SECRET) በአገልጋዩ ላይ አልተዋቀረም', 503);
}
$provided = $_SERVER['HTTP_X_BOT_PROXY_SECRET'] ?? ($input['proxy_secret'] ?? '');
if (!hash_equals($expected, (string)$provided)) {
    jsonError('ያልተፈቀደ ጥያቄ (Unauthorized)', 401);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonError('POST ብቻ ይፈቀዳል', 405);
}

$action = $input['action'] ?? '';
$today = new DateTimeImmutable('today', new DateTimeZone('Africa/Addis_Ababa'));
$todayStr = $today->format('Y-m-d');
$weekStr = $today->modify('+7 days')->format('Y-m-d');

// ---------- shared helpers ----------

function botUserByChat(PDO $pdo, string $chatId): ?array {
    if ($chatId === '') return null;
    $stmt = $pdo->prepare("
        SELECT u.id, u.username, u.full_name, u.role_title, u.role, u.department_id,
               u.telegram_chat_id, d.name AS department_name, d.short_name AS department_short_name,
               d.is_super_admin, d.can_view_all
        FROM users u
        JOIN departments d ON u.department_id = d.id
        WHERE u.telegram_chat_id = ? AND u.status = 'active'
        LIMIT 1
    ");
    $stmt->execute([$chatId]);
    $user = $stmt->fetch();
    return $user ?: null;
}

function botPublicUser(array $user): array {
    return [
        'user_id' => (int)$user['id'],
        'username' => $user['username'],
        'full_name' => $user['full_name'],
        'role_title' => $user['role_title'],
        'role' => $user['role'] ?? 'member',
        'department_id' => $user['department_id'],
        'department_name' => $user['department_name'],
        'department_short_name' => $user['department_short_name'],
        'is_super_admin' => (bool)($user['is_super_admin'] ?? false),
        'can_view_all' => (bool)($user['can_view_all'] ?? false),
    ];
}

// LIVE plans, fresh-parsed due dates (same rule as plans.php: the
// stored due_date is stale for multi-window plans, so the date is
// always parsed fresh from execution_time).
function botFetchLivePlans(PDO $pdo, ?string $departmentId): array {
    $sql = "
        SELECT p.id, p.department_id, d.name AS department_name,
               d.short_name AS department_short_name,
               p.main_task, p.detail_task, p.execution_time, p.due_date,
               p.progress_percent, p.status, p.is_postponed, p.postponed_date,
               (SELECT r.status FROM reports r WHERE r.plan_id = p.id AND r.is_deleted = 0
                ORDER BY r.created_at DESC, r.updated_at DESC LIMIT 1) AS latest_report_status
        FROM plans p
        JOIN departments d ON p.department_id = d.id
        WHERE (p.is_deleted = 0 OR p.is_deleted IS NULL)
    ";
    $params = [];
    if ($departmentId !== null && $departmentId !== '') {
        $sql .= " AND p.department_id = ?";
        $params[] = $departmentId;
    }
    $sql .= " ORDER BY p.due_date ASC, p.id ASC";
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $plans = $stmt->fetchAll();

    $out = [];
    foreach ($plans as $p) {
        $due = parseEthiopianDate($p['execution_time']) ?: $p['due_date'];
        $out[] = [
            'id' => $p['id'],
            'department_id' => $p['department_id'],
            'department_name' => $p['department_name'],
            'department_short_name' => $p['department_short_name'],
            'main_task' => $p['main_task'],
            'detail_task' => $p['detail_task'],
            'execution_time' => $p['execution_time'],
            'due_date' => $due,
            'due_date_ethiopian' => formatEthiopianDate($due),
            'progress_percent' => (int)$p['progress_percent'],
            'status' => $p['status'],
            'is_postponed' => (bool)$p['is_postponed'],
            'postponed_date' => $p['postponed_date'],
            'latest_report_status' => $p['latest_report_status'],
        ];
    }
    return $out;
}

function botIsReported(array $plan): bool {
    return in_array($plan['latest_report_status'], ['submitted', 'under_review', 'approved'], true);
}

function botPlanCounts(array $plans, string $todayStr, string $weekStr): array {
    $overdue = 0;
    $dueSoon = 0;
    foreach ($plans as $p) {
        if ($p['progress_percent'] >= 100 || botIsReported($p) || empty($p['due_date'])) continue;
        if ($p['due_date'] < $todayStr) {
            $overdue++;
        } elseif ($p['due_date'] <= $weekStr) {
            $dueSoon++;
        }
    }
    return ['total' => count($plans), 'overdue_count' => $overdue, 'due_soon_count' => $dueSoon];
}

// 6-digit one-time code: plain code returned to the caller (the bot
// server only), hash stored. Previous unused codes for the user die.
function botNewCode(PDO $pdo, string $table, int $userId): string {
    $code = (string)random_int(100000, 999999);
    $hash = hash('sha256', $code);
    $expires = date('Y-m-d H:i:s', time() + 900); // 15 minutes
    $pdo->prepare("UPDATE `$table` SET used_at = NOW() WHERE user_id = ? AND used_at IS NULL")->execute([$userId]);
    $pdo->prepare("INSERT INTO `$table` (user_id, code_hash, expires_at) VALUES (?, ?, ?)")->execute([$userId, $hash, $expires]);
    return $code;
}

function botVerifyCode(PDO $pdo, string $table, int $userId, string $code): ?array {
    $hash = hash('sha256', trim($code));
    $stmt = $pdo->prepare("
        SELECT id FROM `$table`
        WHERE user_id = ? AND code_hash = ? AND used_at IS NULL AND expires_at > NOW()
        ORDER BY created_at DESC LIMIT 1
    ");
    $stmt->execute([$userId, $hash]);
    $row = $stmt->fetch();
    return $row ?: null;
}

function botMarkCodeUsed(PDO $pdo, string $table, int $codeId): void {
    $pdo->prepare("UPDATE `$table` SET used_at = NOW() WHERE id = ?")->execute([$codeId]);
}

// 1. ቴሌግራም ማገናኘት — /start <ኮድ> (Link a chat to a user)
if ($action === 'link_verify') {
    $code = trim((string)($input['code'] ?? ''));
    $chatId = trim((string)($input['chat_id'] ?? ''));
    if ($code === '' || $chatId === '') {
        jsonError('ኮድ እና Chat ID ያስፈልጋሉ', 400);
    }
    $hash = hash('sha256', $code);
    $stmt = $pdo->prepare("
        SELECT c.id, c.user_id, u.username, u.full_name, u.department_id,
               d.name AS department_name
        FROM telegram_link_codes c
        JOIN users u ON u.id = c.user_id
        JOIN departments d ON u.department_id = d.id
        WHERE c.code_hash = ? AND c.used_at IS NULL AND c.expires_at > NOW()
          AND u.status = 'active'
        ORDER BY c.created_at DESC LIMIT 1
    ");
    $stmt->execute([$hash]);
    $row = $stmt->fetch();
    if (!$row) {
        jsonError('ኮዱ የተሳሳተ ነው ወይም ጊዜው አልፏል — በአፕ ውስጥ አዲስ ኮድ ጠይቅ', 400);
    }

    $pdo->beginTransaction();
    try {
        // አንድ chat የአንድ ሰው ብቻ ነው — ከሌላ ሰው ላይ ካለ መጀመሪያ አስወግድ።
        $pdo->prepare("UPDATE users SET telegram_chat_id = NULL WHERE telegram_chat_id = ? AND id <> ?")->execute([$chatId, (int)$row['user_id']]);
        $pdo->prepare("UPDATE users SET telegram_chat_id = ? WHERE id = ?")->execute([$chatId, (int)$row['user_id']]);
        $pdo->prepare("UPDATE telegram_link_codes SET used_at = NOW() WHERE id = ?")->execute([(int)$row['id']]);
        $pdo->commit();
    } catch (Exception $e) {
        $pdo->rollBack();
        error_log('bot link_verify error: ' . $e->getMessage());
        jsonError('ማገናኘት አልተቻለም — እባክዎ እንደገና ይሞክሩ', 500);
    }

    logAudit($pdo, 'telegram_link', 'users', (string)$row['user_id'], (int)$row['user_id'], $row['department_id'], ['chat_id' => $chatId]);
    jsonResponse([
        'user_id' => (int)$row['user_id'],
        'username' => $row['username'],
        'full_name' => $row['full_name'],
        'department_id' => $row['department_id'],
        'department_name' => $row['department_name'],
    ]);
}

// 2. ይህ chat የ누구 ነው? (Who owns this chat?)
if ($action === 'user_by_chat') {
    $chatId = trim((string)($input['chat_id'] ?? ''));
    $user = botUserByChat($pdo, $chatId);
    if (!$user) {
        jsonResponse(['linked' => false]);
    }
    jsonResponse(['linked' => true, 'user' => botPublicUser($user)]);
}

// 3. የዚህ ሰው ክፍል LIVE እቅዶች (Live plans for the linked user)
if ($action === 'plans_for') {
    $chatId = trim((string)($input['chat_id'] ?? ''));
    $user = botUserByChat($pdo, $chatId);
    if (!$user) {
        jsonError('ይህ Telegram account ከስርዓቱ ጋር አልተገናኘም', 404);
    }
    $dept = (!empty($user['is_super_admin']) || !empty($user['can_view_all'])) ? null : $user['department_id'];
    $plans = botFetchLivePlans($pdo, $dept);
    $counts = botPlanCounts($plans, $todayStr, $weekStr);
    jsonResponse([
        'user' => botPublicUser($user),
        'plans' => $plans,
        'total' => $counts['total'],
        'overdue_count' => $counts['overdue_count'],
    ]);
}

// 4. በቅርብ 7 ቀናት ውስጥ የሚደርሱ + የዘገዩ እቅዶች (Due in the next 7 days)
if ($action === 'recent_for') {
    $chatId = trim((string)($input['chat_id'] ?? ''));
    $user = botUserByChat($pdo, $chatId);
    // 2026-11-26 (link gate): unlinked chats see nothing at all.
    if (!$user) {
        jsonError('ይህ Telegram account ከስርዓቱ ጋር አልተገናኘም', 404);
    }
    $dept = null;
    if ($user && empty($user['is_super_admin']) && empty($user['can_view_all'])) {
        $dept = $user['department_id'];
    }
    $plans = botFetchLivePlans($pdo, $dept);
    $recent = [];
    foreach ($plans as $p) {
        if ($p['progress_percent'] >= 100 || botIsReported($p) || empty($p['due_date'])) continue;
        if ($p['due_date'] < $todayStr || $p['due_date'] <= $weekStr) {
            $recent[] = $p;
        }
    }
    usort($recent, function ($a, $b) {
        return strcmp($a['due_date'] ?? '', $b['due_date'] ?? '') ?: strcmp($a['id'], $b['id']);
    });
    $recent = array_slice($recent, 0, 20);
    jsonResponse([
        'user' => $user ? botPublicUser($user) : null,
        'today' => $todayStr,
        'plans' => $recent,
        'count' => count($recent),
    ]);
}

// 5. LIVE ማጠቃለያ — የክፍል እቅድ ብዛት (Live counts by department)
// 2026-11-26 (link gate): linked chats only; regular users see ONLY
// their own department's counts (office/audit see all).
if ($action === 'plans_summary') {
    $chatId = trim((string)($input['chat_id'] ?? ''));
    $user = botUserByChat($pdo, $chatId);
    if (!$user) {
        jsonError('ይህ Telegram account ከስርዓቱ ጋር አልተገናኘም', 404);
    }
    $dept = null;
    if (empty($user['is_super_admin']) && empty($user['can_view_all'])) {
        $dept = $user['department_id'];
    }
    $plans = botFetchLivePlans($pdo, $dept);
    $byDept = [];
    foreach ($plans as $p) {
        $name = $p['department_name'];
        $byDept[$name] = ($byDept[$name] ?? 0) + 1;
    }
    $counts = botPlanCounts($plans, $todayStr, $weekStr);
    jsonResponse([
        'total' => $counts['total'],
        'overdue_count' => $counts['overdue_count'],
        'by_department' => $byDept,
    ]);
}

// 6. LIVE እቅድ ዝርዝር — አንድ ክፍል (Live plan list)
// 2026-11-26 (link gate): linked chats only; regular users are forced
// to their own department (a requested other department is ignored).
if ($action === 'plans_list') {
    $chatId = trim((string)($input['chat_id'] ?? ''));
    $user = botUserByChat($pdo, $chatId);
    if (!$user) {
        jsonError('ይህ Telegram account ከስርዓቱ ጋር አልተገናኘም', 404);
    }
    $dept = $input['department_id'] ?? null;
    if (empty($user['is_super_admin']) && empty($user['can_view_all'])) {
        $dept = $user['department_id'];
    }
    $plans = botFetchLivePlans($pdo, ($dept === '' ? null : $dept));
    $counts = botPlanCounts($plans, $todayStr, $weekStr);
    jsonResponse([
        'plans' => $plans,
        'total' => $counts['total'],
        'overdue_count' => $counts['overdue_count'],
    ]);
}

// LIVE እቅድ ቆጠራ — ለሰርቨር ብቻ (server-side only, no chat_id)
// 2026-11-26 (live count fix): the bot service's own health endpoint
// (root `/` plans_count) and /api/plans need the LIVE count/list, but
// plans_list is link-gated since PR #40 and 404s without a chat_id.
// These two actions are proxy-secret only — the same trust boundary as
// every other bot.php action — and are never called from any Telegram
// handler, so no chat_id is required or accepted.
if ($action === 'plans_count') {
    $plans = botFetchLivePlans($pdo, null);
    $byDept = [];
    foreach ($plans as $p) {
        $name = $p['department_name'];
        $byDept[$name] = ($byDept[$name] ?? 0) + 1;
    }
    $counts = botPlanCounts($plans, $todayStr, $weekStr);
    jsonResponse([
        'total' => $counts['total'],
        'overdue_count' => $counts['overdue_count'],
        'due_soon_count' => $counts['due_soon_count'],
        'by_department' => $byDept,
    ]);
}

// LIVE እቅድ ዝርዝር — ለሰርቨር ብቻ (server-side only, all departments)
if ($action === 'plans_all') {
    $dept = $input['department_id'] ?? null;
    $plans = botFetchLivePlans($pdo, ($dept === '' ? null : $dept));
    $counts = botPlanCounts($plans, $todayStr, $weekStr);
    jsonResponse([
        'plans' => $plans,
        'total' => $counts['total'],
        'overdue_count' => $counts['overdue_count'],
    ]);
}

// 10. ክፍሎች ዝርዝር — ለቦቱ ክፍል ቁልፎች (Departments list, live)
if ($action === 'departments') {
    $stmt = $pdo->query("SELECT id, name, short_name FROM departments ORDER BY id ASC");
    jsonResponse(['departments' => $stmt->fetchAll()]);
}

// 11. እቅድ ክንውን ከቦቱ — Progress update from Telegram.
// Same update as plans.php PUT (clamp 0–100, 100% → completed,
// version +1, audit log), but the caller is a LINKED Telegram
// chat, not a JWT: the clicker must be a member of the plan's
// own department. The office and audit are view-only in the bot
// — they update progress from the app only.
if ($action === 'plan_progress') {
    $planId = trim((string)($input['plan_id'] ?? ''));
    $progress = isset($input['progress']) ? max(0, min(100, (int)$input['progress'])) : null;
    $chatId = trim((string)($input['chat_id'] ?? ''));
    if ($planId === '' || $chatId === '' || $progress === null) {
        jsonError('የዕቅድ መለያ፣ ክንውን እና Chat ID ያስፈልጋሉ', 400);
    }
    $user = botUserByChat($pdo, $chatId);
    if (!$user) {
        jsonError('ይህ Telegram account ከስርዓቱ ጋር አልተገናኘም', 403);
    }
    if (!empty($user['is_super_admin']) || !empty($user['can_view_all'])) {
        jsonError('ጽ/ቤት እና ቁጥጥር እቅድ ክንውን ከአፕ ውስጥ ብቻ ነው የሚያዘምኑት', 403);
    }
    $stmt = $pdo->prepare("SELECT id, department_id, status FROM plans WHERE id = ?");
    $stmt->execute([$planId]);
    $plan = $stmt->fetch();
    if (!$plan) {
        jsonError('እቅዱ አልተገኘም', 404);
    }
    if ($plan['department_id'] !== $user['department_id']) {
        jsonError('የሌላ ክፍል እቅድ ክንውን ማዘመን አይቻልም', 403);
    }
    $status = $progress >= 100 ? 'completed' : null;
    $pdo->prepare("UPDATE plans SET progress_percent = ?, status = COALESCE(?, status), version = version + 1 WHERE id = ?")
        ->execute([$progress, $status, $planId]);
    logAudit($pdo, 'update_plan_progress', 'plans', $planId, (int)$user['id'], $user['department_id'], [
        'progress_percent' => $progress,
        'status' => $status,
        'via' => 'telegram',
    ]);
    jsonResponse([
        'plan_id' => $planId,
        'progress_percent' => $progress,
        'status' => $status ?? ($plan['status'] ?? 'in_progress'),
    ]);
}

// 7. የይለፍ ቃል ዳግም ማስጀመሪያ ኮድ — ቦቱ ይጠይቃል፣ ኮዱን ወደ ተገናኘው
// chat ይልካል (Reset code — returned ONLY to the bot server)
if ($action === 'reset_request') {
    $identifier = trim((string)($input['username'] ?? $input['user_id'] ?? ''));
    if ($identifier === '') {
        jsonResponse(['ok' => false]);
    }
    $stmt = $pdo->prepare("
        SELECT u.id, u.full_name, u.telegram_chat_id
        FROM users u
        WHERE (u.username = ? OR u.department_id = ? OR CAST(u.id AS CHAR) = ?)
          AND u.status = 'active'
        LIMIT 1
    ");
    $stmt->execute([$identifier, $identifier, $identifier]);
    $user = $stmt->fetch();
    // ተጠቃሚው ካልተገኘ ወይም Telegram ካልተገናኘ — ተመሳሳይ ምላሽ
    // (የተጠቃሚ መኖር/አለመኖር እንዳይታወቅ)።
    if (!$user || empty($user['telegram_chat_id'])) {
        jsonResponse(['ok' => false]);
    }
    $userId = (int)$user['id'];
    $recentStmt = $pdo->prepare("SELECT COUNT(*) FROM password_reset_codes WHERE user_id = ? AND created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR)");
    $recentStmt->execute([$userId]);
    if ((int)$recentStmt->fetchColumn() >= 3) {
        jsonResponse(['ok' => false]);
    }
    $code = botNewCode($pdo, 'password_reset_codes', $userId);
    logAudit($pdo, 'telegram_reset_request', 'users', (string)$userId, $userId, null, []);
    jsonResponse([
        'ok' => true,
        'user_id' => $userId,
        'chat_id' => $user['telegram_chat_id'],
        'code' => $code,
        'full_name' => $user['full_name'],
    ]);
}

// 8. ኮድ አረጋግጥ + አዲስ የይለፍ ቃል አስቀምጥ (Verify code + set new password)
if ($action === 'reset_verify') {
    $userId = (int)($input['user_id'] ?? 0);
    $code = trim((string)($input['code'] ?? ''));
    $newPass = (string)($input['new_password'] ?? '');
    if ($userId <= 0 || $code === '' || $newPass === '') {
        jsonError('የተጠቃሚ መለያ፣ ኮድ እና አዲስ የይለፍ ቃል ያስፈልጋሉ', 400);
    }
    if (strlen($newPass) < 8 || !preg_match('/[0-9]/', $newPass)) {
        jsonError('አዲሱ የይለፍ ቃል ቢያንስ 8 ፊደላት እና ቢያንስ አንድ ቁጥር መያዝ አለበት።', 400);
    }
    $row = botVerifyCode($pdo, 'password_reset_codes', $userId, $code);
    if (!$row) {
        jsonError('ኮዱ የተሳሳተ ነው ወይም ጊዜው አልፏል — አዲስ ኮድ ጠይቅ', 400);
    }
    $hash = password_hash($newPass, PASSWORD_BCRYPT, ['cost' => 12]);
    $pdo->beginTransaction();
    try {
        // 2026-11-26: bump token_version so every token issued before
        // this reset stops working immediately.
        $pdo->prepare("UPDATE users SET password_hash = ?, must_change_password = 0, token_version = token_version + 1 WHERE id = ?")->execute([$hash, $userId]);
        botMarkCodeUsed($pdo, 'password_reset_codes', (int)$row['id']);
        $pdo->commit();
    } catch (Exception $e) {
        $pdo->rollBack();
        error_log('bot reset_verify error: ' . $e->getMessage());
        jsonError('የይለፍ ቃል መቀየር አልተቻለም — እባክዎ እንደገና ይሞክሩ', 500);
    }
    logAudit($pdo, 'telegram_password_reset', 'users', (string)$userId, $userId, null, []);
    jsonResponse(['message' => 'የይለፍ ቃልዎ በተሳካ ሁኔታ ተቀይሯል!']);
}

// 9. የፅ/ቤት ግምገማ ከቴሌግራም — Approve / Reject (Office review from the bot)
if ($action === 'report_review') {
    $reportId = trim((string)($input['report_id'] ?? ''));
    $reviewAction = trim((string)($input['action'] ?? ''));
    $chatId = trim((string)($input['chat_id'] ?? ''));
    $comment = trim((string)($input['comment'] ?? ''));
    if ($reportId === '' || $chatId === '') {
        jsonError('የሪፖርት መለያ እና Chat ID ያስፈልጋሉ', 400);
    }
    $map = ['approve' => 'approved', 'reject' => 'rejected'];
    if (!isset($map[$reviewAction])) {
        jsonError('ትክክለኛ ያልሆነ የግምገማ ውሳኔ', 400);
    }
    $status = $map[$reviewAction];

    $user = botUserByChat($pdo, $chatId);
    if (!$user || empty($user['is_super_admin'])) {
        jsonError('ይህንን ተግባር ለማከናወን የፅ/ቤት (Super Admin) ፈቃድ ያስፈልጋል', 403);
    }
    $reviewerName = $user['full_name'];

    $repStmt = $pdo->prepare("SELECT id, department_id, title, status FROM reports WHERE id = ? LIMIT 1");
    $repStmt->execute([$reportId]);
    $rep = $repStmt->fetch();
    if (!$rep) {
        jsonError('ሪፖርቱ አልተገኘም', 404);
    }
    if (!in_array($rep['status'], ['submitted', 'under_review'], true)) {
        jsonError('ይህ ሪፖርት አስቀድሞ ተገምግሟል (' . $rep['status'] . ')', 400);
    }

    $pdo->beginTransaction();
    try {
        $now = date('Y-m-d H:i:s');
        $pdo->prepare("UPDATE reports SET status = ?, office_feedback = ?, reviewed_by = ?, reviewed_at = ?, version = version + 1 WHERE id = ?")
            ->execute([$status, $comment, $reviewerName, $now, $reportId]);
        $pdo->prepare("INSERT INTO report_reviews (report_id, reviewer_name, reviewer_role, action, comment) VALUES (?, ?, ?, ?, ?)")
            ->execute([$reportId, $reviewerName, 'የፅ/ቤት ዋና ጸሐፊ', $status, $comment]);

        $notifType = ($status === 'approved') ? 'report_approved' : 'revision_requested';
        $notifTitle = ($status === 'approved') ? "ሪፖርትዎ ጸድቋል! 🕊️" : "የሪፖርት ማሻሻያ ተጠይቋል ⚠️";
        $notifMsg = "ፅ/ቤት «" . $rep['title'] . "» በሚለው ሪፖርትዎ ላይ የሚከተለውን ውሳኔ ሰጥቷል፦ " . ($comment ?: $status);
        $notifId = 'notif_' . uniqid();
        $pdo->prepare("INSERT INTO notifications (id, department_id, title, message, type, target_id) VALUES (?, ?, ?, ?, ?, ?)")
            ->execute([$notifId, $rep['department_id'], $notifTitle, $notifMsg, $notifType, $reportId]);

        $pdo->commit();
    } catch (Exception $e) {
        $pdo->rollBack();
        error_log('bot report_review error: ' . $e->getMessage());
        jsonError('ግምገማውን መመዝገብ አልተቻለም — እባክዎ እንደገና ይሞክሩ', 500);
    }

    logAudit($pdo, 'review_report_telegram', 'reports', $reportId, (int)$user['id'], 'admin', ['action' => $status]);
    jsonResponse([
        'report_id' => $reportId,
        'status' => $status,
        'title' => $rep['title'],
        'department_name' => $rep['department_id'],
    ]);
}

jsonError('ያልታወቀ ተግባር', 400);
