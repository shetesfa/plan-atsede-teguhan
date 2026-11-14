<?php
// በአጸደ ትጉሃን አገልጋይ uploads ማውጫ ውስጥ ያሉ ፋይሎችን በቀጥታ በድር አሳሽ ማግኘት በጥብቅ የተከለከለ ነው
// ሁሉም ፋይሎች በ api/files.php ኤንድፖይንት በኩል ፈቃድ ተረጋግጦ ብቻ ይወርዳሉ
http_response_code(403);
echo json_encode(['status' => 'error', 'message' => 'የተከለከለ መዳረሻ (Forbidden). ፋይሎችን ለማግኘት api/files.php ይጠቀሙ።'], JSON_UNESCAPED_UNICODE);
exit;
