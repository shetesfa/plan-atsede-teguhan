<?php
/**
 * ዓጸደ ትጉሃን - Comprehensive Master Security & Access Control Test Suite
 * 
 * ይህ ስክሪፕት በስርዓቱ ላይ የተተገበሩትን ሁሉንም የደህንነት፣ የማረጋገጫ (Auth)፣
 * የፈቃድ (RBAC)፣ የዳታ ታማኝነት (Data Integrity)፣ የፋይል ደህንነት (File Security)
 * እና የማመሳሰል (Sync Idempotency) ህጎች በዝርዝር ፈትሾ ሪፖርት ያቀርባል።
 */

class MasterSecurityTester {
    private string $baseUrl;
    private array $results = [];
    private ?string $adminToken = null;
    private ?string $educationToken = null;
    private ?string $mezmurToken = null;
    private $createdPlanId = 0;
    private $createdReportId = 0;
    private $createdDocId = 0;
    private $createdAttachmentId = 0;
    private $mezmurNotifId = 0;
    private ?PDO $pdo = null;

    public function __construct(string $baseUrl = 'http://127.0.0.1:8000') {
        $this->baseUrl = rtrim($baseUrl, '/');
    }

    private function getPdo(): PDO {
        if ($this->pdo === null) {
            $envFile = __DIR__ . '/../api/.env';
            if (file_exists($envFile)) {
                $lines = file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
                foreach ($lines as $line) {
                    $line = trim($line);
                    if (!empty($line) && !str_starts_with($line, '#') && str_contains($line, '=')) {
                        list($k, $v) = explode('=', $line, 2);
                        putenv(trim($k) . '=' . trim($v, " \t\n\r\0\x0B\"'"));
                    }
                }
            }
            $host = getenv('DB_HOST') ?: '127.0.0.1';
            $db = getenv('DB_NAME') ?: 'atsede_db';
            $user = getenv('DB_USER') ?: 'root';
            $pass = getenv('DB_PASS') !== false ? getenv('DB_PASS') : '';
            $this->pdo = new PDO("mysql:host=$host;dbname=$db;charset=utf8mb4", $user, $pass, [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            ]);
        }
        return $this->pdo;
    }

    private function request(string $method, string $path, ?array $body = null, ?string $token = null, array $extraHeaders = []): array {
        $ch = curl_init($this->baseUrl . $path);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
        curl_setopt($ch, CURLOPT_TIMEOUT, 15);

        $headers = ['Accept: application/json'];
        if ($token) {
            $headers[] = "Authorization: Bearer $token";
        }
        foreach ($extraHeaders as $k => $v) {
            $headers[] = "$k: $v";
        }

        if ($body !== null) {
            $jsonData = json_encode($body);
            curl_setopt($ch, CURLOPT_POSTFIELDS, $jsonData);
            $headers[] = 'Content-Type: application/json';
        }

        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        $raw = curl_exec($ch);
        $statusCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        $json = json_decode($raw, true);
        return [
            'status' => $statusCode,
            'body' => $json,
            'raw' => $raw
        ];
    }

    private function record(string $testName, bool $passed, string $expected, string $actual, string $details = ''): void {
        $this->results[] = [
            'name' => $testName,
            'passed' => $passed,
            'expected' => $expected,
            'actual' => $actual,
            'details' => $details
        ];
        $mark = $passed ? "\033[32m[PASS]\033[0m" : "\033[31m[FAIL]\033[0m";
        echo sprintf("%-8s %-55s (Expected: %s, Got: %s)\n", $mark, $testName, $expected, $actual);
        if (!$passed && $details) {
            echo "         Details: $details\n";
        }
    }

