<?php
// ============================================================
// የአጸደ ትጉሃን ይፋዊ ሰነዶች ማህደር ኤፒአይ (Hardened Documents API)
// ============================================================

require_once __DIR__ . '/config.php';

$auth = requireAuth();
$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    $type = $_GET['type'] ?? null;
    $sql = "SELECT * FROM documents WHERE 1=1";
    $params = [];

    if (!$auth['is_super_admin']) {
        $sql .= " AND department_id = ?";
        $params[] = $auth['department_id'];
    } else {
        $dept = $_GET['dept'] ?? null;
        if ($dept && $dept !== 'all' && $dept !== 'admin') {
            $sql .= " AND department_id = ?";
            $params[] = $dept;
        }
    }

    if ($type) {
        $sql .= " AND doc_type = ?";
        $params[] = $type;
    }

    $sql .= " ORDER BY created_at DESC";
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    jsonResponse($stmt->fetchAll());
}

if ($method === 'POST') {
    $input = getJsonInput();

    $id = !empty($input['id']) ? $input['id'] : ('doc_' . time() . '_' . rand(100, 999));
    $deptId = $auth['is_super_admin'] ? ($input['department_id'] ?? $auth['department_id']) : $auth['department_id'];
    $docType = in_array($input['doc_type'] ?? '', ['letter', 'proposal', 'note', 'table'], true) ? $input['doc_type'] : 'letter';
    $title = trim($input['title'] ?? 'ይፋዊ ሰነድ');
    $recipient = $input['recipient'] ?? null;
    $date = $input['date'] ?? date('d/m/Y');
    $contentJson = json_encode($input['content'] ?? $input, JSON_UNESCAPED_UNICODE);
    $pdfPath = $input['pdf_file_path'] ?? null;

    $stmt = $pdo->prepare("
        INSERT INTO documents (
            id, department_id, doc_type, title, recipient, date, content_json, pdf_file_path
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?
        ) ON DUPLICATE KEY UPDATE
            title = VALUES(title),
            recipient = VALUES(recipient),
            content_json = VALUES(content_json),
            pdf_file_path = VALUES(pdf_file_path)
    ");
    $stmt->execute([$id, $deptId, $docType, $title, $recipient, $date, $contentJson, $pdfPath]);

    logAudit($pdo, 'save_document', 'documents', $id, $auth['user_id'], $deptId, ['title' => $title, 'type' => $docType]);

    jsonResponse(['message' => 'ሰነዱ በተሳካ ሁኔታ በማህደር ተቀምጧል', 'id' => $id]);
}

jsonError('ያልተፈቀደ ዘዴ', 405);
