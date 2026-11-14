import 'package:flutter/material.dart';
import '../models/department.dart';
import '../models/proposal.dart';
import '../services/pdf_generator_service.dart';
import '../services/telegram_service.dart';
import '../widgets/telegram_connect_dialog.dart';
import '../theme/app_theme.dart';

class ProposalGeneratorScreen extends StatefulWidget {
  const ProposalGeneratorScreen({super.key});

  @override
  State<ProposalGeneratorScreen> createState() => _ProposalGeneratorScreenState();
}

class _ProposalGeneratorScreenState extends State<ProposalGeneratorScreen> {
  final _formKey = GlobalKey<FormState>();

  // Audit M8: all fields start EMPTY. The old code pre-filled a real
  // dated Timket proposal (named preparer, sample budget),
  // which could be sent by accident with stale content.
  String department = 'ልማትና በጎ አድራጎት ክፍል';
  final titleController = TextEditingController();
  final dateController = TextEditingController();
  final objectiveController = TextEditingController();
  final locationDateController = TextEditingController();
  final activitiesController = TextEditingController();
  final manpowerController = TextEditingController();
  final preparedByNameController = TextEditingController();
  final preparedByTitleController = TextEditingController();

  List<BudgetItem> budgetItems = [];

  bool isGenerating = false;

