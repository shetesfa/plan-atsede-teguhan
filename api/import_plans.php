<?php
// ============================================================
// የአጸደ ትጉሃን እቅድ ማስገቢያ ኤፒአይ (Plan Import API)
// Server-to-server only: imports plan rows (e.g. from the 2019
// Excel) into the ONLINE database. The app never stores plans
// locally — this endpoint is the way Excel plans reach the
// server, and the app reads them back from plans.php.
//
// Auth: header `X-Bot-Proxy-Secret` equal to BOT_PROXY_SECRET
// (the SAME secret the scheduler endpoint uses). No user token
// is needed, so an import can run even after the admin password
// has been changed in the app.
//
// POST {"plans":[{...}], "delete_ids":["plan_22", ...]} — a row WITH
// an id is UPDATED (all fields overwritten), a row WITHOUT an id is
// INSERTED with the next plan_NNN id. delete_ids soft-deletes plans
// (is_deleted=1, same as plans.php DELETE) — used for rows that have
// no source document, e.g. the invented filler/mezmur/admin rows.
// due_date is always computed fresh via parseEthiopianDate
// (last-window rule). Returns {inserted:[ids], updated:[ids],
// deleted:[ids], count}.
// ============================================================

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/ethiopian_date.php';

date_default_timezone_set('Africa/Addis_Ababa');

$input = getJsonInput();

$expected = (string)(getenv('BOT_PROXY_SECRET') ?: '');
if ($expected === '') {
    jsonError('የማስገቢያ ምስጢር (BOT_PROXY_SECRET) በአገልጋዩ ላይ አልተዋቀረም', 503);
}
$provided = $_SERVER['HTTP_X_BOT_PROXY_SECRET'] ?? ($input['proxy_secret'] ?? '');
if (!hash_equals($expected, (string)$provided)) {
    jsonError('ያልተፈቀደ ጥያቄ (Unauthorized)', 401);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonError('POST ብቻ ይፈቀዳል', 405);
}

$plans = $input['plans'] ?? [];
$deleteIds = $input['delete_ids'] ?? [];
if (!is_array($plans)) $plans = [];
if (!is_array($deleteIds)) $deleteIds = [];
if (empty($plans) && empty($deleteIds)) {
    jsonError('የሚገቡ እቅዶች ዝርዝር አልተገኘም', 400);
}

// Next free plan_NNN id (max numeric suffix + 1).
$nextId = 1;
try {
    $rows = $pdo->query("SELECT id FROM plans")->fetchAll(PDO::FETCH_COLUMN);
    foreach ($rows as $existingId) {
        if (preg_match('/^plan_(\d+)$/', (string)$existingId, $m)) {
            $nextId = max($nextId, (int)$m[1] + 1);
        }
    }
} catch (Exception $e) {
    jsonError('የነባር እቅዶች ዝርዝር ማንበብ አልተቻለም፡ ' . $e->getMessage(), 500);
}

$inserted = [];
$updated = [];
$deleted = [];

$pdo->beginTransaction();
try {
    $deleteStmt = $pdo->prepare("UPDATE plans SET is_deleted = 1, version = version + 1 WHERE id = ?");
    foreach ($deleteIds as $delId) {
        $deleteStmt->execute([(string)$delId]);
        if ($deleteStmt->rowCount() > 0) {
            $deleted[] = (string)$delId;
        }
    }

    $stmt = $pdo->prepare("
        INSERT INTO plans (
            id, department_id, sub_department, main_task, detail_task,
            measurement, quantity, execution_time, target_date, budget,
            remarks, months_json, progress_percent, status, priority,
            assigned_to, sync_id, version, is_deleted, due_date
        ) VALUES (
            ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?,
            ?, ?, ?, 0, ?
        ) ON DUPLICATE KEY UPDATE
            sub_department = VALUES(sub_department),
            main_task = VALUES(main_task),
            detail_task = VALUES(detail_task),
            measurement = VALUES(measurement),
            quantity = VALUES(quantity),
            execution_time = VALUES(execution_time),
            target_date = VALUES(target_date),
            budget = VALUES(budget),
            remarks = VALUES(remarks),
            months_json = VALUES(months_json),
            progress_percent = VALUES(progress_percent),
            status = VALUES(status),
            priority = VALUES(priority),
            assigned_to = VALUES(assigned_to),
            due_date = VALUES(due_date),
            version = version + 1
    ");

    foreach ($plans as $item) {
        if (empty($item['department_id'])) continue;
        $isNew = empty($item['id']);
        $id = $isNew ? ('plan_' . $nextId++) : (string)$item['id'];
        $monthsJson = isset($item['months'])
            ? json_encode($item['months'], JSON_UNESCAPED_UNICODE)
            : ($item['months_json'] ?? null);
        $executionTime = $item['execution_time'] ?? null;
        $stmt->execute([
            $id,
            $item['department_id'],
            $item['sub_department'] ?? null,
            $item['main_task'] ?? ($item['title'] ?? 'እቅድ'),
            $item['detail_task'] ?? ($item['description'] ?? ''),
            $item['measurement'] ?? null,
            $item['quantity'] ?? null,
            $executionTime,
            $item['target_date'] ?? null,
            $item['budget'] ?? null,
            $item['remarks'] ?? null,
            $monthsJson,
            (int)($item['progress_percent'] ?? 0),
            $item['status'] ?? 'in_progress',
            $item['priority'] ?? 'medium',
            $item['assigned_to'] ?? null,
            $item['sync_id'] ?? ('sync_' . uniqid()),
            (int)($item['version'] ?? 1),
            parseEthiopianDate($executionTime),
        ]);
        if ($isNew) {
            $inserted[] = $id;
        } else {
            $updated[] = $id;
        }
    }
    $pdo->commit();
    logAudit($pdo, 'import_plans', 'plans', null, null, null, [
        'inserted' => $inserted,
        'updated' => $updated,
        'deleted' => $deleted,
    ]);
    jsonResponse([
        'message' => count($inserted) . ' አዲስ እቅዶች ገብተዋል፣ ' . count($updated) . ' እቅዶች ተስተካክለዋል፣ ' . count($deleted) . ' እቅዶች ተሰርዘዋል',
        'inserted' => $inserted,
        'updated' => $updated,
        'deleted' => $deleted,
        'count' => count($inserted) + count($updated),
    ]);
} catch (Exception $e) {
    $pdo->rollBack();
    jsonError('እቅዶችን ማስገባት አልተቻለም፡ ' . $e->getMessage(), 500);
}
