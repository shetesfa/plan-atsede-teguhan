<?php
// ============================================================
// የአጸደ ትጉሃን የተጠቃሚዎች አስተዳደር ኤፒአይ (Users API — 2026-11-26)
// ------------------------------------------------------------
// የጽ/ቤት (Super Admin) ብቻ ነው የሚጠቀመው — አዲስ user መጨመር፣
// user መረጃ ማሻሻል፣ password reset፣ user ማሰናከል/ማንቃት።
// DELETE የሚያደርገው ረድፍ መሰረዝ አይደለም — status='inactive'
// ማድረግ ነው (audit log እና ሪፖርቶች እንዳይበላሹ)።
// Role: 'member' (ነባሪ) ወይም 'dept_admin' — dept_admin የራሱን
// ክፍል እቅዶች ብቻ ማስተዳደር ይችላል (ሌላ ክፍል ማየት አይችልም)።
// ============================================================

require_once __DIR__ . '/config.php';

$auth = requireAuth(); // እያንዳንዱ ጥያቄ የግድ የተረጋገጠ ተጠቃሚ መሆን አለበት!
$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';

$userFields = "u.id, u.username, u.full_name, u.role_title, u.role, u.department_id,
               d.name AS department_name, d.short_name AS department_short_name,
               u.status, u.phone, u.email, u.last_login, u.must_change_password, u.created_at";

// 1. የተጠቃሚዎች ዝርዝር ማምጣት (GET — list, or single ?id=)
if ($method === 'GET') {
    requireSuperAdmin($auth);

    $id = $_GET['id'] ?? null;
    if (!empty($id)) {
        $stmt = $pdo->prepare("SELECT $userFields FROM users u LEFT JOIN departments d ON u.department_id = d.id WHERE u.id = ? LIMIT 1");
        $stmt->execute([$id]);
        $user = $stmt->fetch();
        if (!$user) {
            jsonError('ተጠቃሚው አልተገኘም', 404);
        }
        jsonResponse(['user' => $user]);
    }

    $stmt = $pdo->query("SELECT $userFields FROM users u LEFT JOIN departments d ON u.department_id = d.id ORDER BY u.department_id, u.username");
    jsonResponse(['users' => $stmt->fetchAll()]);
}