    public function runAll(): void {
        echo "\n=================================================================\n";
        echo "   ዓጸደ ትጉሃን - ሁለገብ የደህንነት እና የፍቃድ ማረጋገጫ (Master Test Suite)\n";
        echo "=================================================================\n\n";

        $this->testUnauthenticatedAccess();
        $this->testInvalidToken();
        $this->testInvalidLogin();
        $this->testRateLimiting();
        $this->testValidLogin();
        $this->testDisabledUserTokenRevocation();
        $this->testPasswordChangeAndComplexity();
        $this->testUrlDepartmentOverrideBlocked();
        $this->testPlansRbacAndConcurrency();
        $this->testReportsWorkflowAndImmutability();
        $this->testChatRoomMembershipAndNotices();
        $this->testDocumentsRbacAndOverwritePrevention();
        $this->testNotificationsIdorProtection();
        $this->testFileDownloadSecurityAndRbac();
        $this->testMaliciousFileUpload();
        $this->testSyncSecurityAndIdempotency();
        $this->testLogoutAndTokenRevocation();

        $this->printSummary();
    }

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

    private function testInvalidToken(): void {
        echo "\n--- 2. የተሳሳተ ወይም የተበላሸ ቶከን ፍተሻ (Invalid/Forged Token) ---\n";
        $res = $this->request('GET', '/api/plans.php', null, 'forged.signature.token');
        $this->record("በተበላሸ ቶከን /api/plans.php መጠየቅ", $res['status'] === 401, "401 Unauthorized", (string)$res['status']);
    }

    private function testInvalidLogin(): void {
        echo "\n--- 3. የተሳሳተ የይለፍ ቃል ፍተሻ (Invalid Credentials) ---\n";
        $res = $this->request('POST', '/api/auth.php', [
            'username' => 'education',
            'password' => 'WrongPassword123!'
        ]);
        $this->record("በስህተት የይለፍ ቃል መግባት", $res['status'] === 401, "401 Unauthorized", (string)$res['status']);
    }

    private function testRateLimiting(): void {
        echo "\n--- 4. የብሩት ፎርስ መከላከያ ፍተሻ (Rate Limiting) ---\n";
        $hitRateLimit = false;
        $attemptStatus = 0;
        
        for ($i = 1; $i <= 6; $i++) {
            $res = $this->request('POST', '/api/auth.php', [
                'username' => 'attacker_bot_test',
                'password' => 'badpass_' . $i
            ], null, ['X-Forwarded-For' => '10.0.0.99']);
            
            if ($res['status'] === 429) {
                $hitRateLimit = true;
                $attemptStatus = 429;
                break;
            }
            $attemptStatus = $res['status'];
        }

        $this->record("ከተደጋጋሚ የስህተት ሙከራ በኋላ 429 Too Many Requests ማግኘት", $hitRateLimit, "429 Too Many Requests", (string)$attemptStatus);
    }

    private function testValidLogin(): void {
        echo "\n--- 5. ትክክለኛ መግቢያ እና የቶከን አሰጣጥ ፍተሻ (Valid Logins) ---\n";
        
        // 1. ትምህርት ክፍል
        $res1 = $this->request('POST', '/api/auth.php', [
            'username' => 'education',
            'password' => 'Atsede@2019Secure!'
        ]);
        $hasToken1 = !empty($res1['body']['data']['token'] ?? null);
        if ($hasToken1) $this->educationToken = $res1['body']['data']['token'];
        $this->record("የትምህርት ክፍል መግባት (education)", $res1['status'] === 200 && $hasToken1, "200 OK + Token", (string)$res1['status']);

        // 2. መዝሙር ክፍል
        $res2 = $this->request('POST', '/api/auth.php', [
            'username' => 'mezmur',
            'password' => 'Atsede@2019Secure!'
        ]);
        $hasToken2 = !empty($res2['body']['data']['token'] ?? null);
        if ($hasToken2) $this->mezmurToken = $res2['body']['data']['token'];
        $this->record("የመዝሙር ክፍል መግባት (mezmur)", $res2['status'] === 200 && $hasToken2, "200 OK + Token", (string)$res2['status']);

        // 3. ፅ/ቤት (Admin)
        $res3 = $this->request('POST', '/api/auth.php', [
            'username' => 'admin',
            'password' => 'Atsede@2019Secure!'
        ]);
        $hasToken3 = !empty($res3['body']['data']['token'] ?? null);
        if ($hasToken3) $this->adminToken = $res3['body']['data']['token'];
        $this->record("የፅ/ቤት አስተዳዳሪ መግባት (admin)", $res3['status'] === 200 && $hasToken3, "200 OK + Token", (string)$res3['status']);
    }

