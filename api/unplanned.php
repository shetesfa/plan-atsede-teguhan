<?php
// ============================================================
// የዐጸደ ትጉሃን ያልታቀዱ ግን የተከናወኑ ስራዎች ኤፒአይ (Unplanned Activities API)
// 2026-11-26: unplanned works used to live ONLY in the phone's memory
// (MainNavigationScreen held a plain List, nothing ever saved it) — an
// app restart wiped every unplanned work, and the office could never see
// other departments' works. They now live in unplanned_activities.
// Evidence photos are stored as bytes (evidence_data) — the Render
// container filesystem is not writable, so nothing is ever gated on a
// disk write (same lesson as migration 10 / reports.php).
// ============================================================

require_once __DIR__ . '/config.php';

$auth = requireAuth();
$method = $_SERVER['REQUEST_METHOD'];

// Columns returned to the app: metadata only — the evidence bytes are
// NEVER inlined in list/detail responses (download via files.php?id=...).
$unplannedCols = "id, department_id, department_name, title, description, execution_date, budget_used, evidence_path, (evidence_data IS NOT NULL) AS has_evidence, status, secretariat_note, submitted_by_user_id, created_at, updated_at";

function fetchUnplannedRow(PDO $pdo, string $id, bool $forWrite = false): ?array {
    global $unplannedCols;
    // For write checks the caller also needs the evidence columns, so the
    // row is fetched with the blob only when it is about to be updated.
    $cols = $forWrite
        ? $unplannedCols . ", evidence_mime, evidence_data"
        : $unplannedCols;
    $stmt = $pdo->prepare("SELECT $cols FROM unplanned_activities WHERE id = ? AND is_deleted = 0 LIMIT 1");
    $stmt->execute([$id]);
    $row = $stmt->fetch();
    if (!$row) return null;
    $row['has_evidence'] = (bool)($row['has_evidence'] ?? false);
    return $row;
}

function unplannedPublicRow(array $row): array {
    unset($row['evidence_data']);
    $row['has_evidence'] = (bool)($row['has_evidence'] ?? false);
    return $row;
}

// Evidence validation shared by create/update: base64 bytes of a photo.
// Only JPG/PNG photos (the app picks images only), max 10MB. Returns
// [bytes, mime, name], null when no evidence was sent, or exits 400.
function unplannedEvidence(array $input): ?array {
    $b64 = $input['evidence_base64'] ?? '';
    $name = trim($input['evidence_name'] ?? '');
    if ($b64 === '' && $name === '') return null;
    if ($b64 === '' || $name === '') {
        jsonError('የማስረጃ ፎቶ መረጃው ሙሉ አይደለም (ስም እና ፋይል ሁለቱም ያስፈልጋሉ)', 400);
    }
    $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
    if (!in_array($ext, ['jpg', 'jpeg', 'png'], true)) {
        jsonError('የተከለከለ የፋይል ቅጥያ! የማስረጃ ፎቶ JPG ወይም PNG ብቻ መሆን አለበት።', 400);
    }
    if (str_contains($b64, ',')) {
        $b64 = explode(',', $b64)[1];
    }
    $bytes = base64_decode($b64, true);
    if ($bytes === false) {
        jsonError('የማስረጃ ፎቶውን ማንበብ አልተቻለም', 400);
    }
    if (strlen($bytes) > 10485760) {
        jsonError('የማስረጃ ፎቶው ከ 10MB መብለጥ የለበትም።', 400);
    }
    $mime = null;
    if (function_exists('finfo_open')) {
        $finfo = finfo_open(FILEINFO_MIME_TYPE);
        $mime = finfo_buffer($finfo, $bytes);
        finfo_close($finfo);
    }
    if (!in_array($mime, ['image/jpeg', 'image/png'], true)) {
        jsonError('የተከለከለ የፋይል ይዘት (MIME type mismatch)!', 400);
    }
    return [$bytes, $mime, $name];
}

