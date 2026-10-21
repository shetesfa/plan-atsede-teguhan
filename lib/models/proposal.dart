class BudgetItem {
  final String itemName;
  final String unit;
  final double quantity;
  final double unitPrice;

  BudgetItem({
    required this.itemName,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
  });

  double get totalPrice => quantity * unitPrice;

  Map<String, dynamic> toJson() => {
        'itemName': itemName,
        'unit': unit,
        'quantity': quantity,
        'unitPrice': unitPrice,
      };

  factory BudgetItem.fromJson(Map<String, dynamic> json) => BudgetItem(
        itemName: json['itemName'] ?? '',
        unit: json['unit'] ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
      );
}

class Proposal {
  final String id;
  final String title;
  final String departmentName;
  final String date;
  final String objective;
  final String targetLocationAndDate;
  final String activities;
  final List<BudgetItem> budgetItems;
  final String manpower;
  final String preparedByName;
  final String preparedByTitle;
  final String approvalStatus; // በመጠባበቅ ላይ, ጸድቋል, ውድቅ ተደርጓል
  final String secretariatNote;

  Proposal({
    required this.id,
    required this.title,
    required this.departmentName,
    required this.date,
    required this.objective,
    required this.targetLocationAndDate,
    required this.activities,
    required this.budgetItems,
    required this.manpower,
    required this.preparedByName,
    required this.preparedByTitle,
    this.approvalStatus = 'በመጠባበቅ ላይ',
    this.secretariatNote = '',
  });

  double get grandTotalBudget {
    return budgetItems.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  double get totalBudget => grandTotalBudget;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'departmentName': departmentName,
        'date': date,
        'objective': objective,
        'targetLocationAndDate': targetLocationAndDate,
        'activities': activities,
        'budgetItems': budgetItems.map((e) => e.toJson()).toList(),
        'manpower': manpower,
        'preparedByName': preparedByName,
        'preparedByTitle': preparedByTitle,
        'approvalStatus': approvalStatus,
        'secretariatNote': secretariatNote,
      };

  factory Proposal.fromJson(Map<String, dynamic> json) => Proposal(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        departmentName: json['departmentName'] ?? '',
        date: json['date'] ?? '',
        objective: json['objective'] ?? '',
        targetLocationAndDate: json['targetLocationAndDate'] ?? '',
        activities: json['activities'] ?? '',
        budgetItems: (json['budgetItems'] as List? ?? [])
            .map((e) => BudgetItem.fromJson(e))
            .toList(),
        manpower: json['manpower'] ?? '',
        preparedByName: json['preparedByName'] ?? '',
        preparedByTitle: json['preparedByTitle'] ?? '',
        approvalStatus: json['approvalStatus'] ?? 'በመጠባበቅ ላይ',
        secretariatNote: json['secretariatNote'] ?? '',
      );
}
