<?php
// ============================================================
// የአጸደ ትጉሃን ማሳወቂያዎች ኤፒአይ (Notifications API)
// ============================================================

require_once __DIR__ . '/config.php';

$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';

// 1. ማሳወቂያዎችን ማምጣት
if ($method === 'GET') {
    $dept = $_GET['dept'] ?? null;
    $unreadOnly = isset($_GET['unread_only']) && $_GET['unread_only'] === '1';

    $sql = "SELECT * FROM notifications WHERE 1=1";
    $params = [];

    if ($dept && $dept !== 'all') {
        $sql .= " AND (department_id = ? OR department_id = 'all' OR department_id IS NULL)";
        $params[] = $dept;
    }

    if ($unreadOnly) {
        $sql .= " AND is_read = 0";
    }

    $sql .= " ORDER BY created_at DESC LIMIT 50";
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $notifications = $stmt->fetchAll();

    // ያልተነበቡ ብዛት
    $countSql = "SELECT COUNT(*) FROM notifications WHERE is_read = 0";
    $countParams = [];
    if ($dept && $dept !== 'all') {
        $countSql .= " AND (department_id = ? OR department_id = 'all' OR department_id IS NULL)";
        $countParams[] = $dept;
    }
    $cStmt = $pdo->prepare($countSql);
    $cStmt->execute($countParams);
    $unreadCount = (int)$cStmt->fetchColumn();

    jsonResponse([
        'unread_count' => $unreadCount,
        'notifications' => $notifications
    ]);
}

// 2. የተነበበ ምልክት ማድረግ (Mark as Read)
if ($method === 'POST') {
    $input = getJsonInput();
    $id = $input['id'] ?? null;
    $markAll = isset($input['mark_all']) && $input['mark_all'] === true;
    $dept = $input['department_id'] ?? null;

    if ($markAll) {
        if ($dept) {
            $stmt = $pdo->prepare("UPDATE notifications SET is_read = 1 WHERE department_id = ? OR department_id = 'all'");
            $stmt->execute([$dept]);
        } else {
            $pdo->query("UPDATE notifications SET is_read = 1");
        }
        jsonResponse(['message' => 'ሁሉም ማሳወቂያዎች እንደተነበቡ ተደርገዋል']);
    }

    if ($id) {
        $stmt = $pdo->prepare("UPDATE notifications SET is_read = 1 WHERE id = ?");
        $stmt->execute([$id]);
        jsonResponse(['message' => 'ማሳወቂያው እንደተነበበ ተደርጓል', 'id' => $id]);
    }

    // አዲስ ማሳወቂያ በእጅ መፍጠር (ለምሳሌ ይፋዊ ማስታወቂያ)
    if (!empty($input['title']) && !empty($input['message'])) {
        $notifId = 'notif_' . uniqid();
        $targetDept = $input['department_id'] ?? 'all';
        $type = $input['type'] ?? 'announcement';
        $stmt = $pdo->prepare("INSERT INTO notifications (id, department_id, title, message, type) VALUES (?, ?, ?, ?, ?)");
        $stmt->execute([$notifId, $targetDept, $input['title'], $input['message'], $type]);
        jsonResponse(['message' => 'ማሳወቂያው ተልኳል', 'id' => $notifId]);
    }

    jsonError('ልክ ያልሆነ ጥያቄ', 400);
}

jsonError('ያልተፈቀደ ዘዴ', 405);