// 1. ስራዎችን ማምጣት (GET — department-scoped; can_view_all sees all)
if ($method === 'GET') {
    $id = $_GET['id'] ?? null;
    $requestedDept = $_GET['department'] ?? null;
    $from = $_GET['from'] ?? null;
    $to = $_GET['to'] ?? null;

    if ($id) {
        $row = fetchUnplannedRow($pdo, $id);
        if (!$row) {
            jsonError('ስራው አልተገኘም', 404);
        }
        if (empty($auth['is_super_admin']) && empty($auth['can_view_all']) && $auth['department_id'] !== $row['department_id']) {
            jsonError('የሌላ ክፍልን መረጃ የማየት ፈቃድ የለዎትም (Forbidden).', 403);
        }
        jsonResponse(unplannedPublicRow($row));
    }

    $sql = "SELECT $unplannedCols FROM unplanned_activities WHERE is_deleted = 0";
    $params = [];

    // አስተዳዳሪ ወይም ቁጥጥር (can_view_all — ማየት ብቻ) ካልሆነ የራሱን ክፍል
    // ስራዎች ብቻ ነው ማየት የሚችለው — 2026-11-26
    if (empty($auth['is_super_admin']) && empty($auth['can_view_all'])) {
        if (!empty($requestedDept) && $requestedDept !== 'all' && $requestedDept !== $auth['department_id']) {
            jsonError('የተከለከለ ክንውን! የሌላ ክፍልን ስራዎች የመጠየቅ ፈቃድ የለዎትም (Forbidden).', 403);
        }
        $sql .= " AND department_id = ?";
        $params[] = $auth['department_id'];
    } elseif ($requestedDept && $requestedDept !== 'all' && $requestedDept !== 'admin') {
        $sql .= " AND department_id = ?";
        $params[] = $requestedDept;
    }

    // from/to filter by SUBMISSION date (created_at): execution_date is
    // free-form Ethiopian text, so it cannot be range-filtered.
    if ($from) {
        $sql .= " AND DATE(created_at) >= ?";
        $params[] = $from;
    }
    if ($to) {
        $sql .= " AND DATE(created_at) <= ?";
        $params[] = $to;
    }

    $sql .= " ORDER BY created_at DESC, id DESC";
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll();
    foreach ($rows as &$r) {
        $r['has_evidence'] = (bool)$r['has_evidence'];
    }
    unset($r);
    jsonResponse($rows);
}

