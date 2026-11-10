<?php
// ============================================================
// የአጸደ ትጉሃን የሪፖርት እና የፅ/ቤት የስራ ፍሰት ኤፒአይ (Reports & Office Workflow API)
// ሪፖርት ማቅረብ፣ መገምገም፣ ማጽደቅ፣ ማሻሻያ መጠየቅ፣ ፋይል ማያያዝ እና የታሪክ መዝገብ
// ============================================================

require_once __DIR__ . '/config.php';

$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';

// 1. ሪፖርቶችን ማምጣት (GET Reports)
if ($method === 'GET') {
    // የአንድን ሪፖርት ታሪክ ማምጣት (Audit Trail)
    if ($action === 'history') {
        $reportId = $_GET['report_id'] ?? '';
        if (empty($reportId)) {
            jsonError('የሪፖርት መለያ (report_id) ያስፈልጋል', 400);
        }
        $stmt = $pdo->prepare("SELECT * FROM report_reviews WHERE report_id = ? ORDER BY created_at ASC");
        $stmt->execute([$reportId]);
        jsonResponse($stmt->fetchAll());
    }

    $id = $_GET['id'] ?? null;
    $dept = $_GET['dept'] ?? null;
    $planId = $_GET['plan_id'] ?? null;
    $status = $_GET['status'] ?? null;

    // ነጠላ ሪፖርት በ ID
    if ($id) {
        $stmt = $pdo->prepare("
            SELECT r.*, d.name AS department_name, d.short_name AS department_short_name, p.main_task AS plan_title
            FROM reports r
            JOIN departments d ON r.department_id = d.id
            LEFT JOIN plans p ON r.plan_id = p.id
            WHERE r.id = ? AND r.is_deleted = 0
            LIMIT 1
        ");
        $stmt->execute([$id]);
        $report = $stmt->fetch();
        if (!$report) {
            jsonError('ሪፖርቱ አልተገኘም', 404);
        }

        // አባሪዎችን ማምጣት
        $attStmt = $pdo->prepare("SELECT * FROM report_attachments WHERE report_id = ?");
        $attStmt->execute([$id]);
        $report['attachments'] = $attStmt->fetchAll();

        jsonResponse($report);
    }

    // የሪፖርቶች ዝርዝር
    $sql = "
        SELECT r.*, d.name AS department_name, d.short_name AS department_short_name, p.main_task AS plan_title
        FROM reports r
        JOIN departments d ON r.department_id = d.id
        LEFT JOIN plans p ON r.plan_id = p.id
        WHERE r.is_deleted = 0
    ";
    $params = [];

    if ($dept && $dept !== 'all' && $dept !== 'admin') {
        $sql .= " AND r.department_id = ?";
        $params[] = $dept;
    }

    if ($planId) {
        $sql .= " AND r.plan_id = ?";
        $params[] = $planId;
    }

    if ($status && $status !== 'all') {
        $sql .= " AND r.status = ?";
        $params[] = $status;
    }

    $sql .= " ORDER BY r.created_at DESC";
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $reports = $stmt->fetchAll();

    // ለእያንዳንዱ ሪፖርት አባሪዎችን ማካተት
    foreach ($reports as &$rep) {
        $attStmt = $pdo->prepare("SELECT id, file_name, file_path, file_type, file_size FROM report_attachments WHERE report_id = ?");
        $attStmt->execute([$rep['id']]);
        $rep['attachments'] = $attStmt->fetchAll();
    }

    jsonResponse($reports);
}

// 2. ሪፖርት ማቅረብ ወይም ረቂቅ መመዝገብ (POST Report)
if ($method === 'POST' && $action !== 'review') {
    $auth = authenticateRequest();
    
    // ከ JSON ወይም ከ FormData ማንበብ
    $isMultipart = !empty($_FILES);
    $input = $isMultipart ? $_POST : getJsonInput();

    $reportId = $input['id'] ?? ('rep_' . time() . '_' . rand(100, 999));
    $planId = !empty($input['plan_id']) ? $input['plan_id'] : null;
    $deptId = $input['department_id'] ?? ($auth['department_id'] ?? 'education');
    $submittedBy = $input['submitted_by'] ?? ($auth['username'] ?? 'ኃላፊ');
    $title = trim($input['title'] ?? '');
    $activities = trim($input['activities_completed'] ?? ($input['description'] ?? ''));
    $progress = (int)($input['progress_percent'] ?? 0);
    $challenges = $input['challenges'] ?? null;
    $solutions = $input['solutions_proposed'] ?? null;
    $budgetSpent = !empty($input['budget_spent']) ? (float)$input['budget_spent'] : 0.00;
    $status = $input['status'] ?? 'submitted'; // 'draft' or 'submitted'
    $syncId = $input['sync_id'] ?? ('sync_' . uniqid());

    if (empty($title)) {
        // የዕቅዱን ርዕስ እንደ ነባሪ መውሰድ
        if ($planId) {
            $pStmt = $pdo->prepare("SELECT main_task FROM plans WHERE id = ?");
            $pStmt->execute([$planId]);
            $title = $pStmt->fetchColumn() ?: 'የክንውን ሪፖርት';
        } else {
            $title = 'የክንውን ሪፖርት';
        }
    }

    if (empty($activities)) {
        jsonError('የተከናወኑ ተግባራት ዝርዝር ማብራሪያ ያስፈልጋል', 400);
    }

    $pdo->beginTransaction();
    try {
        // ሪፖርቱን መመዝገብ
        $stmt = $pdo->prepare("
            INSERT INTO reports (
                id, plan_id, department_id, submitted_by, title, activities_completed,
                progress_percent, challenges, solutions_proposed, budget_spent, status,
                sync_id, is_deleted
            ) VALUES (
                ?, ?, ?, ?, ?, ?,
                ?, ?, ?, ?, ?,
                ?, 0
            ) ON DUPLICATE KEY UPDATE
                title = VALUES(title),
                activities_completed = VALUES(activities_completed),
                progress_percent = VALUES(progress_percent),
                challenges = VALUES(challenges),
                solutions_proposed = VALUES(solutions_proposed),
                budget_spent = VALUES(budget_spent),
                status = VALUES(status),
                version = version + 1
        ");
        $stmt->execute([
            $reportId, $planId, $deptId, $submittedBy, $title, $activities,
            $progress, $challenges, $solutions, $budgetSpent, $status,
            $syncId
        ]);

        // እቅድ ካለ የእቅዱን progress እና ሁኔታ ማዘመን
        if ($planId) {
            $planStatus = ($progress >= 100) ? 'completed' : 'in_progress';
            $pUpdate = $pdo->prepare("UPDATE plans SET progress_percent = ?, status = ?, version = version + 1 WHERE id = ?");
            $pUpdate->execute([$progress, $planStatus, $planId]);
        }

        // ፋይሎች ከተሰቀሉ ማስተናገድ
        $uploadDir = __DIR__ . '/uploads/';
        if (!is_dir($uploadDir)) {
            mkdir($uploadDir, 0755, true);
        }

        // 1. ከ multipart $_FILES
        if (!empty($_FILES['attachment'])) {
            $file = $_FILES['attachment'];
            if ($file['error'] === UPLOAD_ERR_OK) {
                $ext = pathinfo($file['name'], PATHINFO_EXTENSION);
                $safeName = 'att_' . time() . '_' . rand(1000, 9999) . '.' . $ext;
                $targetPath = $uploadDir . $safeName;
                if (move_uploaded_file($file['tmp_name'], $targetPath)) {
                    $attId = 'att_' . uniqid();
                    $relPath = 'api/uploads/' . $safeName;
                    $attStmt = $pdo->prepare("INSERT INTO report_attachments (id, report_id, file_name, file_path, file_type, file_size) VALUES (?, ?, ?, ?, ?, ?)");
                    $attStmt->execute([$attId, $reportId, $file['name'], $relPath, $file['type'], $file['size']]);
                }
            }
        }

        // 2. ከ Base64 በ JSON ከተላከ
        if (!empty($input['attachment_base64']) && !empty($input['attachment_name'])) {
            $base64Data = $input['attachment_base64'];
            if (str_contains($base64Data, ',')) {
                $base64Data = explode(',', $base64Data)[1];
            }
            $fileData = base64_decode($base64Data);
            if ($fileData !== false) {
                $origName = $input['attachment_name'];
                $ext = pathinfo($origName, PATHINFO_EXTENSION) ?: 'jpg';
                $safeName = 'att_' . time() . '_' . rand(1000, 9999) . '.' . $ext;
                $targetPath = $uploadDir . $safeName;
                if (file_put_contents($targetPath, $fileData)) {
                    $attId = 'att_' . uniqid();
                    $relPath = 'api/uploads/' . $safeName;
                    $attStmt = $pdo->prepare("INSERT INTO report_attachments (id, report_id, file_name, file_path, file_type, file_size) VALUES (?, ?, ?, ?, ?, ?)");
                    $attStmt->execute([$attId, $reportId, $origName, $relPath, 'application/octet-stream', strlen($fileData)]);
                }
            }
        }

        // የታሪክ መዝገብ (Review History)
        $revStmt = $pdo->prepare("INSERT INTO report_reviews (report_id, reviewer_name, reviewer_role, action, comment) VALUES (?, ?, ?, 'submitted', ?)");
        $revStmt->execute([$reportId, $submittedBy, 'የክፍል ኃላፊ', 'ሪፖርቱ ለፅ/ቤት ገብቷል']);

        // ለፅ/ቤት ማሳወቂያ መላክ
        if ($status === 'submitted') {
            $notifId = 'notif_' . uniqid();
            $notifStmt = $pdo->prepare("INSERT INTO notifications (id, department_id, title, message, type, target_id) VALUES (?, 'admin', ?, ?, 'report_submitted', ?)");
            $notifStmt->execute([$notifId, "አዲስ ሪፖርት ገብቷል፦ $title", "ከ$submittedBy ($deptId) አዲስ ክንውን ሪፖርት ለግምገማ ቀርቧል።", $reportId]);
        }

        $pdo->commit();
        logAudit($pdo, 'submit_report', 'reports', $reportId, $auth['user_id'] ?? null, $deptId, ['title' => $title, 'status' => $status]);

        jsonResponse([
            'message' => ($status === 'draft') ? 'ሪፖርቱ በረቂቅነት ተቀምጧል' : 'ሪፖርቱ በተሳካ ሁኔታ ለፅ/ቤት ገብቷል!',
            'id' => $reportId,
            'status' => $status
        ]);
    } catch (\Exception $e) {
        $pdo->rollBack();
        jsonError('ሪፖርቱን ማስገባት አልተቻለም፡ ' . $e->getMessage(), 500);
    }
}

// 3. የፅ/ቤት ግምገማ (Review: Approve, Request Revision, Reject)
if ($method === 'POST' && $action === 'review') {
    $auth = authenticateRequest();
    $input = getJsonInput();

    $reportId = $input['report_id'] ?? '';
    $reviewAction = $input['action'] ?? ''; // 'approved', 'revision_requested', 'rejected', 'under_review'
    $comment = trim($input['comment'] ?? ($input['feedback'] ?? ''));
    $reviewerName = $input['reviewer_name'] ?? ($auth['username'] ?? 'ዲ/ን ቴዎድሮስ (ፅ/ቤት)');
    $reviewerRole = 'የፅ/ቤት ዋና ጸሐፊ';

    if (empty($reportId) || empty($reviewAction)) {
        jsonError('የሪፖርት መለያ (report_id) እና የግምገማ ውሳኔ (action) ያስፈልጋል', 400);
    }

    $validActions = ['approved', 'revision_requested', 'rejected', 'under_review'];
    if (!in_array($reviewAction, $validActions)) {
        jsonError('ትክክለኛ ያልሆነ የግምገማ ውሳኔ', 400);
    }

    $pdo->beginTransaction();
    try {
        // ሪፖርቱን ማዘመን
        $now = date('Y-m-d H:i:s');
        $stmt = $pdo->prepare("
            UPDATE reports SET
                status = ?, office_feedback = ?, reviewed_by = ?, reviewed_at = ?, version = version + 1
            WHERE id = ?
        ");
        $stmt->execute([$reviewAction, $comment, $reviewerName, $now, $reportId]);

        // በግምገማ ታሪክ ውስጥ መመዝገብ
        $revStmt = $pdo->prepare("INSERT INTO report_reviews (report_id, reviewer_name, reviewer_role, action, comment) VALUES (?, ?, ?, ?, ?)");
        $revStmt->execute([$reportId, $reviewerName, $reviewerRole, $reviewAction, $comment]);

        // የሪፖርቱን ባለቤት ክፍል ማግኘት
        $repStmt = $pdo->prepare("SELECT department_id, title FROM reports WHERE id = ?");
        $repStmt->execute([$reportId]);
        $repInfo = $repStmt->fetch();

        if ($repInfo) {
            $targetDept = $repInfo['department_id'];
            $repTitle = $repInfo['title'];

            $notifType = ($reviewAction === 'approved') ? 'report_approved' : 'revision_requested';
            $notifTitle = ($reviewAction === 'approved') ? "ሪፖርትዎ ጸድቋል! 🕊️" : "የሪፖርት ማሻሻያ ተጠይቋል ⚠️";
            $notifMsg = "ፅ/ቤት «$repTitle» በሚለው ሪፖርትዎ ላይ የሚከተለውን ውሳኔ ሰጥቷል፦ " . ($comment ?: $reviewAction);

            $notifId = 'notif_' . uniqid();
            $notifStmt = $pdo->prepare("INSERT INTO notifications (id, department_id, title, message, type, target_id) VALUES (?, ?, ?, ?, ?, ?)");
            $notifStmt->execute([$notifId, $targetDept, $notifTitle, $notifMsg, $notifType, $reportId]);
        }

        $pdo->commit();
        logAudit($pdo, 'review_report', 'reports', $reportId, $auth['user_id'] ?? null, 'admin', [
            'action' => $reviewAction,
            'comment' => $comment
        ]);

        jsonResponse([
            'message' => "የሪፖርቱ ግምገማ በተሳካ ሁኔታ ተመዝግቧል ($reviewAction)",
            'report_id' => $reportId,
            'status' => $reviewAction
        ]);
    } catch (\Exception $e) {
        $pdo->rollBack();
        jsonError('ግምገማውን መመዝገብ አልተቻለም፡ ' . $e->getMessage(), 500);
    }
}

jsonError('ያልተፈቀደ ጥያቄ ወይም ዘዴ', 405);