  void _addBudgetItem() {
    final nameCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'ቁጥር');
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('አዲስ የበጀት ወጪ ጨምር', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'የእቃው / የአገልግሎቱ ስም')),
              Row(
                children: [
                  Expanded(child: TextField(controller: unitCtrl, decoration: const InputDecoration(labelText: 'መለኪያ'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ብዛት'))),
                ],
              ),
              TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ያንዱ ዋጋ (ብር)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ተው')),
            ElevatedButton(
              onPressed: () {
                final qty = double.tryParse(qtyCtrl.text) ?? 1.0;
                final price = double.tryParse(priceCtrl.text) ?? 0.0;
                if (nameCtrl.text.isNotEmpty) {
                  setState(() {
                    budgetItems.add(BudgetItem(
                      itemName: nameCtrl.text.trim(),
                      unit: unitCtrl.text.trim(),
                      quantity: qty,
                      unitPrice: price,
                    ));
                  });
                }
                Navigator.pop(ctx);
              },
              child: const Text('ጨምር'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _generateProposal() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isGenerating = true);
    try {
      final proposal = Proposal(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: titleController.text.trim(),
        departmentName: department,
        date: dateController.text.trim(),
        objective: objectiveController.text.trim(),
        targetLocationAndDate: locationDateController.text.trim(),
        activities: activitiesController.text.trim(),
        budgetItems: budgetItems,
        manpower: manpowerController.text.trim(),
        preparedByName: preparedByNameController.text.trim(),
        preparedByTitle: preparedByTitleController.text.trim(),
      );

      final pdfBytes = await PdfGeneratorService.generateProposalPdf(proposal);
      await PdfGeneratorService.printOrSharePdf(pdfBytes, 'አጸደ_ትጉሃን_ፕሮፖዛል.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ስህተት ተከስቷል፡ $e'), backgroundColor: AppTheme.redDanger),
        );
      }
    } finally {
      if (mounted) setState(() => isGenerating = false);
    }
  }

  bool isSendingTelegram = false;

  Future<void> _sendToTelegram() async {
    if (!_formKey.currentState!.validate()) return;

    if (TelegramService.savedChatId == null || TelegramService.savedChatId!.isEmpty) {
      final connected = await TelegramConnectDialog.show(context);
      if (!connected) return;
    }

    setState(() => isSendingTelegram = true);
    try {
      final proposal = Proposal(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: titleController.text.trim(),
        departmentName: department,
        date: dateController.text.trim(),
        objective: objectiveController.text.trim(),
        targetLocationAndDate: locationDateController.text.trim(),
        activities: activitiesController.text.trim(),
        budgetItems: budgetItems,
        manpower: manpowerController.text.trim(),
        preparedByName: preparedByNameController.text.trim(),
        preparedByTitle: preparedByTitleController.text.trim(),
      );

      final pdfBytes = await PdfGeneratorService.generateProposalPdf(proposal);
      final caption = '<b>ይፋዊ ፕሮፖዛል</b>\n'
          '<b>ርዕስ፦</b> ${titleController.text.trim()}\n'
          '<b>ክፍል፦</b> $department\n'
          '<b>ቀን፦</b> ${dateController.text.trim()}\n'
          '<b>አጠቃላይ በጀት፦</b> ${proposal.totalBudget.toStringAsFixed(2)} ብር';

      final success = await TelegramService.sendDocument(
        fileBytes: pdfBytes,
        fileName: 'ፕሮፖዛል_${department.replaceAll(' ', '_')}.pdf',
        caption: caption,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ፕሮፖዛሉ በተሳካ ሁኔታ ወደ ቴሌግራም ተልኳል!'),
              backgroundColor: AppTheme.greenSuccess,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ወደ ቴሌግራም መላክ አልተቻለም። እባክዎ ግንኙነቱን ያረጋግጡ።'),
              backgroundColor: AppTheme.redDanger,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ስህተት ተከስቷል፡ $e'), backgroundColor: AppTheme.redDanger),
        );
      }
    } finally {
      if (mounted) setState(() => isSendingTelegram = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grandTotal = budgetItems.fold(0.0, (sum, i) => sum + i.totalPrice);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ይፋዊ ፕሮፖዛል ማዘጋጃ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.telegram, color: Colors.white),
            tooltip: 'የቴሌግራም ማገናኛ',
            onPressed: () => TelegramConnectDialog.show(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // መመሪያ ባነር
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.lightGold,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.secondaryGold.withAlpha(128)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.description, color: AppTheme.primaryMaroon, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'ለበዓላት፣ ለጉዞዎች ወይም ለስልጠናዎች የሚሆን ይፋዊ ፕሮፖዛል በበጀት ሰንጠረዥ እና በአጸደ ትጉሃን አርማ ወደ PDF ያዘጋጁ።',
                        style: TextStyle(fontSize: 12, color: AppTheme.primaryMaroon),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ክፍል
              const Text('አዘጋጅ ክፍል፡', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: Department.allDepartments.where((d) => !d.isSuperAdmin).any((d) => d.name == department)
                    ? department
                    : Department.allDepartments.firstWhere((d) => !d.isSuperAdmin).name,
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                items: Department.allDepartments
                    .where((d) => !d.isSuperAdmin)
                    .map((d) => DropdownMenuItem(value: d.name, child: Text(d.name, style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      department = val;
                      preparedByTitleController.text = '$val ኃላፊ';
                    });
                  }
                },
              ),
              const SizedBox(height: 14),

              _buildField('የፕሮፖዛሉ ርዕስ፡', titleController, hint: 'የፕሮፖዛሉ ርዕስ እዚህ ያስገቡ'),
              const SizedBox(height: 14),

              _buildField('ቀን፡', dateController, hint: 'ቀን/ወር/ዓመት ዓ.ም'),
              const SizedBox(height: 14),

              _buildField('፩. የመርሃግብሩ / የፕሮጀክቱ ዓላማ፡', objectiveController, maxLines: 3, hint: 'ዓላማውን እዚህ ያስገቡ'),
              const SizedBox(height: 14),

              _buildField('፪. የክንውን ጊዜ እና ቦታ፡', locationDateController, hint: 'ጊዜ እና ቦታ እዚህ ያስገቡ'),
              const SizedBox(height: 14),

              _buildField('፫. ዝርዝር ተግባራት እና አፈፃፀም፡', activitiesController, maxLines: 4, hint: 'ተግባራትን እዚህ ያስገቡ'),
              const SizedBox(height: 18),

              // የበጀት ሰንጠረዥ
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('፬. የሚያስፈልግ በጀት እና ቁሳቁስ፡', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  TextButton.icon(
                    onPressed: _addBudgetItem,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('እቃ ጨምር'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    ...budgetItems.asMap().entries.map((e) {
                      final item = e.value;
                      return ListTile(
                        dense: true,
                        title: Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text('${item.quantity.toInt()} ${item.unit} x ${item.unitPrice.toStringAsFixed(0)} ብር'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${item.totalPrice.toStringAsFixed(0)} ብር',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryMaroon),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                              onPressed: () => setState(() => budgetItems.removeAt(e.key)),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('ጠቅላላ ድምር በጀት፡', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(
                            '${grandTotal.toStringAsFixed(2)} ብር',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryMaroon),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              _buildField('፭. የሚያስፈልግ የሰው ኃይል፡', manpowerController, hint: 'የሚያስፈልገውን የሰው ኃይል እዚህ ያስገቡ'),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(child: _buildField('አዘጋጅ ስም፡', preparedByNameController, hint: 'ስም')),
                  const SizedBox(width: 10),
                  Expanded(child: _buildField('ኃላፊነት፡', preparedByTitleController, hint: 'ማዕረግ')),
                ],
              ),
              const SizedBox(height: 24),

              // Export Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: isGenerating ? null : _generateProposal,
                  icon: isGenerating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf),
                  label: Text(isGenerating ? 'ፕሮፖዛሉ እየተዘጋጀ ነው...' : 'ይፋዊ ፕሮፖዛል (PDF) አውጣ'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryMaroon),
                ),
              ),
              const SizedBox(height: 12),

              // ወደ ቴሌግራም መላኪያ አዝራር
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: isSendingTelegram ? null : _sendToTelegram,
                  icon: isSendingTelegram
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded, color: Color(0xFF0088CC)),
                  label: Text(
                    isSendingTelegram ? 'ፕሮፖዛሉ ወደ ቴሌግራም እየተላከ ነው...' : 'ይፋዊ ፕሮፖዛሉን ወደ ቴሌግራም ላክ',
                    style: const TextStyle(color: Color(0xFF0088CC), fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF0088CC), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, {int maxLines = 1, String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          validator: (val) => val == null || val.isEmpty ? 'ይህ ሜዳ መሞላት አለበት' : null,
        ),
      ],
    );
  }
}
