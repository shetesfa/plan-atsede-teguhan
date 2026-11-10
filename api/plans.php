<?php
// ============================================================
// የአጸደ ትጉሃን የእቅዶች አስተዳደር ኤፒአይ (Hardened Plans API)
// ============================================================

require_once __DIR__ . '/config.php';

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
            SELECT p.*, d.name AS department_name, d.short_name AS department_short_name 
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

        // የክፍል ፈቃድ ማረጋገጫ (አስተዳዳሪ ካልሆነ የሌላ ክፍልን የግል እቅድ ማየት አይችልም)
        requireDepartmentOrAdmin($auth, $plan['department_id']);
        jsonResponse($plan);
    }

    $sql = "
        SELECT p.*, d.name AS department_name, d.short_name AS department_short_name 
        FROM plans p 
        JOIN departments d ON p.department_id = d.id 
        WHERE (p.is_deleted = 0 OR p.is_deleted IS NULL)
    ";
    $params = [];

    // አስተዳዳሪ ካልሆነ የራሱን ክፍል እቅዶች ብቻ ነው ማየት የሚችለው
    if (!$auth['is_super_admin']) {
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
                    assigned_to, sync_id, version, is_deleted
                ) VALUES (
                    ?, ?, ?, ?, ?,
                    ?, ?, ?, ?, ?,
                    ?, ?, ?, ?, ?,
                    ?, ?, ?, 0
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
                    (int)($item['version'] ?? 1)
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
    $monthsJson = isset($input['months']) ? json_encode($input['months'], JSON_UNESCAPED_UNICODE) : ($input['months_json'] ?? null);
    $progress = (int)($input['progress_percent'] ?? 0);
    $status = $input['status'] ?? ($progress >= 100 ? 'completed' : 'in_progress');
    $priority = $input['priority'] ?? 'medium';
    $assignedTo = $input['assigned_to'] ?? null;
    $syncId = $input['sync_id'] ?? ('sync_' . uniqid());

    if (empty($mainTask)) {
        jsonError('የዕቅዱ ዋና ተግባር ወይም ርዕስ ያስፈልጋል', 400);
    }

    // ያለውን እቅድ ማረጋገጥ
    $checkStmt = $pdo->prepare("SELECT department_id FROM plans WHERE id = ?");
    $checkStmt->execute([$id]);
    $existing = $checkStmt->fetch();

    if ($existing) {
        // የሌላ ክፍልን እቅድ እንዳያሻሽል ማረጋገጥ
        requireDepartmentOrAdmin($auth, $existing['department_id']);

        $updateStmt = $pdo->prepare("
            UPDATE plans SET
                department_id = ?, sub_department = ?, main_task = ?, detail_task = ?,
                measurement = ?, quantity = ?, execution_time = ?, target_date = ?,
                budget = ?, remarks = ?, months_json = ?, progress_percent = ?,
                status = ?, priority = ?, assigned_to = ?, sync_id = ?, version = version + 1
            WHERE id = ?
        ");
        $updateStmt->execute([
            $deptId, $subDept, $mainTask, $detailTask,
            $measurement, $quantity, $executionTime, $targetDate,
            $budget, $remarks, $monthsJson, $progress,
            $status, $priority, $assignedTo, $syncId,
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
                assigned_to, sync_id, is_deleted
            ) VALUES (
                ?, ?, ?, ?, ?,
                ?, ?, ?, ?, ?,
                ?, ?, ?, ?, ?,
                ?, ?, 0
            )
        ");
        $insertStmt->execute([
            $id, $deptId, $subDept, $mainTask, $detailTask,
            $measurement, $quantity, $executionTime, $targetDate, $budget,
            $remarks, $monthsJson, $progress, $status, $priority,
            $assignedTo, $syncId
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
    $checkStmt = $pdo->prepare("SELECT department_id FROM plans WHERE id = ?");
    $checkStmt->execute([$id]);
    $existing = $checkStmt->fetch();

    if (!$existing) {
        jsonError('እቅዱ አልተገኘም', 404);
    }

    requireDepartmentOrAdmin($auth, $existing['department_id']);

    $progress = isset($input['progress_percent']) ? (int)$input['progress_percent'] : null;
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

// 4. እቅድ መሰረዝ (DELETE Plan — ፅ/ቤት ብቻ ነው መሰረዝ የሚችለው!)
if ($method === 'DELETE') {
    requireSuperAdmin($auth);
    $id = $_GET['id'] ?? (getJsonInput()['id'] ?? null);

    if (empty($id)) {
        jsonError('የዕቅድ መለያ (ID) ያስፈልጋል', 400);
    }

    $stmt = $pdo->prepare("UPDATE plans SET is_deleted = 1, version = version + 1 WHERE id = ?");
    $stmt->execute([$id]);

    logAudit($pdo, 'delete_plan', 'plans', $id, $auth['user_id'], $auth['department_id']);
    jsonResponse(['message' => 'ዕቅዱ በተሳካ ሁኔታ ተሰርዟል', 'id' => $id]);
}

jsonError('ያልተፈቀደ ዘዴ', 405);
