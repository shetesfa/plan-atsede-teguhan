class PlanItem {
  final String id;
  String departmentId;
  String departmentName;
  String subDepartment;
  String mainTask;
  String detailTask;
  String measurement;
  String quantity;
  String executionTime;
  String budget;
  String remarks;
  Map<String, String> months; // {'መስ': '10', 'ጥቅ': '', ...}

  int progressPercent; // 0, 25, 50, 75, 100
  String reason; // ያልተከናወነበት ምክንያት (አጠቃላይ)
  String? evidencePath; // ፎቶ/ሰነድ ማስረጃ
  DateTime? updatedAt;

  // የእቅድ ማስተላለፍ (Postpone / Reschedule) መረጃዎች
  String? postponedDate; // የተላለፈበት አዲስ ቀን
  String? postponeReason; // የተላለፈበት ምክንያት

  // የተሟላ የእቅድ ክንውን ሪፖርት (Detailed Execution & Shortfall Report)
  String? reportDetails; // የተከናወኑ ስራዎች ዝርዝር
  String? notDoneDetails; // ያልተከናወኑ ስራዎች እና ያልተሰራበት ምክንያት
  DateTime? reportSubmittedAt; // ሪፖርት የቀረበበት ቀን
  String? submittedBy; // ሪፖርቱን ያቀረበው ኃላፊ/አካል

  PlanItem({
    required this.id,
    required this.departmentId,
    required this.departmentName,
    required this.subDepartment,
    required this.mainTask,
    required this.detailTask,
    required this.measurement,
    required this.quantity,
    required this.executionTime,
    required this.budget,
    required this.remarks,
    Map<String, String>? months,
    this.progressPercent = 0,
    this.reason = '',
    this.evidencePath,
    this.updatedAt,
    this.postponedDate,
    this.postponeReason,
    this.reportDetails,
    this.notDoneDetails,
    this.reportSubmittedAt,
    this.submittedBy,
  }) : months = months ?? {};

  bool get isCompleted => progressPercent == 100;
  bool get isInProgress => progressPercent > 0 && progressPercent < 100;
  bool get isNotStarted => progressPercent == 0;

  bool get isPostponed => postponedDate != null && postponedDate!.trim().isNotEmpty;
  bool get hasReport =>
      (reportDetails != null && reportDetails!.trim().isNotEmpty) ||
      (notDoneDetails != null && notDoneDetails!.trim().isNotEmpty) ||
      reportSubmittedAt != null;

  String get effectiveExecutionTime =>
      isPostponed ? '$executionTime (👉 የተላለፈበት፦ $postponedDate)' : executionTime;

  PlanItem copyWith({
    String? id,
    String? departmentId,
    String departmentName = '',
    String? subDepartment,
    String? mainTask,
    String? detailTask,
    String? measurement,
    String? quantity,
    String? executionTime,
    String? budget,
    String? remarks,
    Map<String, String>? months,
    int? progressPercent,
    String? reason,
    String? evidencePath,
    DateTime? updatedAt,
    String? postponedDate,
    String? postponeReason,
    String? reportDetails,
    String? notDoneDetails,
    DateTime? reportSubmittedAt,
    String? submittedBy,
  }) {
    return PlanItem(
      id: id ?? this.id,
      departmentId: departmentId ?? this.departmentId,
      departmentName: departmentName.isNotEmpty ? departmentName : this.departmentName,
      subDepartment: subDepartment ?? this.subDepartment,
      mainTask: mainTask ?? this.mainTask,
      detailTask: detailTask ?? this.detailTask,
      measurement: measurement ?? this.measurement,
      quantity: quantity ?? this.quantity,
      executionTime: executionTime ?? this.executionTime,
      budget: budget ?? this.budget,
      remarks: remarks ?? this.remarks,
      months: months ?? this.months,
      progressPercent: progressPercent ?? this.progressPercent,
      reason: reason ?? this.reason,
      evidencePath: evidencePath ?? this.evidencePath,
      updatedAt: updatedAt ?? this.updatedAt,
      postponedDate: postponedDate ?? this.postponedDate,
      postponeReason: postponeReason ?? this.postponeReason,
      reportDetails: reportDetails ?? this.reportDetails,
      notDoneDetails: notDoneDetails ?? this.notDoneDetails,
      reportSubmittedAt: reportSubmittedAt ?? this.reportSubmittedAt,
      submittedBy: submittedBy ?? this.submittedBy,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'departmentId': departmentId,
      'departmentName': departmentName,
      'subDepartment': subDepartment,
      'mainTask': mainTask,
      'detailTask': detailTask,
      'measurement': measurement,
      'quantity': quantity,
      'executionTime': executionTime,
      'budget': budget,
      'remarks': remarks,
      'months': months,
      'progressPercent': progressPercent,
      'reason': reason,
      'evidencePath': evidencePath,
      'updatedAt': updatedAt?.toIso8601String(),
      'postponedDate': postponedDate,
      'postponeReason': postponeReason,
      'reportDetails': reportDetails,
      'notDoneDetails': notDoneDetails,
      'reportSubmittedAt': reportSubmittedAt?.toIso8601String(),
      'submittedBy': submittedBy,
    };
  }

  factory PlanItem.fromJson(Map<String, dynamic> json) {
    Map<String, String> parsedMonths = {};
    if (json['months'] != null && json['months'] is Map) {
      (json['months'] as Map).forEach((k, v) {
        parsedMonths[k.toString()] = v?.toString() ?? '';
      });
    }

    return PlanItem(
      id: json['id'] ?? '',
      departmentId: json['departmentId'] ?? '',
      departmentName: json['departmentName'] ?? '',
      subDepartment: json['subDepartment'] ?? '',
      mainTask: json['mainTask'] ?? '',
      detailTask: json['detailTask'] ?? '',
      measurement: json['measurement'] ?? '',
      quantity: json['quantity'] ?? '',
      executionTime: json['executionTime'] ?? '',
      budget: json['budget'] ?? '',
      remarks: json['remarks'] ?? '',
      months: parsedMonths,
      progressPercent: json['progressPercent'] ?? 0,
      reason: json['reason'] ?? '',
      evidencePath: json['evidencePath'],
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
      postponedDate: json['postponedDate'],
      postponeReason: json['postponeReason'],
      reportDetails: json['reportDetails'],
      notDoneDetails: json['notDoneDetails'],
      reportSubmittedAt: json['reportSubmittedAt'] != null
          ? DateTime.tryParse(json['reportSubmittedAt'])
          : null,
      submittedBy: json['submittedBy'],
    );
  }
}