    private function testDisabledUserTokenRevocation(): void {
        echo "\n--- 6. የታገደ/የተሰናበተ ተጠቃሚ ቶከን ማሰናከያ ፍተሻ (Disabled User Check) ---\n";
        $pdo = $this->getPdo();

        // 1. መጀመሪያ በ hr ትክክለኛ መግቢያ በማድረግ ቶከን ማግኘት
        $resLogin = $this->request('POST', '/api/auth.php', [
            'username' => 'hr',
            'password' => 'Atsede@2019Secure!'
        ]);
        $hrToken = $resLogin['body']['data']['token'] ?? null;

        // 2. የሰው ኃይል (hr) ተጠቃሚን በዳታቤዝ suspend ማድረግ
        $pdo->query("UPDATE users SET status = 'suspended' WHERE username = 'hr'");

        // 3. በቀድሞው ቶከን ኤፒአይ ለመጠየቅ ሲሞከር መከልከሉ (401 Unauthorized)
        $resApi = $this->request('GET', '/api/plans.php', null, $hrToken);
        $this->record("የታገደ ተጠቃሚ (suspended) በቀድሞ ቶከን ሲጠይቅ መከልከሉ (401)", $resApi['status'] === 401, "401 Unauthorized", (string)$resApi['status']);

        // 4. በአዲሱ መግቢያም መከልከሉ (401)
        $resNewLogin = $this->request('POST', '/api/auth.php', [
            'username' => 'hr',
            'password' => 'Atsede@2019Secure!'
        ]);
        $this->record("የታገደ ተጠቃሚ (suspended) አዲስ መግቢያ ሲሞክር መከልከሉ (401)", $resNewLogin['status'] === 401, "401 Unauthorized", (string)$resNewLogin['status']);

        // 5. ሁኔታውን ወደ active መመለስ
        $pdo->query("UPDATE users SET status = 'active' WHERE username = 'hr'");
    }

    private function testPasswordChangeAndComplexity(): void {
        echo "\n--- 7. የይለፍ ቃል መቀየር እና የጥንካሬ ማረጋገጫ (Password Change) ---\n";
        
        // ደካማ የይለፍ ቃል (ያለ ቁጥር ወይም አጭር)
        $res1 = $this->request('POST', '/api/auth.php?action=change_password', [
            'old_password' => 'Atsede@2019Secure!',
            'new_password' => 'short'
        ], $this->educationToken);
        $this->record("ደካማ የይለፍ ቃል ሲቀርብ መከልከሉ (400)", $res1['status'] === 400, "400 Bad Request", (string)$res1['status']);

        // የተሳሳተ የድሮ የይለፍ ቃል
        $res2 = $this->request('POST', '/api/auth.php?action=change_password', [
            'old_password' => 'WrongOldPass123!',
            'new_password' => 'NewSecurePass2019!'
        ], $this->educationToken);
        $this->record("የድሮ የይለፍ ቃል ሲሳሳት መከልከሉ (400)", $res2['status'] === 400, "400 Bad Request", (string)$res2['status']);

        // ትክክለኛ የይለፍ ቃል ለውጥ
        $res3 = $this->request('POST', '/api/auth.php?action=change_password', [
            'old_password' => 'Atsede@2019Secure!',
            'new_password' => 'Atsede@2019Updated1!'
        ], $this->educationToken);
        $this->record("ትክክለኛ የይለፍ ቃል ለውጥ (200 OK)", $res3['status'] === 200, "200 OK", (string)$res3['status']);

        // ወደ ነባር መመለስ
        $this->request('POST', '/api/auth.php?action=change_password', [
            'old_password' => 'Atsede@2019Updated1!',
            'new_password' => 'Atsede@2019Secure!'
        ], $this->educationToken);
    }

