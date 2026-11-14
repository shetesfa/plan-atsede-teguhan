<?php
/**
 * =====================================================================
 * ዓጸደ ትጉሃን - ገለልተኛ እና አስተማማኝ የደህንነት እና የፍቃድ ማረጋገጫ (Master Isolated Test Suite)
 * =====================================================================
 * 
 * ደንቦች (Rules):
 * 1. በምርት (Production) ዳታቤዝ ላይ በፍጹም አይሮጥም (Production-Protected).
 * 2. እውነተኛ ተጠቃሚዎችን፣ የይለፍ ቃሎችን ወይም ነባር መረጃዎችን በፍጹም አይነካም (Zero Production Data Tampering).
 * 3. ሊጣሉ የሚችሉ ጊዜያዊ የሙከራ መለያዎችን (Disposable Fixtures) ብቻ በራሱ ይፈጥራል።
 * 4. ሙከራው ሲያበቃ የፈጠራቸውን ሁሉንም ጊዜያዊ መረጃዎች ሙሉ በሙሉ ያጸዳል (Automated Teardown).
 */

require_once __DIR__ . '/../api/config.php';

// 1. ጥብቅ የምርት ጥበቃ (Strict Production Guard - No Bypass Allowed)
if (($appEnv ?? '') === 'production') {
    die("FATAL: የሙከራ ስብስብ በምርት (Production) አካባቢ ላይ እንዳይሮጥ በደህንነት ምክንያት በጥብቅ ታግዷል!\n");
}

class IsolatedMasterSecurityTest {
    private string $baseUrl;
    private PDO $pdo;
    private string $runId;
    
    // ጊዜያዊ የሙከራ መለያዎች እና ቶከኖች
    private string $testEduUser;
    private string $testMezUser;
    private string $testAdminUser;
    private string $testSuspUser;
    private string $testPassword = 'TestPassword@2026!';

    private ?string $eduToken = null;
    private ?string $mezToken = null;
    private ?string $adminToken = null;

    private int $passed = 0;
    private int $failed = 0;
    private array $failures = [];

    public function __construct(string $baseUrl = 'http://127.0.0.1:8000') {
        global $pdo;
        $this->baseUrl = rtrim($baseUrl, '/');
        $this->pdo = $pdo;
        $this->runId = bin2hex(random_bytes(4));

        $this->testEduUser = '__test_edu_' . $this->runId;
        $this->testMezUser = '__test_mez_' . $this->runId;
        $this->testAdminUser = '__test_admin_' . $this->runId;
        $this->testSuspUser = '__test_susp_' . $this->runId;
    }

    public function run(): void {
        echo "=================================================================\n";
        echo "   ዓጸደ ትጉሃን - ገለልተኛ የደህንነት እና የፍቃድ ማረጋገጫ (Run ID: {$this->runId})\n";
        echo "=================================================================\n\n";

        try {
            $this->setupFixtures();
            $this->runAllSecurityTests();
        } finally {
            $this->teardownFixtures();
        }

        $this->printSummary();
    }

