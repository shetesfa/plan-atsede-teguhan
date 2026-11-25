<?php
// ============================================================
// የአጸደ ትጉሃን ማሳሰቢያ መርሐግብር ኤፒአይ (Reminder Scheduler API)
// Server-to-server only: the Telegram bot calls this endpoint
// to learn which plans are due soon or overdue without a report,
// then sends the Telegram reminders. It is NOT a user endpoint.
// Audit fix 2026-11-25: before this, nothing reminded anyone
// and nothing told the office when a report was late.
//
// Auth: header `X-Bot-Proxy-Secret` (or `proxy_secret` field)
// equal to the BOT_PROXY_SECRET env var — the SAME secret the
// bot service holds in Render. Set it on THIS service too.
// ============================================================

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/ethiopian_date.php';

date_default_timezone_set('Africa/Addis_Ababa');

$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? 'due';

function schedulerSecret(): string {
    return (string)(getenv('BOT_PROXY_SECRET') ?: '');
}

function requireSchedulerAuth(): void {
    $expected = schedulerSecret();
    if ($expected === '') {
        jsonError('የመርሐግብር ምስጢር (BOT_PROXY_SECRET) በአገልጋዩ ላይ አልተዋቀረም', 503);
    }
    $provided = $_SERVER['HTTP_X_BOT_PROXY_SECRET'] ?? '';
    if ($provided === '') {
        $body = getJsonInput();
        $provided = $body['proxy_secret'] ?? ($_POST['proxy_secret'] ?? '');
    }
    if (!hash_equals($expected, (string)$provided)) {
        jsonError('ያልተፈቀደ ጥያቄ (Unauthorized)', 401);
    }
}

requireSchedulerAuth();

$today = new DateTimeImmutable('today', new DateTimeZone('Africa/Addis_Ababa'));
$todayStr = $today->format('Y-m-d');
$tomorrowStr = $today->modify('+1 day')->format('Y-m-d');

// A plan counts as "reported" when a live report exists in one of
// these states — a draft or a rejected report does not count.
$reportedStates = "'submitted','under_review','approved'";

// 1. Due-soon + overdue plans (GET ?action=due)
if ($method === 'GET' && $action === 'due') {
    $stmt = $pdo->prepare("
        SELECT p.id, p.department_id, d.name AS department_name,
               p.main_task, p.detail_task, p.execution_time, p.due_date,
               p.progress_percent, p.status, p.is_postponed, p.postponed_date,
               (SELECT r.status FROM reports r WHERE r.plan_id = p.id AND r.is_deleted = 0
                ORDER BY r.created_at DESC, r.updated_at DESC LIMIT 1) AS latest_report_status
        FROM plans p
        JOIN departments d ON p.department_id = d.id
        WHERE (p.is_deleted = 0 OR p.is_deleted IS NULL)
          AND p.progress_percent < 100
          AND (p.status IS NULL OR p.status NOT IN ('completed', 'cancelled'))
        ORDER BY p.due_date ASC, p.id ASC
    ");
    $stmt->execute();
    $plans = $stmt->fetchAll();

    // Plans already reminded / escalated today (one per plan per kind).
    $logStmt = $pdo->prepare("SELECT plan_id, kind FROM reminder_log WHERE sent_date = ?");
    $logStmt->execute([$todayStr]);
    $logged = [];
    foreach ($logStmt->fetchAll() as $row) {
        $logged[$row['plan_id'] . ':' . $row['kind']] = true;
    }

    $dueSoon = [];
    $overdue = [];
    foreach ($plans as $p) {
        // Stored due_date wins; otherwise parse the text on the fly
        // (old rows written before due_date existed).
        $due = $p['due_date'] ?: parseEthiopianDate($p['execution_time']);
        if ($due === null) continue; // no readable date — cannot remind
        $reported = in_array($p['latest_report_status'], ['submitted', 'under_review', 'approved'], true);
        if ($reported) continue;

        $item = [
            'id' => $p['id'],
            'department_id' => $p['department_id'],
            'department_name' => $p['department_name'],
            'main_task' => $p['main_task'],
            'detail_task' => $p['detail_task'],
            'execution_time' => $p['execution_time'],
            'due_date' => $due,
            'is_postponed' => (bool)$p['is_postponed'],
            'postponed_date' => $p['postponed_date'],
        ];
        if ($due < $todayStr) {
            if (empty($logged[$p['id'] . ':escalation'])) {
                $overdue[] = $item;
            }
        } elseif ($due === $todayStr || $due === $tomorrowStr) {
            if (empty($logged[$p['id'] . ':reminder'])) {
                $dueSoon[] = $item;
            }
        }
    }

    jsonResponse([
        'today' => $todayStr,
        'due_soon' => $dueSoon,
        'overdue' => $overdue,
    ]);
}

// 2. Mark reminders as sent (POST ?action=mark_sent)
// Body: {"items": [{"plan_id": "...", "kind": "reminder"|"escalation"}]}
if ($method === 'POST' && $action === 'mark_sent') {
    $input = getJsonInput();
    $items = $input['items'] ?? [];
    if (!is_array($items)) {
        jsonError('items ዝርዝር ያስፈልጋል', 400);
    }
    $ins = $pdo->prepare("
        INSERT INTO reminder_log (plan_id, kind, sent_date)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE sent_at = CURRENT_TIMESTAMP
    ");
    $marked = 0;
    foreach ($items as $it) {
        $planId = $it['plan_id'] ?? '';
        $kind = $it['kind'] ?? '';
        if ($planId === '' || !in_array($kind, ['reminder', 'escalation'], true)) continue;
        $ins->execute([$planId, $kind, $todayStr]);
        $marked++;
    }
    jsonResponse(['message' => "$marked ማሳሰቢያዎች ተመዝግበዋል", 'marked' => $marked]);
}

jsonError('ያልታወቀ ጥያቄ ወይም ዘዴ', 404);