    private function testUrlDepartmentOverrideBlocked(): void {
        echo "\n--- 8. በ URL Parameter የሚደረግ Cross-Dept ጥያቄ መከልከል (URL Override Blocked) ---\n";

        // 1. እቅዶች ላይ
        $res1 = $this->request('GET', '/api/plans.php?dept=mezmur', null, $this->educationToken);
        $this->record("የትምህርት ክፍል ?dept=mezmur እቅድ ሲጠይቅ መከልከሉ (403)", $res1['status'] === 403, "403 Forbidden", (string)$res1['status']);

        // 2. ሪፖርቶች ላይ
        $res2 = $this->request('GET', '/api/reports.php?dept=mezmur', null, $this->educationToken);
        $this->record("የትምህርት ክፍል ?dept=mezmur ሪፖርት ሲጠይቅ መከልከሉ (403)", $res2['status'] === 403, "403 Forbidden", (string)$res2['status']);

        // 3. ሰነዶች ላይ
        $res3 = $this->request('GET', '/api/documents.php?dept=mezmur', null, $this->educationToken);
        $this->record("የትምህርት ክፍል ?dept=mezmur ሰነድ ሲጠይቅ መከልከሉ (403)", $res3['status'] === 403, "403 Forbidden", (string)$res3['status']);
    }

    private function testPlansRbacAndConcurrency(): void {
        echo "\n--- 9. የእቅዶች RBAC እና Concurrency ፍተሻ (Plans Module) ---\n";

        // 1. የትምህርት ክፍል የራሱን እቅድ ይፈጥራል (201)
        $res1 = $this->request('POST', '/api/plans.php', [
            'title' => 'የ2019 ዓ.ም የትምህርት ጥራት ማሻሻያ ስልጠና',
            'description' => 'ለመምህራን የተዘጋጀ ሳምንታዊ ስልጠና',
            'department_id' => 'education',
            'priority' => 'high',
            'status' => 'pending'
        ], $this->educationToken);
        $this->createdPlanId = $res1['body']['data']['id'] ?? 0;
        $this->record("የትምህርት ክፍል የራሱን እቅድ መፍጠር (201)", $res1['status'] === 201 && !empty($this->createdPlanId), "201 Created", (string)$res1['status']);

        // 2. የትምህርት ክፍል በመዝሙር ስም እቅድ ሊፈጥር ሲሞክር (403)
        $res2 = $this->request('POST', '/api/plans.php', [
            'title' => 'ህገወጥ የመዝሙር ጥናት እቅድ',
            'department_id' => 'mezmur'
        ], $this->educationToken);
        $this->record("በሌላ ክፍል ስም እቅድ ሲፈጠር መከልከሉ (403)", $res2['status'] === 403, "403 Forbidden", (string)$res2['status']);

        // 3. የመዝሙር ክፍል የትምህርትን እቅድ ለማሻሻል ሲሞክር (403)
        $res3 = $this->request('PUT', '/api/plans.php', [
            'id' => $this->createdPlanId,
            'title' => 'የተጠለፈ እቅድ'
        ], $this->mezmurToken);
        $this->record("የመዝሙር ክፍል የትምህርት እቅድ ሲያሻሽል መከልከሉ (403)", $res3['status'] === 403, "403 Forbidden", (string)$res3['status']);

        // 4. ተራ ክፍል እቅድ ለመሰረዝ ሲሞክር (403)
        $res4 = $this->request('DELETE', "/api/plans.php?id={$this->createdPlanId}", null, $this->educationToken);
        $this->record("ተራ ክፍል እቅድ ሲሰርዝ መከልከሉ (Office Only - 403)", $res4['status'] === 403, "403 Forbidden", (string)$res4['status']);
    }

