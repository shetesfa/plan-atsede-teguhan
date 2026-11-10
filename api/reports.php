<?php
// ============================================================
// የአጸደ ትጉሃን የሪፖርት እና የፅ/ቤት የስራ ፍሰት ኤፒአይ (Hardened Reports Workflow API)
// ============================================================

require_once __DIR__ . '/config.php';

$auth = requireAuth(); // የግድ የተረጋገጠ ተጠቃሚ መሆን አለበት!
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

        // የሪፖርቱን ክፍል መፈተሽ
        $repCheck = $pdo->prepare("SELECT department_id FROM reports WHERE id = ?");
        $repCheck->execute([$reportId]);
        $repDept = $repCheck->fetchColumn();
        if (!$repDept) {
            jsonError('ሪፖርቱ አልተገኘም', 404);
        }
        requireDepartmentOrAdmin($auth, $repDept);

        $stmt = $pdo->prepare("SELECT * FROM report_reviews WHERE report_id = ? ORDER BY created_at ASC");
        $stmt->execute([$reportId]);
        jsonResponse($stmt->fetchAll());
    }

    $id = $_GET['id'] ?? null;
    $status = $_GET['status'] ?? null;
    $planId = $_GET['plan_id'] ?? null;

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

        requireDepartmentOrAdmin($auth, $report['department_id']);

        $attStmt = $pdo->prepare("SELECT id, file_name, file_path, file_type, file_size FROM report_attachments WHERE report_id = ?");
        $attStmt->execute([$id]);
        $report['attachments'] = $attStmt->fetchAll();

        jsonResponse($report);
    }

    $sql = "
        SELECT r.*, d.name AS department_name, d.short_name AS department_short_name, p.main_task AS plan_title
        FROM reports r
        JOIN departments d ON r.department_id = d.id
        LEFT JOIN plans p ON r.plan_id = p.id
        WHERE r.is_deleted = 0
    ";
    $params = [];

    // አስተዳዳሪ ካልሆነ የራሱን ክፍል ሪፖርቶች ብቻ ያያል
    if (!$auth['is_super_admin']) {
        $sql .= " AND r.department_id = ?";
        $params[] = $auth['department_id'];
    } else {
        $filterDept = $_GET['dept'] ?? null;
        if ($filterDept && $filterDept !== 'all' && $filterDept !== 'admin') {
            $sql .= " AND r.department_id = ?";
            $params[] = $filterDept;
        }
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

    foreach ($reports as &$rep) {
        $attStmt = $pdo->prepare("SELECT id, file_name, file_path, file_type, file_size FROM report_attachments WHERE report_id = ?");
        $attStmt->execute([$rep['id']]);
        $rep['attachments'] = $attStmt->fetchAll();
    }

    jsonResponse($reports);
}

