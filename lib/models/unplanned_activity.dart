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
}