    private function testReportsWorkflowAndImmutability(): void {
        echo "\n--- 10. የሪፖርት የስራ ሂደት እና የማይቀየርበት ደህንነት (Reports Workflow) ---\n";

        // 1. የትምህርት ክፍል ሪፖርት ያቀርባል (201)
        $res1 = $this->request('POST', '/api/reports.php', [
            'title' => 'የጥቅምት ወር የትምህርት ክፍል አፈፃፀም ሪፖርት',
            'summary' => 'ስልጠናዎች በተሳካ ሁኔታ ተጠናቀዋል',
            'plan_id' => $this->createdPlanId,
            'report_period' => 'monthly'
        ], $this->educationToken);
        $this->createdReportId = $res1['body']['data']['id'] ?? 0;
        $this->record("የትምህርት ክፍል ሪፖርት ማቅረብ (201)", $res1['status'] === 201 && !empty($this->createdReportId), "201 Created", (string)$res1['status']);

        // 2. ተራ ክፍል ሪፖርት ለማጽደቅ ሲሞክር (403)
        $res2 = $this->request('POST', '/api/reports.php?action=review', [
            'id' => $this->createdReportId,
            'status' => 'approved',
            'comment' => 'ራሴን አጸደቅኩ'
        ], $this->educationToken);
        $this->record("ተራ ክፍል ሪፖርት ለማጽደቅ ሲሞክር መከልከሉ (403)", $res2['status'] === 403, "403 Forbidden", (string)$res2['status']);

        // 3. ፅ/ቤት ያለ አስተያየት ማሻሻያ ሲጠይቅ (400)
        $res3 = $this->request('POST', '/api/reports.php?action=review', [
            'id' => $this->createdReportId,
            'status' => 'revision_requested',
            'comment' => '' // ባዶ ምክንያት
        ], $this->adminToken);
        $this->record("ያለ አስተያየት ማሻሻያ ሲጠየቅ መከልከሉ (400)", $res3['status'] === 400, "400 Bad Request", (string)$res3['status']);

        // 4. ፅ/ቤት ሪፖርቱን ያጸድቃል (200)
        $res4 = $this->request('POST', '/api/reports.php?action=review', [
            'id' => $this->createdReportId,
            'status' => 'approved',
            'comment' => 'በፅ/ቤት የተረጋገጠ እና የጸደቀ'
        ], $this->adminToken);
        $this->record("የፅ/ቤት አስተዳዳሪ ሪፖርቱን ማጽደቁ (200)", $res4['status'] === 200, "200 OK", (string)$res4['status']);

        // 5. የጸደቀ ሪፖርት ላይ ተራ ክፍል ማሻሻያ እንዳያደርግ መከልከል (Approved Report Immutable - 403)
        $res5 = $this->request('POST', '/api/reports.php', [
            'id' => $this->createdReportId,
            'title' => 'የጸደቀ ሪፖርት ላይ የተደረገ ህገወጥ ለውጥ',
            'summary' => 'ቀድሞ የጸደቀውን ለመቀየር መሞከር'
        ], $this->educationToken);
        $this->record("የጸደቀ ሪፖርት ላይ ለውጥ ሲሞከር መከልከሉ (403)", $res5['status'] === 403, "403 Forbidden", (string)$res5['status']);
    }

    private function testChatRoomMembershipAndNotices(): void {
        echo "\n--- 11. የቻት ሩም አባልነት እና ይፋዊ መመሪያ ፈቃድ (Chat Module) ---\n";

        // 1. ተራ ክፍል ይፋዊ መመሪያ ሲልክ መከልከሉ (403)
        $res1 = $this->request('POST', '/api/chat.php', [
            'room' => 'general',
            'message' => 'ህገወጥ ይፋዊ መመሪያ',
            'is_official_notice' => 1
        ], $this->educationToken);
        $this->record("ተራ ክፍል ይፋዊ መመሪያ ሲልክ መከልከሉ (403)", $res1['status'] === 403, "403 Forbidden", (string)$res1['status']);

        // 2. ፅ/ቤት ይፋዊ መመሪያ ሲልክ (201)
        $res2 = $this->request('POST', '/api/chat.php', [
            'room' => 'general',
            'message' => 'በፅ/ቤት የተላለፈ ይፋዊ መመሪያ',
            'is_official_notice' => 1
        ], $this->adminToken);
        $this->record("ፅ/ቤት ይፋዊ መመሪያ ማስተላለፉ (201)", $res2['status'] === 201, "201 Created", (string)$res2['status']);

        // 3. ተራ ክፍል ወደ ፅ/ቤት የግል ሩም (office) መልእክት ለማየት ሲሞክር (403)
        $res3 = $this->request('GET', '/api/chat.php?channel=office', null, $this->educationToken);
        $this->record("ተራ ክፍል ወደ ፅ/ቤት የግል ሩም (office) ሲገባ መከልከሉ (403)", $res3['status'] === 403, "403 Forbidden", (string)$res3['status']);

        // 4. ተራ ክፍል ወደ ሌላ ክፍል ውስጣዊ ሩም (dept_mezmur) ሲገባ መከልከሉ (403)
        $res4 = $this->request('GET', '/api/chat.php?channel=dept_mezmur', null, $this->educationToken);
        $this->record("የትምህርት ክፍል ወደ dept_mezmur ሩም ሲገባ መከልከሉ (403)", $res4['status'] === 403, "403 Forbidden", (string)$res4['status']);
    }