// 2. ሪፖርት ማቅረብ (POST Report)
if ($method === 'POST' && $action !== 'review') {
    $isMultipart = !empty($_FILES);
    $input = $isMultipart ? $_POST : getJsonInput();

    $reportId = !empty($input['id']) ? $input['id'] : ('rep_' . time() . '_' . rand(100, 999));
    $planId = !empty($input['plan_id']) ? $input['plan_id'] : null;

    // ማንነት እና ክፍል ከ Token ብቻ ይወሰዳሉ (Spoofing መከላከል)
    $deptId = $auth['is_super_admin'] ? ($input['department_id'] ?? $auth['department_id']) : $auth['department_id'];
    $submittedBy = $auth['full_name'] ?? $auth['username'];

    $title = trim($input['title'] ?? '');
    $activities = trim($input['activities_completed'] ?? ($input['summary'] ?? ($input['description'] ?? '')));
    $progress = (int)($input['progress_percent'] ?? 0);
    $challenges = $input['challenges'] ?? null;
    $solutions = $input['solutions_proposed'] ?? null;
    $budgetSpent = !empty($input['budget_spent']) ? (float)$input['budget_spent'] : 0.00;
    $status = in_array($input['status'] ?? '', ['draft', 'submitted'], true) ? $input['status'] : 'submitted';
    $syncId = $input['sync_id'] ?? ('sync_' . uniqid());

    if ($planId) {
        $pStmt = $pdo->prepare("SELECT department_id, main_task FROM plans WHERE id = ?");
        $pStmt->execute([$planId]);
        $plan = $pStmt->fetch();
        if ($plan) {
            requireDepartmentOrAdmin($auth, $plan['department_id']);
            if (empty($title)) {
                $title = $plan['main_task'] . ' - ክንውን ሪፖርት';
            }
        }
    }

    if (empty($title)) {
        $title = 'የክንውን ሪፖርት';
    }

    if (empty($activities)) {
        jsonError('የተከናወኑ ተግባራት ዝርዝር ማብራሪያ ያስፈልጋል', 400);
    }

    $pdo->beginTransaction();
    try {
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

        if ($planId) {
            $planStatus = ($progress >= 100) ? 'completed' : 'in_progress';
            $pUpdate = $pdo->prepare("UPDATE plans SET progress_percent = ?, status = ?, version = version + 1 WHERE id = ?");
            $pUpdate->execute([$progress, $planStatus, $planId]);
        }

        // ደህንነቱ የተጠበቀ የፋይል ሰቀላ ማስተናገድ (Secure Attachment Upload)
        $uploadDir = __DIR__ . '/uploads/';
        if (!is_dir($uploadDir)) {
            mkdir($uploadDir, 0755, true);
        }

        $allowedExtensions = ['jpg', 'jpeg', 'png', 'pdf', 'docx', 'xlsx'];
        $allowedMimeTypes = [
            'image/jpeg', 'image/png', 'application/pdf',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        ];

        // 1. Multipart ሰቀላ
        if (!empty($_FILES['attachment'])) {
            $file = $_FILES['attachment'];
            if ($file['error'] === UPLOAD_ERR_OK) {
                $ext = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
                $finfo = finfo_open(FILEINFO_MIME_TYPE);
                $mime = finfo_file($finfo, $file['tmp_name']);
                finfo_close($finfo);

                if (!in_array($ext, $allowedExtensions, true) || !in_array($mime, $allowedMimeTypes, true)) {
                    $pdo->rollBack();
                    jsonError('የተከለከለ የፋይል አይነት! የተፈቀዱት፦ JPG, PNG, PDF, DOCX, XLSX ብቻ ናቸው።', 400);
                }

                if ($file['size'] > 20971520) {
                    $pdo->rollBack();
                    jsonError('የፋይል መጠኑ ከ 20MB መብለጥ የለበትም።', 400);
                }

                $safeName = 'att_' . hash('sha256', uniqid() . microtime()) . '.' . $ext;
                $targetPath = $uploadDir . $safeName;
                if (move_uploaded_file($file['tmp_name'], $targetPath)) {
                    $attId = 'att_' . uniqid();
                    $relPath = 'api/uploads/' . $safeName;
                    $attStmt = $pdo->prepare("INSERT INTO report_attachments (id, report_id, file_name, file_path, file_type, file_size) VALUES (?, ?, ?, ?, ?, ?)");
                    $attStmt->execute([$attId, $reportId, htmlspecialchars($file['name'], ENT_QUOTES, 'UTF-8'), $relPath, $mime, $file['size']]);
                }
            }
        }

        // 2. Base64 ሰቀላ
        if (!empty($input['attachment_base64']) && !empty($input['attachment_name'])) {
            $origName = $input['attachment_name'];
            $ext = strtolower(pathinfo($origName, PATHINFO_EXTENSION));

            if (!in_array($ext, $allowedExtensions, true)) {
                $pdo->rollBack();
                jsonError('የተከለከለ የፋይል ቅጥያ! የተፈቀዱት፦ JPG, PNG, PDF, DOCX, XLSX ብቻ ናቸው።', 400);
            }

            $base64Data = $input['attachment_base64'];
            if (str_contains($base64Data, ',')) {
                $base64Data = explode(',', $base64Data)[1];
            }
            $fileData = base64_decode($base64Data);

            if ($fileData !== false) {
                if (strlen($fileData) > 20971520) {
                    $pdo->rollBack();
                    jsonError('የፋይል መጠኑ ከ 20MB መብለጥ የለበትም።', 400);
                }

                $finfo = finfo_open(FILEINFO_MIME_TYPE);
                $mime = finfo_buffer($finfo, $fileData);
                finfo_close($finfo);

                if (!in_array($mime, $allowedMimeTypes, true)) {
                    $pdo->rollBack();
                    jsonError('የተከለከለ የፋይል ይዘት (MIME type mismatch)!', 400);
                }

                $safeName = 'att_' . hash('sha256', uniqid() . microtime()) . '.' . $ext;
                $targetPath = $uploadDir . $safeName;
                if (file_put_contents($targetPath, $fileData)) {
                    $attId = 'att_' . uniqid();
                    $relPath = 'api/uploads/' . $safeName;
                    $attStmt = $pdo->prepare("INSERT INTO report_attachments (id, report_id, file_name, file_path, file_type, file_size) VALUES (?, ?, ?, ?, ?, ?)");
                    $attStmt->execute([$attId, $reportId, htmlspecialchars($origName, ENT_QUOTES, 'UTF-8'), $relPath, $mime, strlen($fileData)]);
                }
            }
        }

        $revStmt = $pdo->prepare("INSERT INTO report_reviews (report_id, reviewer_name, reviewer_role, action, comment) VALUES (?, ?, ?, 'submitted', ?)");
        $revStmt->execute([$reportId, $submittedBy, $auth['role_title'] ?? 'የክፍል ኃላፊ', 'ሪፖርቱ ለፅ/ቤት ገብቷል']);

        if ($status === 'submitted') {
            $notifId = 'notif_' . uniqid();
            $notifStmt = $pdo->prepare("INSERT INTO notifications (id, department_id, title, message, type, target_id) VALUES (?, 'admin', ?, ?, 'report_submitted', ?)");
            $notifStmt->execute([$notifId, "አዲስ ሪፖርት ገብቷል፦ $title", "ከ$submittedBy ($deptId) አዲስ ክንውን ሪፖርት ለግምገማ ቀርቧል።", $reportId]);
        }

        $pdo->commit();
        logAudit($pdo, 'submit_report', 'reports', $reportId, $auth['user_id'], $deptId, ['title' => $title, 'status' => $status]);

        jsonResponse([
            'message' => ($status === 'draft') ? 'ሪፖርቱ በረቂቅነት ተቀምጧል' : 'ሪፖርቱ በተሳካ ሁኔታ ለፅ/ቤት ገብቷል!',
            'id' => $reportId,
            'status' => $status
        ], 201);
    } catch (\Exception $e) {
        $pdo->rollBack();
        jsonError('ሪፖርቱን ማስገባት አልተቻለም፡ ' . $e->getMessage(), 500);
    }
}

