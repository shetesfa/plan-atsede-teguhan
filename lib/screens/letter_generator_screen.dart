import 'package:flutter/material.dart';
import '../models/department.dart';
import '../models/official_letter.dart';
import '../services/pdf_generator_service.dart';
import '../services/telegram_service.dart';
import '../widgets/telegram_connect_dialog.dart';
import '../theme/app_theme.dart';

class LetterGeneratorScreen extends StatefulWidget {
  const LetterGeneratorScreen({super.key});

  @override
  State<LetterGeneratorScreen> createState() => _LetterGeneratorScreenState();
}

class _LetterGeneratorScreenState extends State<LetterGeneratorScreen> {
  final _formKey = GlobalKey<FormState>();

  // Audit M8: all fields start EMPTY. The old code pre-filled a real
  // dated letter about the library (a named recipient, full
  // body/remarks), which could be sent by accident with stale content.
  String senderDept = 'ትምህርት እና ስልጠና ክፍል';
  final dateController = TextEditingController();
  final recipientNameController = TextEditingController();
  final recipientDeptController = TextEditingController();
  final subjectController = TextEditingController();
  final bodyController = TextEditingController();
  final remarksController = TextEditingController();
  final signeeNameController = TextEditingController();
  final signeeTitleController = TextEditingController();
  final ccController = TextEditingController();

  bool isGenerating = false;

  Future<void> _generateLetter() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isGenerating = true);
    try {
      final ccItems = ccController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final letter = OfficialLetter(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderDepartment: senderDept,
        date: dateController.text.trim(),
        recipientName: recipientNameController.text.trim(),
        recipientDepartment: recipientDeptController.text.trim(),
        subject: subjectController.text.trim(),
        body: bodyController.text.trim(),
        remarks: remarksController.text.trim(),
        signeeName: signeeNameController.text.trim(),
        signeeTitle: signeeTitleController.text.trim(),
        ccList: ccItems,
      );

      final pdfBytes = await PdfGeneratorService.generateLetterPdf(letter);
      await PdfGeneratorService.printOrSharePdf(pdfBytes, 'አጸደ_ትጉሃን_ደብዳቤ.pdf');
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
      final ccItems = ccController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final letter = OfficialLetter(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderDepartment: senderDept,
        date: dateController.text.trim(),
        recipientName: recipientNameController.text.trim(),
        recipientDepartment: recipientDeptController.text.trim(),
        subject: subjectController.text.trim(),
        body: bodyController.text.trim(),
        remarks: remarksController.text.trim(),
        signeeName: signeeNameController.text.trim(),
        signeeTitle: signeeTitleController.text.trim(),
        ccList: ccItems,
      );

      final pdfBytes = await PdfGeneratorService.generateLetterPdf(letter);
      final caption = '<b>ይፋዊ ደብዳቤ</b>\n'
          '<b>ከ፦</b> $senderDept\n'
          '<b>ለ፦</b> ${recipientNameController.text.trim()} (${recipientDeptController.text.trim()})\n'
          '<b>ጉዳዩ፦</b> ${subjectController.text.trim()}\n'
          '<b>ቀን፦</b> ${dateController.text.trim()}';

      final success = await TelegramService.sendDocument(
        fileBytes: pdfBytes,
        fileName: 'ደብዳቤ_${senderDept.replaceAll(' ', '_')}.pdf',
        caption: caption,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ደብዳቤው በተሳካ ሁኔታ ወደ ቴሌግራም ተልኳል!'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('ይፋዊ ደብዳቤ መጻፊያ'),
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
                    Icon(Icons.info_outline, color: AppTheme.primaryMaroon, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'በዚህ ቅጽ የሞሉት ደብዳቤ በቀጥታ የአጸደ ትጉሃን አርማ እና ፎርማት ተካቶበት ወደ ይፋዊ PDF ይቀየራል።',
                        style: TextStyle(fontSize: 12, color: AppTheme.primaryMaroon),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // የላኪ ክፍል መራጭ
              const Text('የላኪው ክፍል (አዘጋጅ)፡', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: Department.allDepartments.any((d) => d.name == senderDept)
                    ? senderDept
                    : Department.allDepartments.first.name,
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                items: Department.allDepartments
                    .map((d) => DropdownMenuItem(value: d.name, child: Text(d.name, style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      senderDept = val;
                      signeeTitleController.text = '$val ኃላፊ';
                    });
                  }
                },
              ),
              const SizedBox(height: 14),

              // ቀን
              _buildTextField('ቀን (Date)፡', dateController, hint: 'ቀን/ወር/ዓመት ዓ.ም'),
              const SizedBox(height: 14),

              // ተቀባይ
              _buildTextField('ለማን (የተቀባይ ስም)፡', recipientNameController, hint: 'የተቀባይ ስም እዚህ ያስገቡ'),
              const SizedBox(height: 14),
              _buildTextField('የተቀባይ ክፍል / አገልግሎት፡', recipientDeptController, hint: 'የተቀባይ ክፍል እዚህ ያስገቡ'),
              const SizedBox(height: 14),

              // ጉዳዩ
              _buildTextField('ጉዳዩ (Subject)፡', subjectController, hint: 'የደብዳቤው ጉዳይ እዚህ ያስገቡ'),
              const SizedBox(height: 14),

              // ዝርዝር መልዕክት
              const Text('የደብዳቤው ዝርዝር መልዕክት፡', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              TextFormField(
                controller: bodyController,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'መልዕክትዎን እዚህ ያስገቡ...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(12),
                ),
                validator: (val) => val == null || val.isEmpty ? 'እባክዎ መልዕክት ያስገቡ' : null,
              ),
              const SizedBox(height: 14),

              // ማሳሰቢያ
              const Text('ማሳሰቢያ (አስፈላጊ ከሆነ)፡', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              TextFormField(
                controller: remarksController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'ማሳሰቢያ እዚህ ይጻፉ...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 14),

              // ፈራሚ
              Row(
                children: [
                  Expanded(child: _buildTextField('የኃላፊው ስም፡', signeeNameController, hint: 'ስም')),
                  const SizedBox(width: 10),
                  Expanded(child: _buildTextField('የኃላፊነት ማዕረግ፡', signeeTitleController, hint: 'ማዕረግ')),
                ],
              ),
              const SizedBox(height: 14),

              // ግልባጭ
              _buildTextField('ግልባጭ (cc) - በኮማ ይለዩ፡', ccController, hint: 'ለምሳሌ፦ ለሰንበት ትምህርት ቤቱ ጽ/ቤት'),
              const SizedBox(height: 24),

              // የ PDF ማመንጫ አዝራር
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: isGenerating ? null : _generateLetter,
                  icon: isGenerating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf),
                  label: Text(isGenerating ? 'ደብዳቤው እየተዘጋጀ ነው...' : 'ይፋዊ ደብዳቤ (PDF) አውጣ'),
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
                    isSendingTelegram ? 'ደብዳቤው ወደ ቴሌግራም እየተላከ ነው...' : 'ይፋዊ ደብዳቤውን ወደ ቴሌግራም ላክ',
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

  Widget _buildTextField(String label, TextEditingController controller, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
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