    private function testDocumentsRbacAndOverwritePrevention(): void {
        echo "\n--- 12. የሰነዶች RBAC እና መደራረብ መከላከል (Documents Module) ---\n";

        // 1. የትምህርት ክፍል ሰነድ ማስቀመጥ (201)
        $res1 = $this->request('POST', '/api/documents.php', [
            'title' => 'የትምህርት ክፍል መተዳደሪያ ደንብ',
            'doc_type' => 'proposal',
            'department_id' => 'education'
        ], $this->educationToken);
        $this->createdDocId = $res1['body']['data']['id'] ?? 0;
        $this->record("የትምህርት ክፍል ሰነድ መፍጠር (201)", $res1['status'] === 201 && !empty($this->createdDocId), "201 Created", (string)$res1['status']);

        // 2. የመዝሙር ክፍል በዚያው ID ሰነዱን ሊተካ ሲሞክር (403)
        $res2 = $this->request('POST', '/api/documents.php', [
            'id' => $this->createdDocId,
            'title' => 'የተጠለፈ የሰነድ ርዕስ',
            'department_id' => 'mezmur'
        ], $this->mezmurToken);
        $this->record("የመዝሙር ክፍል የትምህርት ሰነድ ሊተካ ሲሞክር መከልከሉ (403)", $res2['status'] === 403, "403 Forbidden", (string)$res2['status']);

        // 3. የመዝሙር ክፍል የትምህርት ሰነድ ሊሰርዝ ሲሞክር (403)
        $res3 = $this->request('DELETE', "/api/documents.php?id={$this->createdDocId}", null, $this->mezmurToken);
        $this->record("የመዝሙር ክፍል የትምህርት ሰነድ ሲሰርዝ መከልከሉ (403)", $res3['status'] === 403, "403 Forbidden", (string)$res3['status']);

        // 4. የትምህርት ክፍል የራሱን ሰነድ ሲሰርዝ (200)
        $res4 = $this->request('DELETE', "/api/documents.php?id={$this->createdDocId}", null, $this->educationToken);
        $this->record("የትምህርት ክፍል የራሱን ሰነድ መሰረዙ (200)", $res4['status'] === 200, "200 OK", (string)$res4['status']);
    }

    private function testNotificationsIdorProtection(): void {
        echo "\n--- 13. የማሳወቂያ IDOR መከላከል ፍተሻ (Notifications Module) ---\n";
        $pdo = $this->getPdo();

        // ለመዝሙር ክፍል የግል ማሳወቂያ መፍጠር
        $notifId = 'notif_test_mezmur_' . uniqid();
        $pdo->prepare("INSERT INTO notifications (id, department_id, title, message, type) VALUES (?, 'mezmur', 'የመዝሙር ማሳወቂያ', 'የመዝሙር ክፍል ብቻ ያየዋል', 'announcement')")->execute([$notifId]);
        $this->mezmurNotifId = $notifId;

        // የትምህርት ክፍል ያንን ማሳወቂያ እንደተነበበ ለማድረግ ሲሞክር (IDOR Attack - 403)
        $res = $this->request('POST', '/api/notifications.php', ['id' => $this->mezmurNotifId], $this->educationToken);
        $this->record("የትምህርት ክፍል የመዝሙርን ማሳወቂያ ሊያነብ ሲሞክር መከልከሉ (403)", $res['status'] === 403, "403 Forbidden", (string)$res['status']);
    }