// 2. ስራ መመዝገብ (POST)
if ($method === 'POST') {
    $input = getJsonInput();

    $title = trim($input['title'] ?? '');
    if ($title === '') {
        jsonError('የስራው ርዕስ ያስፈልጋል', 400);
    }

    // የክፍል መለያን በሰርቨር ማረጋገጥ (ፅ/ቤት ካልሆነ በስተቀር የራሱን ክፍል ብቻ ነው የሚመዘግበው!)
    if (!empty($input['department_id']) && !$auth['is_super_admin'] && $input['department_id'] !== $auth['department_id']) {
        jsonError('የተከለከለ ክንውን! በሌላ ክፍል ስም ስራ መመዝገብ አይችሉም (Forbidden)', 403);
    }
    $deptId = $auth['is_super_admin'] ? ($input['department_id'] ?? $auth['department_id']) : $auth['department_id'];

    // የክፍል ስም — የተላከ ካለ እሱን፣ ካልሆነ ከ departments ሰንጠረዥ ማግኘት
    // (ፅ/ቤት ለሌላ ክፍል ሲመዘግብ ስሙ ትክክል እንዲሆን)።
    $deptName = trim($input['department_name'] ?? '');
    if ($deptName === '') {
        $dStmt = $pdo->prepare("SELECT name FROM departments WHERE id = ? LIMIT 1");
        $dStmt->execute([$deptId]);
        $deptName = $dStmt->fetchColumn() ?: ($auth['department_name'] ?? $deptId);
    }

    $evidence = unplannedEvidence($input);

    $id = 'unplanned_' . time() . '_' . rand(100, 999);
    $stmt = $pdo->prepare("
        INSERT INTO unplanned_activities (
            id, department_id, department_name, title, description,
            execution_date, budget_used, evidence_path, evidence_mime, evidence_data,
            status, secretariat_note, submitted_by_user_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'ተመዝግቧል', '', ?)
    ");
    try {
        $stmt->execute([
            $id, $deptId, $deptName, $title,
            trim($input['description'] ?? ''),
            trim($input['execution_date'] ?? ''),
            trim($input['budget_used'] ?? ''),
            $evidence ? $evidence[2] : null,
            $evidence ? $evidence[1] : null,
            $evidence ? $evidence[0] : null,
            $auth['user_id'] ?? null,
        ]);
    } catch (\Exception $e) {
        error_log('unplanned create error: ' . $e->getMessage());
        jsonError('ስራውን መመዝገብ አልተቻለም። እባክዎ እንደገና ይሞክሩ።', 500);
    }

    logAudit($pdo, 'create_unplanned', 'unplanned_activities', $id, $auth['user_id'], $deptId, ['title' => $title]);
    $row = fetchUnplannedRow($pdo, $id);
    jsonResponse(unplannedPublicRow($row ?: ['id' => $id]), 201);
}

// 3. ስራ ማሻሻል (PUT — own department or office; only the office may
// approve it or add a secretariat note)
if ($method === 'PUT') {
    $input = getJsonInput();
    $id = $input['id'] ?? ($_GET['id'] ?? null);
    if (empty($id)) {
        jsonError('የስራ መለያ (ID) ያስፈልጋል', 400);
    }

    $row = fetchUnplannedRow($pdo, $id, true);
    if (!$row) {
        jsonError('ስራው አልተገኘም', 404);
    }

    requireDepartmentOrAdmin($auth, $row['department_id']);
    $isSuper = !empty($auth['is_super_admin']);

    $title = trim($input['title'] ?? $row['title']);
    if ($title === '') {
        jsonError('የስራው ርዕስ ያስፈልጋል', 400);
    }

    $status = $row['status'];
    if (isset($input['status'])) {
        if (!$isSuper) {
            jsonError('ስራን ማጽደቅ የሚችለው ፅ/ቤት ብቻ ነው (Forbidden).', 403);
        }
        if (!in_array($input['status'], ['ተመዝግቧል', 'በፅ/ቤት ጸድቋል'], true)) {
            jsonError('የተሳሳተ የስራ ሁኔታ', 400);
        }
        $status = $input['status'];
    }

    $note = $row['secretariat_note'];
    if (isset($input['secretariat_note'])) {
        if (!$isSuper) {
            jsonError('የፅ/ቤት ማስታወሻ መጻፍ የሚችለው ፅ/ቤት ብቻ ነው (Forbidden).', 403);
        }
        $note = trim($input['secretariat_note']);
    }

    // Evidence: a new photo replaces the old one; evidence_remove clears it;
    // otherwise the stored photo is kept untouched.
    $evidencePath = $row['evidence_path'];
    $evidenceMime = $row['evidence_mime'];
    $evidenceData = $row['evidence_data'];
    $evidence = unplannedEvidence($input);
    if ($evidence) {
        $evidenceData = $evidence[0];
        $evidenceMime = $evidence[1];
        $evidencePath = $evidence[2];
    } elseif (!empty($input['evidence_remove'])) {
        $evidencePath = null;
        $evidenceMime = null;
        $evidenceData = null;
    }

    $stmt = $pdo->prepare("
        UPDATE unplanned_activities SET
            title = ?, description = ?, execution_date = ?, budget_used = ?,
            status = ?, secretariat_note = ?,
            evidence_path = ?, evidence_mime = ?, evidence_data = ?
        WHERE id = ?
    ");
    try {
        $stmt->execute([
            $title,
            trim((string)($input['description'] ?? $row['description'] ?? '')),
            trim((string)($input['execution_date'] ?? $row['execution_date'] ?? '')),
            trim((string)($input['budget_used'] ?? $row['budget_used'] ?? '')),
            $status, $note,
            $evidencePath, $evidenceMime, $evidenceData,
            $id,
        ]);
    } catch (\Exception $e) {
        error_log('unplanned update error: ' . $e->getMessage());
        jsonError('ስራውን ማሻሻል አልተቻለም። እባክዎ እንደገና ይሞክሩ።', 500);
    }

    logAudit($pdo, 'update_unplanned', 'unplanned_activities', $id, $auth['user_id'], $row['department_id'], ['title' => $title, 'status' => $status]);
    $updated = fetchUnplannedRow($pdo, $id);
    jsonResponse(unplannedPublicRow($updated ?: $row));
}

// 4. ስራ መሰረዝ (DELETE — soft delete; super-admin, or dept_admin for
// their own department — 2026-11-26)
if ($method === 'DELETE') {
    $id = $_GET['id'] ?? (getJsonInput()['id'] ?? null);
    if (empty($id)) {
        jsonError('የስራ መለያ (ID) ያስፈልጋል', 400);
    }

    $row = fetchUnplannedRow($pdo, $id, true);
    if (!$row) {
        jsonError('ስራው አልተገኘም', 404);
    }

    $canDelete = !empty($auth['is_super_admin'])
        || (!empty($auth['is_dept_admin']) && $auth['department_id'] === $row['department_id']);
    if (!$canDelete) {
        jsonError('ይህንን ስራ ለመሰረዝ ፈቃድ የለዎትም — የራስዎ ክፍል ስራ ብቻ መሰረዝ ይችላሉ (Forbidden).', 403);
    }

    $stmt = $pdo->prepare("UPDATE unplanned_activities SET is_deleted = 1 WHERE id = ?");
    $stmt->execute([$id]);

    logAudit($pdo, 'delete_unplanned', 'unplanned_activities', $id, $auth['user_id'], $auth['department_id']);
    jsonResponse(['message' => 'ስራው በተሳካ ሁኔታ ተሰርዟል', 'id' => $id]);
}

jsonError('ያልተፈቀደ ዘዴ', 405);