    /**
     * ጊዜያዊ የሙከራ መለያዎችን እና ዳታዎችን ማዘጋጀት (Fixture Setup)
     */
    private function setupFixtures(): void {
        echo "🔧 [Setup] ጊዜያዊ የሙከራ መለያዎችን እና ዳታዎችን ማዘጋጀት...\n";
        $hash = password_hash($this->testPassword, PASSWORD_BCRYPT, ['cost' => 10]);

        // 1. የሙከራ ክፍሎች መኖራቸውን ማረጋገጥ (ነባር ክፍሎችን ሳይቀይሩ በደህና መመዝገብ)
        $this->pdo->exec("
            INSERT IGNORE INTO departments (id, name, short_name, is_super_admin) VALUES
            ('education', 'የትምህርት እና ስልጠና ክፍል', 'ትምህርት', 0),
            ('mezmur', 'የመዝሙር እና ስነጥበብ ክፍል', 'መዝሙር', 0),
            ('admin', 'የሰንበት ት/ቤት ፅ/ቤት', 'ፅ/ቤት', 1);
        ");

        // 2. ጊዜያዊ የሙከራ ተጠቃሚዎችን መፍጠር
        $stmt = $this->pdo->prepare("
            INSERT INTO users (department_id, username, full_name, role_title, password_hash, status)
            VALUES (?, ?, ?, ?, ?, ?)
        ");
        $stmt->execute(['education', $this->testEduUser, 'የሙከራ ትምህርት ኃላፊ', 'የትምህርት ኃላፊ', $hash, 'active']);
        $stmt->execute(['mezmur', $this->testMezUser, 'የሙከራ መዝሙር ኃላፊ', 'የመዝሙር ኃላፊ', $hash, 'active']);
        $stmt->execute(['admin', $this->testAdminUser, 'የሙከራ ፅ/ቤት ጸሐፊ', 'የፅ/ቤት ጸሐፊ', $hash, 'active']);
        $stmt->execute(['education', $this->testSuspUser, 'የታገደ የሙከራ አባል', 'አባል', $hash, 'suspended']);

        echo "✅ [Setup] የሙከራ መለያዎች ተዘጋጅተዋል: {$this->testEduUser}, {$this->testMezUser}, {$this->testAdminUser}\n\n";
    }

    /**
     * ሙከራው ሲያበቃ የፈጠራቸውን ጊዜያዊ ዳታዎች ማጽዳት (Fixture Teardown)
     */
    private function teardownFixtures(): void {
        echo "\n🧹 [Teardown] ጊዜያዊ የሙከራ መረጃዎችን ከዳታቤዝ ማጽዳት...\n";
        try {
            // የሙከራ ተጠቃሚዎችን ማጽዳት
            $stmt = $this->pdo->prepare("DELETE FROM users WHERE username IN (?, ?, ?, ?)");
            $stmt->execute([$this->testEduUser, $this->testMezUser, $this->testAdminUser, $this->testSuspUser]);

            // በ runId የተፈጠሩ የሙከራ እቅዶችን፣ ሪፖርቶችን፣ ሰነዶችን እና መልእክቶችን ማጽዳት
            $like = "%{$this->runId}%";
            $this->pdo->prepare("DELETE FROM reports WHERE id LIKE ? OR title LIKE ?")->execute([$like, $like]);
            $this->pdo->prepare("DELETE FROM plans WHERE id LIKE ? OR main_task LIKE ?")->execute([$like, $like]);
            $this->pdo->prepare("DELETE FROM documents WHERE id LIKE ? OR title LIKE ?")->execute([$like, $like]);
            $this->pdo->prepare("DELETE FROM chat_messages WHERE id LIKE ? OR message LIKE ?")->execute([$like, $like]);
            $this->pdo->prepare("DELETE FROM sync_queue WHERE id LIKE ?")->execute([$like]);
            $this->pdo->prepare("DELETE FROM notifications WHERE id LIKE ? OR title LIKE ?")->execute([$like, $like]);

            echo "✅ [Teardown] ሁሉም ጊዜያዊ የሙከራ መረጃዎች በንጽህና ተወግደዋል!\n";
        } catch (\Exception $e) {
            echo "⚠️ [Teardown Error]: " . $e->getMessage() . "\n";
        }
    }

    private function runAllSecurityTests(): void {
        $this->testUnauthenticatedAccess();
        $this->testInvalidTokens();
        $this->testAuthenticationAndLogins();
        $this->testSuspendedUserEnforcement();
        $this->testRateLimitingAndBruteForce();
        $this->testPasswordManagement();
        $this->testPlanRbacAndConcurrency();
        $this->testReportWorkflowAndImmutability();
        $this->testChatRoomsAndMembership();
        $this->testPerUserReadReceipts();
        $this->testDocumentRbac();
        $this->testNotificationRbac();
        $this->testSecureFileDownloads();
        $this->testMaliciousUploadPrevention();
        $this->testSyncIdempotencyAndSecurity();
        $this->testSyncIdorAndOwnership();
        $this->testLogoutAndTokenRevocation();
    }

    // --- 1. ያልተፈቀደ መዳረሻ ፍተሻ (Unauthenticated) ---
    private function testUnauthenticatedAccess(): void {
        echo "--- 1. ያልተፈቀደ መዳረሻ ፍተሻ (Unauthenticated Endpoints) ---\n";
        $endpoints = [
            '/api/plans.php',
            '/api/reports.php',
            '/api/chat.php',
            '/api/sync.php',
            '/api/notifications.php',
            '/api/documents.php'
        ];

        foreach ($endpoints as $ep) {
            $res = $this->request('GET', $ep);
            $this->record("ያለ Token $ep መጠየቅ", $res['status'] === 401, "401 Unauthorized", (string)$res['status']);
        }
    }

    // --- 2. የተጭበረበረ ወይም የተበላሸ ቶከን ---
    private function testInvalidTokens(): void {
        echo "\n--- 2. የተጭበረበረ ወይም የተበላሸ ቶከን ፍተሻ (Forged Token) ---\n";
        $res = $this->request('GET', '/api/plans.php', null, 'forged.signature.token');
        $this->record("በተጭበረበረ ቶከን መጠየቅ ሲከለከል (401)", $res['status'] === 401, "401 Unauthorized", (string)$res['status']);
    }

    // --- 3. ትክክለኛ መግቢያ እና ቶከን አሰጣጥ ---
    private function testAuthenticationAndLogins(): void {
        echo "\n--- 3. ትክክለኛ መግቢያ እና የቶከን አሰጣጥ (Valid Logins) ---\n";
        
        // የተሳሳተ የይለፍ ቃል
        $resBad = $this->request('POST', '/api/auth.php', [
            'username' => $this->testEduUser,
            'password' => 'WrongPassword999!'
        ]);
        $this->record("የተሳሳተ የይለፍ ቃል ሲቀርብ መከልከሉ (401)", $resBad['status'] === 401, "401 Unauthorized", (string)$resBad['status']);

        // የትምህርት ክፍል መግቢያ
        $resEdu = $this->request('POST', '/api/auth.php', [
            'username' => $this->testEduUser,
            'password' => $this->testPassword
        ]);
        $hasEduToken = !empty($resEdu['body']['data']['token'] ?? null);
        if ($hasEduToken) $this->eduToken = $resEdu['body']['data']['token'];
        $this->record("የትምህርት ክፍል ጊዜያዊ መለያ መግባት (200)", $resEdu['status'] === 200 && $hasEduToken, "200 OK + Token", (string)$resEdu['status']);

        // የመዝሙር ክፍል መግቢያ
        $resMez = $this->request('POST', '/api/auth.php', [
            'username' => $this->testMezUser,
            'password' => $this->testPassword
        ]);
        $hasMezToken = !empty($resMez['body']['data']['token'] ?? null);
        if ($hasMezToken) $this->mezToken = $resMez['body']['data']['token'];
        $this->record("የመዝሙር ክፍል ጊዜያዊ መለያ መግባት (200)", $resMez['status'] === 200 && $hasMezToken, "200 OK + Token", (string)$resMez['status']);

        // የፅ/ቤት አስተዳዳሪ መግቢያ
        $resAdmin = $this->request('POST', '/api/auth.php', [
            'username' => $this->testAdminUser,
            'password' => $this->testPassword
        ]);
        $hasAdminToken = !empty($resAdmin['body']['data']['token'] ?? null);
        if ($hasAdminToken) $this->adminToken = $resAdmin['body']['data']['token'];
        $this->record("የፅ/ቤት አስተዳዳሪ ጊዜያዊ መለያ መግባት (200)", $resAdmin['status'] === 200 && $hasAdminToken, "200 OK + Token", (string)$resAdmin['status']);
    }

    // --- 4. የታገደ ተጠቃሚ መከልከሉ ---
    private function testSuspendedUserEnforcement(): void {
        echo "\n--- 4. የታገደ ተጠቃሚ ፍተሻ (Suspended User Check) ---\n";
        $res = $this->request('POST', '/api/auth.php', [
            'username' => $this->testSuspUser,
            'password' => $this->testPassword
        ]);
        $this->record("የታገደ ተጠቃሚ (suspended) መግባት ሲከለከል (401)", $res['status'] === 401, "401 Unauthorized", (string)$res['status']);
    }

    // --- 5. የብሩት ፎርስ መከላከያ (Rate Limiting) ---
    private function testRateLimitingAndBruteForce(): void {
        echo "\n--- 5. የብሩት ፎርስ መከላከያ ፍተሻ (Rate Limiting) ---\n";
        $hitRateLimit = false;
        $attemptStatus = 0;

        for ($i = 0; $i < 7; $i++) {
            $res = $this->request('POST', '/api/auth.php', [
                'username' => 'non_existent_brute_' . $this->runId,
                'password' => 'WrongPass!'
            ]);
            if ($res['status'] === 429) {
                $hitRateLimit = true;
                $attemptStatus = 429;
                break;
            }
            $attemptStatus = $res['status'];
        }

        $this->record("ከተደጋጋሚ የስህተት ሙከራ በኋላ 429 Too Many Requests ማግኘት", $hitRateLimit, "429 Too Many Requests", (string)$attemptStatus);
    }

    // --- 6. የይለፍ ቃል መቀየር እና የጥንካሬ ማረጋገጫ ---
    private function testPasswordManagement(): void {
        echo "\n--- 6. የይለፍ ቃል መቀየር እና የጥንካሬ ማረጋገጫ (Password Management) ---\n";
        
        // ደካማ የይለፍ ቃል
        $resWeak = $this->request('POST', '/api/auth.php?action=change_password', [
            'old_password' => $this->testPassword,
            'new_password' => '1234'
        ], $this->eduToken);
        $this->record("ደካማ የይለፍ ቃል ሲቀርብ መከልከሉ (400)", $resWeak['status'] === 400, "400 Bad Request", (string)$resWeak['status']);

        // የድሮ የይለፍ ቃል ሲሳሳት
        $resWrongOld = $this->request('POST', '/api/auth.php?action=change_password', [
            'old_password' => 'WrongOldPassword123!',
            'new_password' => 'StrongNewPass@2026!'
        ], $this->eduToken);
        $this->record("የድሮው የይለፍ ቃል ሲሳሳት መከልከሉ (400)", $resWrongOld['status'] === 400, "400 Bad Request", (string)$resWrongOld['status']);
    }

    // --- 7. የእቅዶች RBAC እና Concurrency ---
    private function testPlanRbacAndConcurrency(): void {
        echo "\n--- 7. የእቅዶች RBAC እና የስሪት ግጭት መከላከል (Plans Module) ---\n";
        $planId = "plan_{$this->runId}_1";

        // የትምህርት ክፍል እቅድ መፍጠር
        $resCreate = $this->request('POST', '/api/plans.php', [
            'id' => $planId,
            'main_task' => "የትምህርት እቅድ {$this->runId}",
            'progress_percent' => 10,
            'status' => 'in_progress'
        ], $this->eduToken);
        $this->record("የትምህርት ክፍል የራሱን እቅድ መፍጠር (201)", $resCreate['status'] === 201, "201 Created", (string)$resCreate['status']);

        // በሌላ ክፍል ስም እቅድ ሲፈጠር መከልከል
        $resSpoof = $this->request('POST', '/api/plans.php', [
            'id' => "plan_{$this->runId}_spoof",
            'department_id' => 'mezmur',
            'main_task' => "የተጭበረበረ እቅድ {$this->runId}"
        ], $this->eduToken);
        $this->record("በሌላ ክፍል ስም እቅድ ሲፈጠር መከልከሉ (403)", $resSpoof['status'] === 403, "403 Forbidden", (string)$resSpoof['status']);

        // የመዝሙር ክፍል የትምህርት እቅድ ሲያሻሽል መከልከል
        $resCrossEdit = $this->request('POST', '/api/plans.php', [
            'id' => $planId,
            'main_task' => "የመዝሙር ክፍል ጥቃት {$this->runId}"
        ], $this->mezToken);
        $this->record("የመዝሙር ክፍል የትምህርት እቅድ ሲያሻሽል መከልከሉ (403)", $resCrossEdit['status'] === 403, "403 Forbidden", (string)$resCrossEdit['status']);

        // ተራ ክፍል እቅድ ሲሰርዝ መከልከል (ፅ/ቤት ብቻ)
        $resDel = $this->request('DELETE', "/api/plans.php?id=$planId", null, $this->eduToken);
        $this->record("ተራ ክፍል እቅድ ሲሰርዝ መከልከሉ (Office Only - 403)", $resDel['status'] === 403, "403 Forbidden", (string)$resDel['status']);
    }

    // --- 8. የሪፖርት የስራ ፍሰት እና የማይቀየርበት ደህንነት ---
    private function testReportWorkflowAndImmutability(): void {
        echo "\n--- 8. የሪፖርት የስራ ፍሰት እና የማይቀየርበት ደህንነት (Reports Module) ---\n";
        $reportId = "rep_{$this->runId}_1";
        $planId = "plan_{$this->runId}_1";

        // የትምህርት ክፍል ሪፖርት ማቅረብ
        $resSubmit = $this->request('POST', '/api/reports.php', [
            'id' => $reportId,
            'plan_id' => $planId,
            'title' => "የትምህርት ክንውን ሪፖርት {$this->runId}",
            'activities_completed' => 'ዋና ዋና ተግባራት ተጠናቀዋል',
            'progress_percent' => 50,
            'status' => 'submitted'
        ], $this->eduToken);
        $this->record("የትምህርት ክፍል ሪፖርት ማቅረብ (201)", $resSubmit['status'] === 201, "201 Created", (string)$resSubmit['status']);

        // ተራ ክፍል ሪፖርት ለማጽደቅ ሲሞክር መከልከል
        $resUnauthorizedApprove = $this->request('POST', '/api/reports.php?action=review', [
            'report_id' => $reportId,
            'action' => 'approved'
        ], $this->eduToken);
        $this->record("ተራ ክፍል ሪፖርት ለማጽደቅ ሲሞክር መከልከሉ (403)", $resUnauthorizedApprove['status'] === 403, "403 Forbidden", (string)$resUnauthorizedApprove['status']);

        // ያለ አስተያየት ማሻሻያ ሲጠየቅ መከልከል
        $resNoComment = $this->request('POST', '/api/reports.php?action=review', [
            'report_id' => $reportId,
            'action' => 'revision_requested',
            'comment' => ''
        ], $this->adminToken);
        $this->record("ያለ አስተያየት ማሻሻያ ሲጠየቅ መከልከሉ (400)", $resNoComment['status'] === 400, "400 Bad Request", (string)$resNoComment['status']);

        // የፅ/ቤት አስተዳዳሪ ሪፖርቱን ማጽደቁ
        $resApprove = $this->request('POST', '/api/reports.php?action=review', [
            'report_id' => $reportId,
            'action' => 'approved',
            'comment' => 'ሪፖርቱ በፅ/ቤት ጸድቋል'
        ], $this->adminToken);
        $this->record("የፅ/ቤት አስተዳዳሪ ሪፖርቱን ማጽደቁ (200)", $resApprove['status'] === 200, "200 OK", (string)$resApprove['status']);

        // የጸደቀ ሪፖርት ላይ ተራ ክፍል ለውጥ ሊያደርግ ሲሞክር መከልከል (Immutability)
        $resModifyApproved = $this->request('POST', '/api/reports.php', [
            'id' => $reportId,
            'title' => 'የተቀየረ ርዕስ',
            'activities_completed' => 'የተቀየረ ማብራሪያ'
        ], $this->eduToken);
        $this->record("የጸደቀ ሪፖርት ላይ ለውጥ ሲሞከር መከልከሉ (403)", $resModifyApproved['status'] === 403, "403 Forbidden", (string)$resModifyApproved['status']);
    }

    // --- 9. የቻት ሩም አባልነት እና ፈቃዶች ---
    private function testChatRoomsAndMembership(): void {
        echo "\n--- 9. የቻት ሩም አባልነት እና ፈቃድ ፍተሻ (Chat Module) ---\n";
        
        // ተራ ክፍል ይፋዊ መመሪያ ሲልክ መከልከል
        $resSpoofNotice = $this->request('POST', '/api/chat.php', [
            'channel' => 'general',
            'message' => 'የውሸት ይፋዊ መመሪያ',
            'is_official_notice' => 1
        ], $this->eduToken);
        $this->record("ተራ ክፍል ይፋዊ መመሪያ ሲልክ መከልከሉ (403)", $resSpoofNotice['status'] === 403, "403 Forbidden", (string)$resSpoofNotice['status']);

        // ፅ/ቤት ይፋዊ መመሪያ ማስተላለፉ
        $resNotice = $this->request('POST', '/api/chat.php', [
            'channel' => 'general',
            'message' => 'ትክክለኛ ይፋዊ መመሪያ ከፅ/ቤት',
            'is_official_notice' => 1
        ], $this->adminToken);
        $this->record("ፅ/ቤት ይፋዊ መመሪያ ማስተላለፉ (201)", $resNotice['status'] === 201, "201 Created", (string)$resNotice['status']);

        // ተራ ክፍል ወደ ፅ/ቤት የግል ሩም (office) ሲገባ መከልከል
        $resOfficeRoom = $this->request('GET', '/api/chat.php?channel=office', null, $this->eduToken);
        $this->record("ተራ ክፍል ወደ ፅ/ቤት የግል ሩም (office) ሲገባ መከልከሉ (403)", $resOfficeRoom['status'] === 403, "403 Forbidden", (string)$resOfficeRoom['status']);

        // የክፍሎች ዝርዝር (Rooms) - ተራ ክፍል የፅ/ቤት ሩምን እንዳያይ መከልከል
        $resRooms = $this->request('GET', '/api/chat.php?action=rooms', null, $this->eduToken);
        $hasOfficeRoom = false;
        foreach ($resRooms['body']['data'] ?? [] as $r) {
            if (($r['id'] ?? '') === 'room_office' || ($r['name'] ?? '') === 'ከፅ/ቤት ጋር ቀጥታ መስመር') {
                $hasOfficeRoom = true;
                break;
            }
        }
        $this->record("ተራ ክፍል ሲጠይቅ የፅ/ቤት የግል ሩም በዝርዝር አለመታየቱ", !$hasOfficeRoom, "office room hidden", $hasOfficeRoom ? "visible" : "hidden");
    }

    // --- 10. የተጠቃሚ-ተኮር የንባብ ማረጋገጫ (Per-User Read Receipts) ---
    private function testPerUserReadReceipts(): void {
        echo "\n--- 10. የተጠቃሚ-ተኮር የንባብ ማረጋገጫ (Per-User Read Receipts) ---\n";
        
        $resSend = $this->request('POST', '/api/chat.php', [
            'channel' => 'general',
            'message' => "የተጠቃሚ ንባብ ሙከራ መልእክት {$this->runId}"
        ], $this->eduToken);
        $msgId = $resSend['body']['data']['id'] ?? ($resSend['body']['data']['data']['id'] ?? '');

        // ትምህርት ክፍል መልእክቶቹን እንዳነበበ ያደርጋል
        $this->request('POST', '/api/chat.php?action=mark_read', ['channel' => 'general'], $this->eduToken);

        // የትምህርት ክፍል ቻቱን ሲያይ መልእክቱ is_read = 1 መሆኑ
        $resEdu = $this->request('GET', '/api/chat.php?channel=general', null, $this->eduToken);
        $eduRead = false;
        foreach ($resEdu['body']['data'] ?? [] as $m) {
            if ($m['id'] === $msgId && (int)$m['is_read'] === 1) {
                $eduRead = true;
                break;
            }
        }
        $this->record("ለትምህርት ክፍል መልእክቱ የተነበበ መሆኑ (is_read=1)", $eduRead, "is_read=1", $eduRead ? "1" : "0");

        // ለመዝሙር ክፍል ግን መልእክቱ ያልተነበበ (is_read = 0) መሆን አለበት
        $resMez = $this->request('GET', '/api/chat.php?channel=general', null, $this->mezToken);
        $mezUnread = false;
        foreach ($resMez['body']['data'] ?? [] as $m) {
            if ($m['id'] === $msgId && (int)$m['is_read'] === 0) {
                $mezUnread = true;
                break;
            }
        }
        $this->record("ለመዝሙር ክፍል ግን መልእክቱ ያልተነበበ መሆኑ (is_read=0)", $mezUnread, "is_read=0", $mezUnread ? "0" : "1");
    }

    // --- 11. የሰነዶች RBAC ---
    private function testDocumentRbac(): void {
        echo "\n--- 11. የሰነዶች RBAC እና መደራረብ መከላከል (Documents Module) ---\n";
        $docId = "doc_{$this->runId}_1";

        // የትምህርት ክፍል ሰነድ መፍጠር
        $resCreate = $this->request('POST', '/api/documents.php', [
            'id' => $docId,
            'title' => "የትምህርት ሰነድ {$this->runId}",
            'doc_type' => 'letter',
            'content' => ['body' => 'የሰነድ ይዘት']
        ], $this->eduToken);
        $this->record("የትምህርት ክፍል ሰነድ መፍጠር (201)", $resCreate['status'] === 201, "201 Created", (string)$resCreate['status']);

        // የመዝሙር ክፍል የትምህርት ሰነድ ሊተካ ሲሞክር መከልከል
        $resOverwrite = $this->request('POST', '/api/documents.php', [
            'id' => $docId,
            'title' => "የተሰረቀ ሰነድ {$this->runId}"
        ], $this->mezToken);
        $this->record("የመዝሙር ክፍል የትምህርት ሰነድ ሊተካ ሲሞክር መከልከሉ (403)", $resOverwrite['status'] === 403, "403 Forbidden", (string)$resOverwrite['status']);

        // የመዝሙር ክፍል የትምህርት ሰነድ ሲሰርዝ መከልከል
        $resDelOther = $this->request('DELETE', "/api/documents.php?id=$docId", null, $this->mezToken);
        $this->record("የመዝሙር ክፍል የትምህርት ሰነድ ሲሰርዝ መከልከሉ (403)", $resDelOther['status'] === 403, "403 Forbidden", (string)$resDelOther['status']);
    }

    // --- 12. የማሳወቂያ IDOR መከላከል ---
    private function testNotificationRbac(): void {
        echo "\n--- 12. የማሳወቂያ IDOR መከላከል (Notifications Module) ---\n";
        
        // ፅ/ቤት ለመዝሙር ክፍል ብቻ ማሳወቂያ ይልካል
        $resSendNotif = $this->request('POST', '/api/notifications.php', [
            'department_id' => 'mezmur',
            'title' => "የመዝሙር ማሳወቂያ {$this->runId}",
            'message' => 'ለመዝሙር ክፍል ብቻ የሚደርስ ማሳወቂያ'
        ], $this->adminToken);
        $notifId = $resSendNotif['body']['data']['id'] ?? '';

        // የትምህርት ክፍል የመዝሙርን ማሳወቂያ እንዳነበበ ለማድረግ ሲሞክር መከልከል
        $resTamper = $this->request('POST', '/api/notifications.php', ['id' => $notifId], $this->eduToken);
        $this->record("የትምህርት ክፍል የመዝሙርን ማሳወቂያ ሊያነብ ሲሞክር መከልከሉ (403)", $resTamper['status'] === 403, "403 Forbidden", (string)$resTamper['status']);
    }

    // --- 13. የተጠበቀ የፋይል ማውረድ ---
    private function testSecureFileDownloads(): void {
        echo "\n--- 13. የተጠበቀ የፋይል ማውረድ እና RBAC (File Download Security) ---\n";
        
        // 1. በ Query Parameter የሚላክ ቶከን መከልከሉ
        $resQueryToken = $this->request('GET', "/api/files.php?id=fake&token={$this->eduToken}");
        $this->record("በ Query Parameter ?token= ሲላክ መከልከሉ (401)", $resQueryToken['status'] === 401, "401 Unauthorized", (string)$resQueryToken['status']);

        // 2. ያለ ቶከን ፋይል መጠየቅ ሲከለከል
        $resNoToken = $this->request('GET', '/api/files.php?id=fake');
        $this->record("ያለ Token ፋይል መጠየቅ ሲከለከል (401)", $resNoToken['status'] === 401, "401 Unauthorized", (string)$resNoToken['status']);
    }

    // --- 14. አደገኛ የፋይል ሰቀላ መከላከል ---
    private function testMaliciousUploadPrevention(): void {
        echo "\n--- 14. አደገኛ የፋይል ሰቀላ መከላከል (Malicious Upload Blocked) ---\n";
        $cfile = new CURLFile(__FILE__, 'text/php', 'exploit_shell.php');
        
        $ch = curl_init($this->baseUrl . '/api/reports.php?action=upload');
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, ['file' => $cfile]);
        curl_setopt($ch, CURLOPT_HTTPHEADER, ["Authorization: Bearer " . $this->eduToken]);
        $raw = curl_exec($ch);
        $statusCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        $this->record("የ .php አደገኛ ፋይል ሰቀላ መከልከሉ (400)", $statusCode === 400, "400 Bad Request", (string)$statusCode);
    }

    // --- 15. ከመስመር ውጭ ማመሳሰል Idempotency ---
    private function testSyncIdempotencyAndSecurity(): void {
        echo "\n--- 15. ከመስመር ውጭ ማመሳሰል እና Idempotency (Sync Module) ---\n";
        
        $syncId = "sync_{$this->runId}_idemp";
        $batch = [
            'device_id' => 'device_test_1',
            'changes' => [
                [
                    'sync_id' => $syncId,
                    'entity_type' => 'plan',
                    'action' => 'update',
                    'version' => 10,
                    'payload' => [
                        'id' => "plan_{$this->runId}_1",
                        'progress_percent' => 75
                    ]
                ]
            ]
        ];

        // የመጀመሪያ ማመሳሰል
        $res1 = $this->request('POST', '/api/sync.php', $batch, $this->eduToken);
        $p1 = $res1['body']['data']['summary']['processed'] ?? 0;

        // ሁለተኛ ተደጋጋሚ ማመሳሰል (ተመሳሳይ sync_id)
        $res2 = $this->request('POST', '/api/sync.php', $batch, $this->eduToken);
        $s2 = $res2['body']['data']['summary']['skipped_duplicates'] ?? 0;

        $this->record("የማመሳሰል Idempotency (የመጀመሪያ ተከናውኗል፣ ሁለተኛው ተዘሏል)", $p1 === 1 && $s2 === 1, "p=1, s=1", "p=$p1, s=$s2");

        // የተለየ ተጠቃሚ የዚህን ተጠቃሚ sync_id ሊጠቀም ሲሞክር መከልከል (Sync Key Hijack Blocked)
        $resHijack = $this->request('POST', '/api/sync.php', $batch, $this->mezToken);
        $this->record("ሌላ ተጠቃሚ የዚህን ተጠቃሚ sync_id ሲጠቀም መከልከሉ (403)", $resHijack['status'] === 403, "403 Forbidden", (string)$resHijack['status']);

        // ተመሳሳይ sync_id ከተለየ ይዘት ጋር ሲላክ ግጭት መጣል (Idempotency Conflict 409)
        $conflictBatch = $batch;
        $conflictBatch['changes'][0]['payload']['progress_percent'] = 99; // Different content
        $resConflict = $this->request('POST', '/api/sync.php', $conflictBatch, $this->eduToken);
        $this->record("ተመሳሳይ sync_id ከተለየ ይዘት ጋር ሲላክ ግጭት መጣሉ (409)", $resConflict['status'] === 409, "409 Conflict", (string)$resConflict['status']);
    }

    // --- 16. የማመሳሰል IDOR እና የጸደቀ ሪፖርት ጥበቃ ---
    private function testSyncIdorAndOwnership(): void {
        echo "\n--- 16. የማመሳሰል IDOR እና የጸደቀ ሪፖርት ጥበቃ (Sync IDOR) ---\n";
        
        // በ Sync ውስጥ የትምህርት ሪፖርትን የመዝሙር ክፍል ሊቀይር ሲሞክር መከልከል
        $syncIdorBatch = [
            'device_id' => 'device_attacker',
            'changes' => [
                [
                    'sync_id' => "sync_{$this->runId}_idor_rep",
                    'entity_type' => 'report',
                    'action' => 'update',
                    'payload' => [
                        'id' => "rep_{$this->runId}_1",
                        'title' => 'በጥቃት የተቀየረ ሪፖርት'
                    ]
                ]
            ]
        ];
        $resIdorRep = $this->request('POST', '/api/sync.php', $syncIdorBatch, $this->mezToken);
        $this->record("በ Sync የሌላ ክፍልን ሪፖርት ማሻሻል ሲከለከል (403)", $resIdorRep['status'] === 403, "403 Forbidden", (string)$resIdorRep['status']);

        // በ Sync ውስጥ የጸደቀ ሪፖርት ሊቀየር ሲሞከር መከልከል
        $syncApprovedBatch = [
            'device_id' => 'device_edu',
            'changes' => [
                [
                    'sync_id' => "sync_{$this->runId}_approved_mod",
                    'entity_type' => 'report',
                    'action' => 'update',
                    'payload' => [
                        'id' => "rep_{$this->runId}_1",
                        'title' => 'የጸደቀ ሪፖርት ማሻሻያ ሙከራ'
                    ]
                ]
            ]
        ];
        $resAppRep = $this->request('POST', '/api/sync.php', $syncApprovedBatch, $this->eduToken);
        $this->record("በ Sync የጸደቀ ሪፖርት ሊቀየር ሲሞከር መከልከሉ (403)", $resAppRep['status'] === 403, "403 Forbidden", (string)$resAppRep['status']);

        // በ Sync ወደ ፅ/ቤት ሩም (office) መልእክት ሲላክ መከልከል
        $syncOfficeChat = [
            'device_id' => 'device_edu',
            'changes' => [
                [
                    'sync_id' => "sync_{$this->runId}_office_chat",
                    'entity_type' => 'chat',
                    'action' => 'insert',
                    'payload' => [
                        'id' => "msg_{$this->runId}_office",
                        'channel' => 'office',
                        'message' => 'ያልተፈቀደ መልእክት ወደ ፅ/ቤት'
                    ]
                ]
            ]
        ];
        $resOfficeChat = $this->request('POST', '/api/sync.php', $syncOfficeChat, $this->eduToken);
        $this->record("በ Sync ወደ ፅ/ቤት ሩም (office) መልእክት ሲላክ መከልከሉ (403)", $resOfficeChat['status'] === 403, "403 Forbidden", (string)$resOfficeChat['status']);

        // በመዝሙር ክፍል የተላከ የቻት መልእክት በዳታቤዝ መመዝገብ
        $mezMsgId = "msg_{$this->runId}_mez_orig";
        $this->pdo->prepare("
            INSERT INTO chat_messages (id, room_id, channel, department_id, sender_name, message)
            VALUES (?, 'ጠቅላላ ውይይት', 'ጠቅላላ ውይይት', 'mezmur', 'የሙከራ መዝሙር ኃላፊ', 'የመዝሙር ኦሪጅናል መልእክት')
        ")->execute([$mezMsgId]);

        // የትምህርት ክፍል ተጠቃሚ የመዝሙር ክፍልን የቻት መልእክት በ Sync ሊቀይር ሲሞክር መከልከል (Chat IDOR 403)
        $syncChatIdor = [
            'device_id' => 'device_edu',
            'changes' => [
                [
                    'sync_id' => "sync_{$this->runId}_chat_idor",
                    'entity_type' => 'chat',
                    'action' => 'update',
                    'payload' => [
                        'id' => $mezMsgId,
                        'message' => 'በትምህርት ክፍል የተበረዘ የመዝሙር መልእክት'
                    ]
                ]
            ]
        ];
        $resChatIdor = $this->request('POST', '/api/sync.php', $syncChatIdor, $this->eduToken);
        $this->record("በ Sync የሌላ ክፍልን የቻት መልእክት ማሻሻል ሲከለከል (403)", $resChatIdor['status'] === 403, "403 Forbidden", (string)$resChatIdor['status']);

        // በቀጥታ በ PUT /api/chat.php የሌላ ክፍልን መልእክት ማሻሻል ሲከለከል (403)
        $resDirectChatEdit = $this->request('PUT', "/api/chat.php?id=$mezMsgId", ['message' => 'ቀጥታ የተበረዘ'], $this->eduToken);
        $this->record("በ PUT የሌላ ሰውን/ክፍልን መልእክት ማሻሻል ሲከለከል (403)", $resDirectChatEdit['status'] === 403, "403 Forbidden", (string)$resDirectChatEdit['status']);
    }

    // --- 17. ሎግአውት እና ቶከን ማሰናከል ---
    private function testLogoutAndTokenRevocation(): void {
        echo "\n--- 17. ሎግአውት እና ቶከን ማሰናከል (Logout & Token Revocation) ---\n";
        
        $resLogout = $this->request('POST', '/api/auth.php?action=logout', null, $this->mezToken);
        $this->record("የመዝሙር ክፍል ሎግአውት ማድረግ (200)", $resLogout['status'] === 200, "200 OK", (string)$resLogout['status']);

        // ከተሰናከለ ቶከን በኋላ ጥያቄ ሲቀርብ መከልከል
        $resAfterLogout = $this->request('GET', '/api/plans.php', null, $this->mezToken);
        $this->record("ከተሰናከለ ቶከን በኋላ መጠየቅ ሲከለከል (401)", $resAfterLogout['status'] === 401, "401 Unauthorized", (string)$resAfterLogout['status']);
    }

    // --- ረዳት ተግባራት (Helpers) ---
    private function request(string $method, string $path, ?array $body = null, ?string $token = null): array {
        $url = $this->baseUrl . $path;
        $ch = curl_init($url);

        $headers = [
            'Accept: application/json',
            'Content-Type: application/json'
        ];
        if ($token) {
            $headers[] = "Authorization: Bearer $token";
        }

        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);

        if ($body !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body, JSON_UNESCAPED_UNICODE));
        }