    private function testFileDownloadSecurityAndRbac(): void {
        echo "\n--- 14. የተጠበቀ የፋይል ማውረድ እና የክፍል ፈቃድ (File Download RBAC) ---\n";
        $pdo = $this->getPdo();

        // ለትምህርት ክፍል ሪፖርት አባሪ መፍጠር
        $attId = 'att_edu_test_' . uniqid();
        $testFileName = 'edu_secret_report.pdf';
        $dummyPath = 'api/uploads/' . $attId . '.pdf';
        file_put_contents(__DIR__ . '/../' . $dummyPath, '%PDF-1.4 dummy secret content');

        $pdo->prepare("INSERT INTO report_attachments (id, report_id, file_name, file_path, file_type, file_size) VALUES (?, ?, ?, ?, 'application/pdf', 100)")
            ->execute([$attId, $this->createdReportId, $testFileName, $dummyPath]);
        $this->createdAttachmentId = $attId;

        // 1. የመዝሙር ክፍል የትምህርት አባሪን ለማውረድ ሲሞክር (403 Forbidden)
        $res1 = $this->request('GET', "/api/files.php?id={$attId}", null, $this->mezmurToken);
        $this->record("የመዝሙር ክፍል የትምህርት ፋይል ሲጠይቅ መከልከሉ (403)", $res1['status'] === 403, "403 Forbidden", (string)$res1['status']);

        // 2. የትምህርት ክፍል የራሱን ፋይል ሲያወርድ (200 OK)
        $res2 = $this->request('GET', "/api/files.php?id={$attId}", null, $this->educationToken);
        $this->record("የትምህርት ክፍል የራሱን ፋይል ማውረዱ (200)", $res2['status'] === 200, "200 OK", (string)$res2['status']);

        // 3. የፅ/ቤት አስተዳዳሪ ፋይሉን ሲያወርድ (200 OK)
        $res3 = $this->request('GET', "/api/files.php?id={$attId}", null, $this->adminToken);
        $this->record("የፅ/ቤት አስተዳዳሪ ፋይሉን ማውረዱ (200)", $res3['status'] === 200, "200 OK", (string)$res3['status']);

        // ጊዜያዊ ፋይሉን ማጽዳት
        @unlink(__DIR__ . '/../' . $dummyPath);
    }

