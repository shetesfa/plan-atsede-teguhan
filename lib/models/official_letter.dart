class OfficialLetter {
  final String id;
  final String senderDepartment;
  final String date;
  final String recipientName;
  final String recipientDepartment;
  final String subject;
  final String body;
  final String remarks;
  final String signeeName;
  final String signeeTitle;
  final List<String> ccList;
  final DateTime createdAt;

  OfficialLetter({
    required this.id,
    required this.senderDepartment,
    required this.date,
    required this.recipientName,
    required this.recipientDepartment,
    required this.subject,
    required this.body,
    required this.remarks,
    required this.signeeName,
    required this.signeeTitle,
    required this.ccList,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderDepartment': senderDepartment,
      'date': date,
      'recipientName': recipientName,
      'recipientDepartment': recipientDepartment,
      'subject': subject,
      'body': body,
      'remarks': remarks,
      'signeeName': signeeName,
      'signeeTitle': signeeTitle,
      'ccList': ccList,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory OfficialLetter.fromJson(Map<String, dynamic> json) {
    return OfficialLetter(
      id: json['id'] ?? '',
      senderDepartment: json['senderDepartment'] ?? '',
      date: json['date'] ?? '',
      recipientName: json['recipientName'] ?? '',
      recipientDepartment: json['recipientDepartment'] ?? '',
      subject: json['subject'] ?? '',
      body: json['body'] ?? '',
      remarks: json['remarks'] ?? '',
      signeeName: json['signeeName'] ?? '',
      signeeTitle: json['signeeTitle'] ?? '',
      ccList: List<String>.from(json['ccList'] ?? []),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
    );
  }
}
