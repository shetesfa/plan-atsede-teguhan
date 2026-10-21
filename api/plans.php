<?php
require_once __DIR__ . '/db.php';

$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    $dept = $_GET['dept'] ?? null;
    if ($dept && $dept !== 'admin') {
        $stmt = $pdo->prepare("SELECT * FROM plans WHERE department_id = ? ORDER BY id ASC");
        $stmt->execute([$dept]);
    } else {
        $stmt = $pdo->query("SELECT * FROM plans ORDER BY id ASC");
    }
    $plans = $stmt->fetchAll();
    echo json_encode(['status' => 'success', 'data' => $plans]);
    exit;
}

if ($method === 'POST') {
    $input = json_decode(file_get_contents('php://input'), true);
    if (!$input || empty($input['id'])) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'message' => 'የዕቅድ መለያ (ID) ያስፈልጋል']);
        exit;
    }

    $id = $input['id'];
    $progress = $input['progress_percent'] ?? 0;

    $stmt = $pdo->prepare("UPDATE plans SET progress_percent = ? WHERE id = ?");
    $stmt->execute([$progress, $id]);

    echo json_encode(['status' => 'success', 'message' => 'ዕቅዱ ተሻሽሏል']);
    exit;
}
