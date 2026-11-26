<?php
// ============================================================
// የዐጸደ ትጉሃን የእቅዶች አስተዳደር ኤፒአይ (Hardened Plans API)
// ============================================================

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/ethiopian_date.php'; // due_date parsing (audit fix 2026-11-25)

$auth = requireAuth(); // እያንዳንዱ ጥያቄ የግድ የተረጋገጠ ተጠቃሚ መሆን አለበት!
$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';

// 1. እቅዶችን ማምጣት (GET Plans)
if ($method === 'GET') {
    $requestedDept = $_GET['dept'] ?? null;
    $status = $_GET['status'] ?? null;
    $search = $_GET['search'] ?? null;
    $month = $_GET['month'] ?? null;
    $id = $_GET['id'] ?? null;

    // የተወሰነ እቅድ በ ID ማምጣት
    if ($id) {
        $stmt = $pdo->prepare("
            SELECT p.*, d.name AS department_name, d.short_name AS department_short_name,
                   (SELECT r.status FROM reports r WHERE r.plan_id = p.id AND r.is_deleted = 0 ORDER BY r.created_at DESC, r.updated_at DESC LIMIT 1) AS latest_report_status
            FROM plans p 
            JOIN departments d ON p.department_id = d.id 
            WHERE p.id = ? AND (p.is_deleted = 0 OR p.is_deleted IS NULL) 
            LIMIT 1
        ");
        $stmt->execute([$id]);
        $plan = $stmt->fetch();
        if (!$plan) {
            jsonError('እቅዱ አልተገኘም', 404);
        }

        // የክፍል ፈቃድ ማረጋገጫ (አስተዳዳሪ ወይም ቁጥጥር/can_view_all ካልሆነ
        // የሌላ ክፍልን የግል እቅድ ማየት አይችልም — 2026-11-26)
        if (empty($auth['is_super_admin']) && empty($auth['can_view_all']) && $auth['department_id'] !== $plan['department_id']) {
            jsonError('የሌላ ክፍልን መረጃ የማየት ወይም የማሻሻል ፈቃድ የለዎትም (Forbidden).', 403);
        }
        // The date is ALWAYS parsed fresh from the text: the stored
        // due_date was computed by an older parser (first-date rule)
        // and is stale for multi-window plans. Stored value is only
        // a fallback for text the parser cannot read.
        $plan['due_date'] = parseEthiopianDate($plan['execution_time']) ?: $plan['due_date'];
        $plan['due_date_ethiopian'] = formatEthiopianDate($plan['due_date']);
        jsonResponse($plan);
    }

    $sql = "
        SELECT p.*, d.name AS department_name, d.short_name AS department_short_name,
               (SELECT r.status FROM reports r WHERE r.plan_id = p.id AND r.is_deleted = 0 ORDER BY r.created_at DESC, r.updated_at DESC LIMIT 1) AS latest_report_status
        FROM plans p 
        JOIN departments d ON p.department_id = d.id 
        WHERE (p.is_deleted = 0 OR p.is_deleted IS NULL)
    ";
    $params = [];

    // አስተዳዳሪ ወይም ቁጥጥር (can_view_all — ማየት ብቻ) ካልሆነ የራሱን ክፍል
    // እቅዶች ብቻ ነው ማየት የሚችለው — 2026-11-26
    if (empty($auth['is_super_admin']) && empty($auth['can_view_all'])) {
        if (!empty($requestedDept) && $requestedDept !== 'all' && $requestedDept !== $auth['department_id']) {
            jsonError('የተከለከለ ክንውን! የሌላ ክፍልን እቅዶች የመጠየቅ ፈቃድ የለዎትም (Forbidden).', 403);
        }
        $sql .= " AND p.department_id = ?";
        $params[] = $auth['department_id'];
    } elseif ($requestedDept && $requestedDept !== 'all' && $requestedDept !== 'admin') {
        $sql .= " AND p.department_id = ?";
        $params[] = $requestedDept;
    }

    if ($status && $status !== 'all') {
        $sql .= " AND p.status = ?";
        $params[] = $status;
    }

    if ($search) {
        $sql .= " AND (p.main_task LIKE ? OR p.detail_task LIKE ? OR p.sub_department LIKE ?)";
        $searchTerm = "%$search%";
        $params[] = $searchTerm;
        $params[] = $searchTerm;
        $params[] = $searchTerm;
    }

    $sql .= " ORDER BY p.id ASC";
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $plans = $stmt->fetchAll();

    // The date is ALWAYS parsed fresh from the text (see above),
    // so the app sees the correct date for every plan.
    foreach ($plans as &$p) {
        $p['due_date'] = parseEthiopianDate($p['execution_time']) ?: $p['due_date'];
        $p['due_date_ethiopian'] = formatEthiopianDate($p['due_date']);
    }
    unset($p);

    if ($month && $month !== 'all') {
        $plans = array_values(array_filter($plans, function($p) use ($month) {
            if (empty($p['months_json'])) return false;
            $months = json_decode($p['months_json'], true);
            return is_array($months) && in_array($month, $months);
        }));
    }

    jsonResponse($plans);
}

// 2. እቅድ መፍጠር ወይም ማሻሻል (POST Plan)
if ($method === 'POST') {
    $input = getJsonInput();

    // የጅምላ ማስገቢያ (ለፅ/ቤት አስተዳዳሪ ብቻ የተፈቀደ)
    if ($action === 'bulk_sync') {
        requireSuperAdmin($auth);
        if (empty($input['plans']) || !is_array($input['plans'])) {
            jsonError('የሚገቡ እቅዶች ዝርዝር አልተገኘም', 400);
        }

        $pdo->beginTransaction();
        try {
            $insertStmt = $pdo->prepare("
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

            $importedCount = 0;
            foreach ($input['plans'] as $item) {
                if (empty($item['id']) || empty($item['department_id'])) continue;
                $monthsJson = isset($item['months']) ? json_encode($item['months'], JSON_UNESCAPED_UNICODE) : ($item['months_json'] ?? null);
                $insertStmt->execute([
                    $item['id'],
                    $item['department_id'],
                    $item['sub_department'] ?? null,
                    $item['main_task'] ?? ($item['title'] ?? 'እቅድ'),
                    $item['detail_task'] ?? ($item['description'] ?? ''),
                    $item['measurement'] ?? null,
                    $item['quantity'] ?? null,
                    $item['execution_time'] ?? null,
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
                    parseEthiopianDate($item['execution_time'] ?? null)
                ]);
                $importedCount++;
            }
            $pdo->commit();
            logAudit($pdo, 'bulk_import_plans', 'plans', null, $auth['user_id'], $auth['department_id'], ['count' => $importedCount]);
            jsonResponse(['message' => "$importedCount እቅዶች በተሳካ ሁኔታ ተጭነዋል", 'count' => $importedCount]);
        } catch (\Exception $e) {
            $pdo->rollBack();
            jsonError('የጅምላ እቅዶችን ማስገባት አልተቻለም፡ ' . $e->getMessage(), 500);
        }
    }

    // ነጠላ እቅድ መፍጠር ወይም ማሻሻል
    $id = !empty($input['id']) ? $input['id'] : ('plan_' . time() . '_' . rand(100, 999));
    
    // የክፍል መለያን በሰርቨር ማረጋገጥ (ፅ/ቤት ካልሆነ በስተቀር የራሱን ክፍል ብቻ ነው የሚመዘግበው!)
    if (!empty($input['department_id']) && !$auth['is_super_admin'] && $input['department_id'] !== $auth['department_id']) {
        jsonError('የተከለከለ ክንውን! በሌላ ክፍል ስም እቅድ መፍጠር ወይም ማሻሻል አይችሉም (Forbidden)', 403);
    }
    $deptId = $auth['is_super_admin'] ? ($input['department_id'] ?? $auth['department_id']) : $auth['department_id'];

    $subDept = $input['sub_department'] ?? null;
    $mainTask = trim($input['main_task'] ?? ($input['title'] ?? ''));
    $detailTask = trim($input['detail_task'] ?? ($input['description'] ?? ''));
    $measurement = $input['measurement'] ?? null;
    $quantity = $input['quantity'] ?? null;
    $executionTime = $input['execution_time'] ?? null;
    $targetDate = $input['target_date'] ?? null;
    $budget = $input['budget'] ?? null;
    $remarks = $input['remarks'] ?? null;
    // Audit fix 2026-11-25: postpone is now persisted server-side
    // (before, only the new date survived — the fact that the plan
    // was postponed, its original date and the reason were lost).
    $isPostponed = !empty($input['is_postponed']) ? 1 : 0;
    $postponedDate = $input['postponed_date'] ?? null;
    $postponeReason = $input['postpone_reason'] ?? null;
    $originalExecutionTime = $input['original_execution_time'] ?? null;
    // Real due date parsed from the Ethiopian execution_time text.
    $dueDate = parseEthiopianDate($executionTime);
    $monthsJson = isset($input['months']) ? json_encode($input['months'], JSON_UNESCAPED_UNICODE) : ($input['months_json'] ?? null);
    $progress = max(0, min(100, (int)($input['progress_percent'] ?? 0)));
    $status = $input['status'] ?? ($progress >= 100 ? 'completed' : 'in_progress');
    $priority = in_array($input['priority'] ?? '', ['high', 'medium', 'low'], true) ? $input['priority'] : 'medium';
    $assignedTo = $input['assigned_to'] ?? null;
    $syncId = $input['sync_id'] ?? ('sync_' . uniqid());

    if (empty($mainTask)) {
        jsonError('የዕቅዱ ዋና ተግባር ወይም ርዕስ ያስፈልጋል', 400);
    }

    // ያለውን እቅድ ማረጋገጥ
    $checkStmt = $pdo->prepare("SELECT department_id, version, execution_time, original_execution_time, is_postponed FROM plans WHERE id = ?");
    $checkStmt->execute([$id]);
    $existing = $checkStmt->fetch();

    if ($existing) {
        // የሌላ ክፍልን እቅድ እንዳያሻሽል ማረጋገጥ
        requireDepartmentOrAdmin($auth, $existing['department_id']);

        // Optimistic Concurrency ፍተሻ
        $clientVersion = isset($input['version']) ? (int)$input['version'] : null;
        if ($clientVersion !== null && (int)$existing['version'] > $clientVersion) {
            jsonError('የስሪት ግጭት ተፈጥሯል (Version Conflict)! እቅዱ በሌላ ተጠቃሚ ቀድሞ ስለተሻሻለ እባክዎ ገጹን አድሰው እንደገና ይሞክሩ።', 409);
        }

        // Postpone guard: keep the ORIGINAL date when a plan is
        // postponed for the first time and the caller did not send it.
        $postponedAt = null;
        if ($isPostponed) {
            if (empty($originalExecutionTime) && !empty($existing['execution_time']) && $existing['execution_time'] !== $executionTime) {
                $originalExecutionTime = $existing['execution_time'];
            }
            if (empty($existing['is_postponed'])) {
                $postponedAt = date('Y-m-d H:i:s');
            }
        } else {
            $postponedDate = null;
            $postponeReason = null;
            $originalExecutionTime = null;
        }

        $updateStmt = $pdo->prepare("
            UPDATE plans SET
                department_id = ?, sub_department = ?, main_task = ?, detail_task = ?,
                measurement = ?, quantity = ?, execution_time = ?, target_date = ?,
                budget = ?, remarks = ?, months_json = ?, progress_percent = ?,
                status = ?, priority = ?, assigned_to = ?, sync_id = ?, version = version + 1,
                original_execution_time = ?, postponed_date = ?, postpone_reason = ?,
                is_postponed = ?, postponed_at = COALESCE(?, postponed_at), due_date = ?
            WHERE id = ?
        ");
        $updateStmt->execute([
            $deptId, $subDept, $mainTask, $detailTask,
            $measurement, $quantity, $executionTime, $targetDate,
            $budget, $remarks, $monthsJson, $progress,
            $status, $priority, $assignedTo, $syncId,
            $originalExecutionTime, $postponedDate, $postponeReason,
            $isPostponed, $postponedAt, $dueDate,
            $id
        ]);
        $msg = 'ዕቅዱ በተሳካ ሁኔታ ተሻሽሏል';
        logAudit($pdo, 'update_plan', 'plans', $id, $auth['user_id'], $deptId, ['main_task' => $mainTask]);
    } else {
        $insertStmt = $pdo->prepare("
            INSERT INTO plans (
                id, department_id, sub_department, main_task, detail_task,
                measurement, quantity, execution_time, target_date, budget,
                remarks, months_json, progress_percent, status, priority,
                assigned_to, sync_id, is_deleted,
                original_execution_time, postponed_date, postpone_reason, is_postponed, due_date
            ) VALUES (
                ?, ?, ?, ?, ?,
                ?, ?, ?, ?, ?,
                ?, ?, ?, ?, ?,
                ?, ?, 0,
                ?, ?, ?, ?, ?
            )
        ");
        $insertStmt->execute([
            $id, $deptId, $subDept, $mainTask, $detailTask,
            $measurement, $quantity, $executionTime, $targetDate, $budget,
            $remarks, $monthsJson, $progress, $status, $priority,
            $assignedTo, $syncId,
            $originalExecutionTime, $postponedDate, $postponeReason, $isPostponed, $dueDate
        ]);
        $msg = 'አዲስ ዕቅድ በተሳካ ሁኔታ ተመዝግቧል';
        logAudit($pdo, 'create_plan', 'plans', $id, $auth['user_id'], $deptId, ['main_task' => $mainTask]);
    }

    $statusCode = $existing ? 200 : 201;
    jsonResponse(['message' => $msg, 'id' => $id, 'progress_percent' => $progress, 'status' => $status], $statusCode);
}

// 3. እቅድ ማሻሻል (PUT Progress update)
if ($method === 'PUT') {
    $input = getJsonInput();
    if (empty($input['id'])) {
        jsonError('የዕቅድ መለያ (ID) ያስፈልጋል', 400);
    }

    $id = $input['id'];
    $checkStmt = $pdo->prepare("SELECT department_id, version FROM plans WHERE id = ?");
    $checkStmt->execute([$id]);
    $existing = $checkStmt->fetch();

    if (!$existing) {
        jsonError('እቅዱ አልተገኘም', 404);
    }

    requireDepartmentOrAdmin($auth, $existing['department_id']);

    $clientVersion = isset($input['version']) ? (int)$input['version'] : null;
    if ($clientVersion !== null && (int)$existing['version'] > $clientVersion) {
        jsonError('የስሪት ግጭት ተፈጥሯል (Version Conflict)! እቅዱ በሌላ ተጠቃሚ ቀድሞ ስለተሻሻለ እባክዎ ገጹን አድሰው እንደገና ይሞክሩ።', 409);
    }

    $progress = isset($input['progress_percent']) ? max(0, min(100, (int)$input['progress_percent'])) : null;
    $status = $input['status'] ?? null;

    if ($progress !== null) {
        if ($progress >= 100 && !$status) {
            $status = 'completed';
        }
        $stmt = $pdo->prepare("UPDATE plans SET progress_percent = ?, status = COALESCE(?, status), version = version + 1 WHERE id = ?");
        $stmt->execute([$progress, $status, $id]);
    }

    logAudit($pdo, 'update_plan_progress', 'plans', $id, $auth['user_id'], $existing['department_id'], [
        'progress_percent' => $progress,
        'status' => $status
    ]);

    jsonResponse(['message' => 'የዕቅዱ ክንውን ተሻሽሏል', 'id' => $id]);
}

// 4. እቅድ መሰረዝ (DELETE Plan — ፅ/ቤት መሰረዝ ይችላል፤ dept_admin የራሱን
// ክፍል እቅድ ብቻ መሰረዝ ይችላል — 2026-11-26)
if ($method === 'DELETE') {
    $id = $_GET['id'] ?? (getJsonInput()['id'] ?? null);

    if (empty($id)) {
        jsonError('የዕቅድ መለያ (ID) ያስፈልጋል', 400);
    }

    $planStmt = $pdo->prepare("SELECT department_id FROM plans WHERE id = ? AND (is_deleted = 0 OR is_deleted IS NULL) LIMIT 1");
    $planStmt->execute([$id]);
    $planRow = $planStmt->fetch();
    if (!$planRow) {
        jsonError('ዕቅዱ አልተገኘም', 404);
    }

    $canDelete = !empty($auth['is_super_admin'])
        || (!empty($auth['is_dept_admin']) && $auth['department_id'] === $planRow['department_id']);
    if (!$canDelete) {
        jsonError('ይህንን እቅድ ለመሰረዝ ፈቃድ የለዎትም — የራስዎ ክፍል እቅድ ብቻ መሰረዝ ይችላሉ (Forbidden).', 403);
    }

    $stmt = $pdo->prepare("UPDATE plans SET is_deleted = 1, version = version + 1 WHERE id = ?");
    $stmt->execute([$id]);

    logAudit($pdo, 'delete_plan', 'plans', $id, $auth['user_id'], $auth['department_id']);
    jsonResponse(['message' => 'ዕቅዱ በተሳካ ሁኔታ ተሰርዟል', 'id' => $id]);
}

jsonError('ያልተፈቀደ ዘዴ', 405);