        $raw = curl_exec($ch);
        $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        $json = json_decode($raw, true);
        return [
            'status' => $status,
            'body' => $json ?: [],
            'raw' => $raw
        ];
    }

    private function record(string $name, bool $passed, string $expected, string $got): void {
        if ($passed) {
            $this->passed++;
            echo " [PASS] $name\n";
        } else {
            $this->failed++;
            $this->failures[] = "$name (Expected: $expected, Got: $got)";
            echo " [FAIL] $name (Expected: $expected, Got: $got)\n";
        }
    }

    private function printSummary(): void {
        echo "\n=================================================================\n";
        echo "   የሙከራው ማጠቃለያ ውጤት (Isolated Test Execution Summary)\n";
        echo "=================================================================\n";
        echo "  አጠቃላይ የተካሄዱ ሙከራዎች: " . ($this->passed + $this->failed) . "\n";
        echo "  ያለፉ (PASSED): {$this->passed}\n";
        echo "  የወደቁ (FAILED): {$this->failed}\n";
        echo "=================================================================\n\n";

        if ($this->failed > 0) {
            echo "የወደቁ ሙከራዎች ዝርዝር:\n";
            foreach ($this->failures as $f) {
                echo " - $f\n";
            }
            exit(1);
        } else {
            echo "🎉 እንኳን ደስ አለዎት! ሁሉም የደህንነት እና የፍቃድ ሙከራዎች 100% አልፈዋል።\n";
            echo "🛡️ የትኛውም እውነተኛ ተጠቃሚ ወይም የምርት መረጃ አልተነካም (Zero Production Data Impact).\n";
            exit(0);
        }
    }
}

// ማስኬድ
$test = new IsolatedMasterSecurityTest();
$test->run();
