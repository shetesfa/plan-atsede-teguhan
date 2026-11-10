<?php
// ============================================================
// የአጸደ ትጉሃን ማሳወቂያዎች ኤፒአይ (Hardened Notifications API)
// ============================================================

require_once __DIR__ . '/config.php';

$auth = requireAuth();
$method = $_SERVER['REQUEST_METHOD'];

// 1. ማሳወቂያዎችን ማምጣት
if ($method === 'GET') {
    $unreadOnly = isset($_GET['unread_only']) && $_GET['unread_only'] === '1';

    $sql = "
        SELECT n.id, n.department_id, n.title, n.message, n.type, n.target_id, n.created_at,
               IF(nr.id IS NOT NULL, 1, 0) AS is_read
        FROM notifications n
        LEFT JOIN notification_reads nr ON nr.notification_id = n.id AND nr.user_id = ?
        WHERE 1=1
    ";
    $params = [$auth['user_id']];

    if (!$auth['is_super_admin']) {
        $sql .= " AND (n.department_id = ? OR n.department_id = 'all' OR n.department_id IS NULL)";
        $params[] = $auth['department_id'];
    }

    if ($unreadOnly) {
        $sql .= " AND nr.id IS NULL";
    }

    $sql .= " ORDER BY n.created_at DESC LIMIT 50";
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $notifications = $stmt->fetchAll();

    $countSql = "
        SELECT COUNT(*)
        FROM notifications n
        LEFT JOIN notification_reads nr ON nr.notification_id = n.id AND nr.user_id = ?
        WHERE nr.id IS NULL
    ";
    $countParams = [$auth['user_id']];
    if (!$auth['is_super_admin']) {
        $countSql .= " AND (n.department_id = ? OR n.department_id = 'all' OR n.department_id IS NULL)";
        $countParams[] = $auth['department_id'];
    }
    $cStmt = $pdo->prepare($countSql);
    $cStmt->execute($countParams);
    $unreadCount = (int)$cStmt->fetchColumn();

    jsonResponse([
        'unread_count' => $unreadCount,
        'notifications' => $notifications
    ]);
}

// 2. የተነበበ ምልክት ማድረግ ወይም ይፋዊ ማስታወቂያ መላክ
if ($method === 'POST') {
    $input = getJsonInput();
    $id = $input['id'] ?? null;
    $markAll = isset($input['mark_all']) && $input['mark_all'] === true;

    if ($markAll) {
        $stmt = $pdo->prepare("
            INSERT IGNORE INTO notification_reads (notification_id, user_id, read_at)
            SELECT id, ?, NOW()
            FROM notifications
            WHERE (? = 1 OR department_id = ? OR department_id = 'all' OR department_id IS NULL)
        ");
        $stmt->execute([
            $auth['user_id'],
            $auth['is_super_admin'] ? 1 : 0,
            $auth['department_id']
        ]);
        jsonResponse(['message' => 'ሁሉም ማሳወቂያዎች እንደተነበቡ ተደርገዋል']);
    }

    if ($id) {
        $checkStmt = $pdo->prepare("SELECT department_id FROM notifications WHERE id = ?");
        $checkStmt->execute([$id]);
        $notif = $checkStmt->fetch();

        if (!$notif) {
            jsonError('ማሳወቂያው አልተገኘም', 404);
        }

        // የማሳወቂያው ባለቤት ወይም ፅ/ቤት ወይም ይፋዊ (all) ካልሆነ መከልከል (IDOR Protection)
        if (!$auth['is_super_admin'] && $notif['department_id'] !== $auth['department_id'] && $notif['department_id'] !== 'all' && $notif['department_id'] !== null) {
            jsonError('የተከለከለ ክንውን! የሌላ ክፍልን ማሳወቂያ የመቀየር ፈቃድ የለዎትም (Forbidden).', 403);
        }

        $stmt = $pdo->prepare("INSERT IGNORE INTO notification_reads (notification_id, user_id, read_at) VALUES (?, ?, NOW())");
        $stmt->execute([$id, $auth['user_id']]);
        jsonResponse(['message' => 'ማሳወቂያው እንደተነበበ ተደርጓል', 'id' => $id]);
    }

    // አዲስ ይፋዊ ማስታወቂያ መላክ (ፅ/ቤት ብቻ!)
    if (!empty($input['title']) && !empty($input['message'])) {
        requireSuperAdmin($auth);
        $notifId = 'notif_' . uniqid();
        $targetDept = $input['department_id'] ?? 'all';
        $type = $input['type'] ?? 'announcement';
        $stmt = $pdo->prepare("INSERT INTO notifications (id, department_id, title, message, type) VALUES (?, ?, ?, ?, ?)");
        $stmt->execute([$notifId, $targetDept, htmlspecialchars($input['title'], ENT_QUOTES, 'UTF-8'), htmlspecialchars($input['message'], ENT_QUOTES, 'UTF-8'), $type]);
        jsonResponse(['message' => 'ማሳወቂያው ተልኳል', 'id' => $notifId]);
    }

    jsonError('ልክ ያልሆነ ጥያቄ', 400);
}

jsonError('ያልተፈቀደ ዘዴ', 405);