// 2. አዲስ user መፍጠር / መረጃ ማሻሻል / password reset (POST)
if ($method === 'POST') {
    requireSuperAdmin($auth);
    $input = getJsonInput();

    // (a) አዲስ user መፍጠር
    if ($action === 'create') {
        $username = trim($input['username'] ?? '');
        $fullName = trim($input['full_name'] ?? '');
        $departmentId = trim($input['department_id'] ?? '');
        $password = (string)($input['password'] ?? '');
        $role = ($input['role'] ?? 'member') === 'dept_admin' ? 'dept_admin' : 'member';
        $roleTitle = trim($input['role_title'] ?? '');
        $phone = trim($input['phone'] ?? '') ?: null;
        $email = trim($input['email'] ?? '') ?: null;

        if ($username === '' || $fullName === '' || $departmentId === '') {
            jsonError('የተጠቃሚ ስም፣ ሙሉ ስም እና ክፍል ያስፈልጋሉ', 400);
        }
        if (strlen($password) < 8 || !preg_match('/[0-9]/', $password)) {
            jsonError('የይለፍ ቃል ቢያንስ 8 ፊደላት እና ቢያንስ አንድ ቁጥር መያዝ አለበት።', 400);
        }

        $deptStmt = $pdo->prepare("SELECT id, name FROM departments WHERE id = ? LIMIT 1");
        $deptStmt->execute([$departmentId]);
        $dept = $deptStmt->fetch();
        if (!$dept) {
            jsonError('ክፍሉ አልተገኘም', 400);
        }
        if ($roleTitle === '') {
            $roleTitle = $dept['name'];
        }

        $existsStmt = $pdo->prepare("SELECT id FROM users WHERE username = ? LIMIT 1");
        $existsStmt->execute([$username]);
        if ($existsStmt->fetch()) {
            jsonError('ይህ የተጠቃሚ ስም አስቀድሞ አለ — ሌላ ስም ይምረጡ', 400);
        }

        $hash = password_hash($password, PASSWORD_BCRYPT, ['cost' => 12]);
        $stmt = $pdo->prepare("INSERT INTO users (department_id, username, full_name, role_title, role, password_hash, phone, email, status, must_change_password) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', 1)");
        $stmt->execute([$departmentId, $username, $fullName, $roleTitle, $role, $hash, $phone, $email]);

        $newId = (int)$pdo->lastInsertId();
        logAudit($pdo, 'create_user', 'users', (string)$newId, $auth['user_id'], $auth['department_id'], ['username' => $username, 'department_id' => $departmentId, 'role' => $role]);
        jsonResponse(['message' => 'ተጠቃሚው በተሳካ ሁኔታ ተፈጥሯል — በመጀመሪያ መግቢያ ላይ የይለፍ ቃል መቀየር አለበት', 'id' => $newId], 201);
    }

    // (b) የተጠቃሚ መረጃ ማሻሻል
    if ($action === 'update') {
        $userId = (int)($input['user_id'] ?? $input['id'] ?? 0);
        if ($userId <= 0) {
            jsonError('የተጠቃሚ መለያ (ID) ያስፈልጋል', 400);
        }
        // ራስን መቆለፍ እንዳይሆን — የራስዎን role/status መቀየር አይችሉም።
        $selfChange = ($userId === (int)$auth['user_id']);

        $sets = [];
        $params = [];
        if (isset($input['full_name']) && trim($input['full_name']) !== '') {
            $sets[] = "full_name = ?";
            $params[] = trim($input['full_name']);
        }
        if (isset($input['role_title']) && trim($input['role_title']) !== '') {
            $sets[] = "role_title = ?";
            $params[] = trim($input['role_title']);
        }
        if (isset($input['department_id']) && trim($input['department_id']) !== '') {
            if ($selfChange) {
                jsonError('የራስዎን ክፍል መቀየር አይችሉም', 400);
            }
            $deptStmt = $pdo->prepare("SELECT id FROM departments WHERE id = ? LIMIT 1");
            $deptStmt->execute([trim($input['department_id'])]);
            if (!$deptStmt->fetch()) {
                jsonError('ክፍሉ አልተገኘም', 400);
            }
            $sets[] = "department_id = ?";
            $params[] = trim($input['department_id']);
        }
        if (isset($input['role'])) {
            if ($selfChange) {
                jsonError('የራስዎን ፈቃድ (role) መቀየር አይችሉም', 400);
            }
            $sets[] = "role = ?";
            $params[] = ($input['role'] === 'dept_admin') ? 'dept_admin' : 'member';
        }
        if (isset($input['status'])) {
            if ($selfChange) {
                jsonError('የራስዎን ሁኔታ መቀየር አይችሉም', 400);
            }
            $status = $input['status'];
            if (!in_array($status, ['active', 'inactive', 'suspended'], true)) {
                jsonError('የተሳሳተ ሁኔታ', 400);
            }
            $sets[] = "status = ?";
            $params[] = $status;
        }
        if (array_key_exists('phone', $input)) {
            $sets[] = "phone = ?";
            $params[] = trim($input['phone']) ?: null;
        }
        if (array_key_exists('email', $input)) {
            $sets[] = "email = ?";
            $params[] = trim($input['email']) ?: null;
        }
        if (empty($sets)) {
            jsonError('ምንም የሚሻሻል መረጃ አልተሰጠም', 400);
        }

        $params[] = $userId;
        $stmt = $pdo->prepare("UPDATE users SET " . implode(', ', $sets) . " WHERE id = ?");
        $stmt->execute($params);
        if ($stmt->rowCount() === 0) {
            jsonError('ተጠቃሚው አልተገኘም', 404);
        }
        logAudit($pdo, 'update_user', 'users', (string)$userId, $auth['user_id'], $auth['department_id']);
        jsonResponse(['message' => 'የተጠቃሚው መረጃ ተሻሽሏል', 'id' => $userId]);
    }

    // (c) የይለፍ ቃል ዳግም ማስጀመር (reset — ተጠቃሚው በመጀመሪያ መግቢያ ይቀይረዋል)
    if ($action === 'reset_password') {
        $userId = (int)($input['user_id'] ?? $input['id'] ?? 0);
        $newPass = (string)($input['new_password'] ?? $input['password'] ?? '');
        if ($userId <= 0) {
            jsonError('የተጠቃሚ መለያ (ID) ያስፈልጋል', 400);
        }
        if (strlen($newPass) < 8 || !preg_match('/[0-9]/', $newPass)) {
            jsonError('አዲሱ የይለፍ ቃል ቢያንስ 8 ፊደላት እና ቢያንስ አንድ ቁጥር መያዝ አለበት።', 400);
        }
        $hash = password_hash($newPass, PASSWORD_BCRYPT, ['cost' => 12]);
        // 2026-11-26: bump token_version so every token issued before this
        // reset stops working immediately.
        $stmt = $pdo->prepare("UPDATE users SET password_hash = ?, must_change_password = 1, token_version = token_version + 1 WHERE id = ?");
        $stmt->execute([$hash, $userId]);
        if ($stmt->rowCount() === 0) {
            jsonError('ተጠቃሚው አልተገኘም', 404);
        }
        logAudit($pdo, 'reset_user_password', 'users', (string)$userId, $auth['user_id'], $auth['department_id']);
        jsonResponse(['message' => 'የይለፍ ቃል ዳግም ተጀምሯል — ተጠቃሚው በመጀመሪያ መግቢያ ላይ አዲስ የይለፍ ቃል መቀየር አለበት', 'id' => $userId]);
    }

    jsonError('ያልታወቀ ተግባር', 400);
}

// 3. User ማሰናከል (DELETE — ረድፍ አይሰረዝም፣ status='inactive' ይሆናል)
if ($method === 'DELETE') {
    requireSuperAdmin($auth);
    $id = $_GET['id'] ?? (getJsonInput()['id'] ?? null);
    if (empty($id)) {
        jsonError('የተጠቃሚ መለያ (ID) ያስፈልጋል', 400);
    }
    if ((int)$id === (int)$auth['user_id']) {
        jsonError('ራስዎን ማሰናከል አይችሉም', 400);
    }
    $stmt = $pdo->prepare("UPDATE users SET status = 'inactive' WHERE id = ?");
    $stmt->execute([$id]);
    if ($stmt->rowCount() === 0) {
        jsonError('ተጠቃሚው አልተገኘም', 404);
    }
    logAudit($pdo, 'deactivate_user', 'users', (string)$id, $auth['user_id'], $auth['department_id']);
    jsonResponse(['message' => 'ተጠቃሚው ታግዷል (inactive) — እንደገና ለማንቃት status ማሻሻል ይቻላል', 'id' => (int)$id]);
}

jsonError('ያልተፈቀደ ዘዴ', 405);