// 3. የፅ/ቤት ግምገማ (Review: Approve, Revision, Reject — ፅ/ቤት ብቻ!)
if ($method === 'POST' && $action === 'review') {
    requireSuperAdmin($auth); // ፅ/ቤት ካልሆነ በስተቀር ማንም መገምገም አይችልም!

    $input = getJsonInput();
    $reportId = $input['report_id'] ?? ($input['id'] ?? '');
    $reviewAction = $input['action'] ?? ($input['status'] ?? '');
    $comment = trim($input['comment'] ?? ($input['review_comments'] ?? ($input['feedback'] ?? '')));

    // ገምጋሚው ከ Token ብቻ ይወሰዳል
    $reviewerName = $auth['full_name'] ?? 'የፅ/ቤት ዋና ጸሐፊ';
    $reviewerRole = 'የፅ/ቤት ዋና ጸሐፊ';

    if (empty($reportId) || empty($reviewAction)) {
        jsonError('የሪፖርት መለያ (report_id) እና የግምገማ ውሳኔ (action) ያስፈልጋል', 400);
    }

    $validActions = ['approved', 'revision_requested', 'rejected', 'under_review'];
    if (!in_array($reviewAction, $validActions, true)) {
        jsonError('ትክክለኛ ያልሆነ የግምገማ ውሳኔ', 400);
    }

    $pdo->beginTransaction();
    try {
        $now = date('Y-m-d H:i:s');
        $stmt = $pdo->prepare("
            UPDATE reports SET
                status = ?, office_feedback = ?, reviewed_by = ?, reviewed_at = ?, version = version + 1
            WHERE id = ?
        ");
        $stmt->execute([$reviewAction, $comment, $reviewerName, $now, $reportId]);

        $revStmt = $pdo->prepare("INSERT INTO report_reviews (report_id, reviewer_name, reviewer_role, action, comment) VALUES (?, ?, ?, ?, ?)");
        $revStmt->execute([$reportId, $reviewerName, $reviewerRole, $reviewAction, $comment]);

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
        logAudit($pdo, 'review_report', 'reports', $reportId, $auth['user_id'], 'admin', [
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
