class UnplannedActivity {
  final String id;
  final String departmentId;
  final String departmentName;
  final String title;
  final String description;
  final String executionDate;
  final String budgetUsed;
  final String? evidencePath;
  final DateTime submittedAt;
  String status; // ተመዝግቧል, በፅ/ቤት ጸድቋል
  String secretariatNote;
  // 2026-11-26: server storage — the row carries a photo when the
  // evidence bytes live in the DB (download via files.php?id=<activity id>).
  final bool hasEvidence;

  UnplannedActivity({
    required this.id,
    required this.departmentId,
    required this.departmentName,
    required this.title,
    required this.description,
    required this.executionDate,
    required this.budgetUsed,
    this.evidencePath,
    DateTime? submittedAt,
    this.status = 'ተመዝግቧል',
    this.secretariatNote = '',
    this.hasEvidence = false,
  }) : submittedAt = submittedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'departmentId': departmentId,
        'departmentName': departmentName,
        'title': title,
        'description': description,
        'executionDate': executionDate,
        'budgetUsed': budgetUsed,
        'evidencePath': evidencePath,
        'submittedAt': submittedAt.toIso8601String(),
        'status': status,
        'secretariatNote': secretariatNote,
      };

  factory UnplannedActivity.fromJson(Map<String, dynamic> json) =>
      UnplannedActivity(
        id: json['id'] ?? '',
        departmentId: json['departmentId'] ?? '',
        departmentName: json['departmentName'] ?? '',
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        executionDate: json['executionDate'] ?? '',
        budgetUsed: json['budgetUsed'] ?? '',
        evidencePath: json['evidencePath'],
        submittedAt: json['submittedAt'] != null
            ? DateTime.tryParse(json['submittedAt'])
            : null,
        status: json['status'] ?? 'ተመዝግቧል',
        secretariatNote: json['secretariatNote'] ?? '',
      );

  /// From a server row (api/unplanned.php — snake_case keys).
  /// evidencePath stays null for server rows: the photo itself is never
  /// inlined in list responses; hasEvidence says whether one exists.
  factory UnplannedActivity.fromDbJson(Map<String, dynamic> json) =>
      UnplannedActivity(
        id: json['id'] ?? '',
        departmentId: json['department_id'] ?? '',
        departmentName: json['department_name'] ?? '',
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        executionDate: json['execution_date'] ?? '',
        budgetUsed: json['budget_used'] ?? '',
        submittedAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'])
            : null,
        status: json['status'] ?? 'ተመዝግቧል',
        secretariatNote: json['secretariat_note'] ?? '',
        hasEvidence:
            json['has_evidence'] == true || json['has_evidence'] == 1,
      );

  /// Body for POST/PUT to api/unplanned.php (snake_case keys).
  /// The evidence photo is sent separately as base64 (evidence_base64 +
  /// evidence_name) — it is never part of this map.
  Map<String, dynamic> toServerJson() => {
        'department_id': departmentId,
        'department_name': departmentName,
        'title': title,
        'description': description,
        'execution_date': executionDate,
        'budget_used': budgetUsed,
        'status': status,
        'secretariat_note': secretariatNote,
      };
}