    private function testMaliciousFileUpload(): void {
        echo "\n--- 15. አደገኛ የፋይል ሰቀላ መከላከል ፍተሻ (Malicious Upload Blocked) ---\n";
        $cfile = new CURLFile(__FILE__, 'text/php', 'exploit_shell.php');
        
        $ch = curl_init($this->baseUrl . '/api/reports.php?action=upload');
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, ['file' => $cfile]);
        curl_setopt($ch, CURLOPT_HTTPHEADER, ["Authorization: Bearer " . $this->educationToken]);
        $raw = curl_exec($ch);
        $statusCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        $this->record("የ .php አደገኛ ፋይል ሰቀላ መከልከሉ (400)", $statusCode === 400, "400 Bad Request", (string)$statusCode);
    }

    private function testSyncSecurityAndIdempotency(): void {
        echo "\n--- 16. የከመስመር ውጭ ማመሳሰል እና የተባዛ መከላከል (Sync Module) ---\n";

        // 1. ያለ ቶከን ማመሳሰል (401)
        $res1 = $this->request('POST', '/api/sync.php', ['changes' => []]);
        $this->record("ያለ ቶከን /api/sync.php መጠየቅ (401)", $res1['status'] === 401, "401 Unauthorized", (string)$res1['status']);

        // 2. የሌላ ክፍል ዳታ በ sync መላክ (403)
        $res2 = $this->request('POST', '/api/sync.php', [
            'changes' => [
                [
                    'sync_id' => 'sync_fake_cross_' . uniqid(),
                    'entity_type' => 'plan',
                    'action' => 'insert',
                    'department_id' => 'mezmur',
                    'data' => ['title' => 'ህገወጥ sync']
                ]
            ]
        ], $this->educationToken);
        $this->record("በ sync ውስጥ የሌላ ክፍል ዳታ ሲላክ መከልከሉ (403)", $res2['status'] === 403, "403 Forbidden", (string)$res2['status']);

        // 3. ትክክለኛ ማመሳሰል እና የተባዛ sync_id መከላከል (Idempotency)
        $syncId = 'sync_edu_valid_' . uniqid();
        $payload = [
            'changes' => [
                [
                    'sync_id' => $syncId,
                    'entity_type' => 'plan',
                    'action' => 'insert',
                    'department_id' => 'education',
                    'data' => ['title' => 'ከመስመር ውጭ የተመዘገበ እቅድ']
                ]
            ]
        ];

        $res3 = $this->request('POST', '/api/sync.php', $payload, $this->educationToken);
        $res4 = $this->request('POST', '/api/sync.php', $payload, $this->educationToken);
        $passed = ($res3['status'] === 200 && ($res3['body']['data']['summary']['processed'] ?? 0) === 1)
               && ($res4['status'] === 200 && ($res4['body']['data']['summary']['skipped_duplicates'] ?? 0) === 1);

        $this->record("የማመሳሰል Idempotency እና የተባዛ መከላከል (Duplicate Skipped)", $passed, "200 OK (1 processed, 1 skipped)", "First: {$res3['status']}, Second: {$res4['status']}");
    }

    private function testLogoutAndTokenRevocation(): void {
        echo "\n--- 17. ቶከን ማሰናከያ ፍተሻ (Logout & Token Revocation) ---\n";

        // 1. መውጣት (Logout)
        $res1 = $this->request('POST', '/api/auth.php?action=logout', null, $this->mezmurToken);
        $this->record("የመዝሙር ክፍል ሎግአውት ማድረግ (200)", $res1['status'] === 200, "200 OK", (string)$res1['status']);

        // 2. ከተሰናከለ ቶከን በኋላ እንደገና መጠየቅ (401)
        $res2 = $this->request('GET', '/api/plans.php', null, $this->mezmurToken);
        $this->record("ከተሰናከለ ቶከን በኋላ መጠየቅ ሲከለከል (401)", $res2['status'] === 401, "401 Unauthorized", (string)$res2['status']);
    }

    private function printSummary(): void {
        $total = count($this->results);
        $passed = count(array_filter($this->results, fn($r) => $r['passed']));
        $failed = $total - $passed;

        echo "\n=================================================================\n";
        echo "   የሙከራው ማጠቃለያ ውጤት (Test Execution Summary)\n";
        echo "=================================================================\n";
        echo "  አጠቃላይ የተካሄዱ ሙከራዎች: $total\n";
        echo "  ያለፉ (PASSED): \033[32m$passed\033[0m\n";
        echo "  የወደቁ (FAILED): " . ($failed > 0 ? "\033[31m$failed\033[0m" : "\033[32m0\033[0m") . "\n";
        echo "=================================================================\n\n";

        if ($failed > 0) {
            echo "የወደቁ ሙከራዎች ዝርዝር:\n";
            foreach ($this->results as $r) {
                if (!$r['passed']) {
                    echo " - {$r['name']} (Expected: {$r['expected']}, Got: {$r['actual']})\n";
                }
            }
            exit(1);
        } else {
            echo "\033[32mእንኳን ደስ አለዎት! ሁሉም የደህንነት እና የፍቃድ ሙከራዎች 100% አልፈዋል።\033[0m\n";
            exit(0);
        }
    }
}

$tester = new MasterSecurityTester('http://127.0.0.1:8000');
$tester->runAll();
