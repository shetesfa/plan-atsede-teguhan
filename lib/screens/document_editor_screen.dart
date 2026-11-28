import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/department.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/file_download.dart';
import '../theme/app_theme.dart';
import '../widgets/telegram_connect_dialog.dart';

class DocumentEditorScreen extends StatefulWidget {
  const DocumentEditorScreen({super.key});

  @override
  State<DocumentEditorScreen> createState() => _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends State<DocumentEditorScreen> {

  bool isChurchMode = true; // ነባሪው ይፋዊ ሰንበት ት/ቤት ነው

  // አጠቃላይ መረጃ
  final orgOrHeaderCtrl = TextEditingController(text: 'ዐጸደ ትጉሃን ሰንበት ትምህርት ቤት');
  // PR #46: this used to be a hardcoded department NAME
  // ('ትምህርት እና ስልጠና ክፍል') sent as department_id. The server takes
  // the value verbatim for the office, so office saves were filed under
  // a bogus department id no filter could ever find. It is now a real
  // department ID (the user's own dept, or the office's pick below).
  String selectedDept = 'education';
  final dateCtrl = TextEditingController(text: '14/02/2019 ዓ.ም');
  final authorCtrl = TextEditingController(text: 'ተስፋሁን ባይህ');
  final authorRoleCtrl = TextEditingController(text: 'የትምህርት ኃላፊ');

  // Word ታብ ተቆጣጣሪዎች
  final wordTitleCtrl = TextEditingController(text: 'የስራ ክንውን እና እንቅስቃሴ ማስታወሻ');
  final wordIntroCtrl = TextEditingController(text: 'ለሚመለከተው አካል በሙሉ፦\nይህ ሰነድ የሚከተሉትን ዋና ዋና ተግባራትና ጉዳዮች ያብራራል።');
  final wordBodyCtrl = TextEditingController(
      text: 'በዚህ የስራ ወቅት የታቀዱ ተግባራት በተሳካ ሁኔታ የተከናወኑ ሲሆን፣ የግብዓት ዝግጅት እና የስራ አፈፃፀም ክትትል ተጠናክሮ ቀጥሏል።');
  final wordPointsCtrl = TextEditingController(
      text: '• ዋና የስራ አፈፃፀም ግምገማ ተካሂዷል\n• የበጀት እና የግብዓት አጠቃቀም ተረጋግጧል\n• የቀጣይ እቅዶች ዝግጅት ተጠናቋል');
  final wordConclusionCtrl = TextEditingController(
      text: 'ይህ ሰነድ ለቀጣይ ውሳኔ እና የስራ ክትትል እንዲያገለግል በአክብሮት ቀርቧል።');

  bool isGenerating = false;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    // A department user always saves under their own department; the
    // office picks the department in the meta header (default education).
    final current = AuthService.currentDepartment;
    if (current != null && !current.isSuperAdmin) {
      selectedDept = current.id;
    }
  }

  /// Departments the save can be filed under: the office picks any
  /// department; a department user is locked to their own.
  List<Department> get _deptChoices {
    if (AuthService.isSuperAdmin) {
      return Department.allDepartments.where((d) => !d.isSuperAdmin).toList();
    }
    final current = AuthService.currentDepartment;
    return current != null ? [current] : <Department>[];
  }

  String _deptName(String id) => Department.allDepartments
      .firstWhere(
        (d) => d.id == id,
        orElse: () => Department.allDepartments.first,
      )
      .name;

  @override
  void dispose() {
    orgOrHeaderCtrl.dispose();
    dateCtrl.dispose();
    authorCtrl.dispose();
    authorRoleCtrl.dispose();
    wordTitleCtrl.dispose();
    wordIntroCtrl.dispose();
    wordBodyCtrl.dispose();
    wordPointsCtrl.dispose();
    wordConclusionCtrl.dispose();
    super.dispose();
  }

  // 3. ሰነዱን በባክኤንድ ማህደር ማስቀመጥ (Save to Documents Archive)
  /// እውነተኛ PDF ማመንጨት (2026-11-26) — ከዚህ በፊት ያለው ቁልፍ "ተከናውኗል"
  /// ብሎ ያሳይ ነበር ግን PDF አያደርግም ነበር። አሁን የቤተክርስቲያኗን አርማና
  /// ማርቆ የያዘ እውነተኛ PDF ይፈጥራል እና የShare መስኮት ይከፍታል።
  Future<void> _exportWordPdf() async {
    setState(() => isGenerating = true);
    try {
      final fontData = await rootBundle.load('assets/nyala.ttf');
      final font = pw.Font.ttf(fontData);
      final logoData = await rootBundle.load('assets/icon.png');
      final logo = pw.MemoryImage(logoData.buffer.asUint8List());

      final title = wordTitleCtrl.text.trim();
      final points = wordPointsCtrl.text
          .split('\n')
          .map((l) => l.trim().replaceFirst(RegExp(r'^[•\-\*]\s*'), ''))
          .where((l) => l.isNotEmpty)
          .toList();
      final bodyLines = wordBodyCtrl.text
          .trim()
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(base: font, bold: font),
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(36),
          build: (context) => [
            pw.Row(
              children: [
                pw.Image(logo, width: 48, height: 48),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        orgOrHeaderCtrl.text.trim(),
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('7A1321'),
                        ),
                      ),
                      pw.Text(
                        'ይፋዊ ሰነድ',
                        style: pw.TextStyle(
                          fontSize: 11,
                          color: PdfColor.fromHex('D4AF37'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.Divider(color: PdfColor.fromHex('D4AF37'), thickness: 2),
            pw.SizedBox(height: 12),
            pw.Text(
              title.isEmpty ? 'ይፋዊ ሰነድ' : title,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'ቀን፦ ${dateCtrl.text.trim()}    |    ${authorCtrl.text.trim()} (${authorRoleCtrl.text.trim()})',
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 14),
            if (wordIntroCtrl.text.trim().isNotEmpty)
              pw.Text(
                wordIntroCtrl.text.trim(),
                style: const pw.TextStyle(fontSize: 12),
              ),
            if (bodyLines.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              ...bodyLines.map(
                (l) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Text(l, style: const pw.TextStyle(fontSize: 12)),
                ),
              ),
            ],
            if (points.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              ...points.map(
                (p) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('• ', style: const pw.TextStyle(fontSize: 12)),
                      pw.Expanded(
                        child: pw.Text(p, style: const pw.TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (wordConclusionCtrl.text.trim().isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                wordConclusionCtrl.text.trim(),
                style: const pw.TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      );

      final bytes = await doc.save();
      final fileName = '${title.isEmpty ? 'ሰነድ' : title}.pdf';
      // PR #46: Printing.sharePdf on the web only opens the browser's
      // print dialog — the "ወደ PDF አውርድ" button looked dead because no
      // download ever happened. On the web, download the file for real;
      // on mobile the share sheet still applies.
      if (kIsWeb) {
        final ok = await downloadBytes(bytes: bytes, fileName: fileName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ok ? 'PDF ወርዷል!' : 'PDF ማውረድ አልተቻለም!',
              ),
              backgroundColor:
                  ok ? AppTheme.greenSuccess : AppTheme.redDanger,
            ),
          );
        }
      } else {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF ማመንጨት አልተቻለም፦ $e'),
            backgroundColor: AppTheme.redDanger,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isGenerating = false);
    }
  }

  Future<void> _saveDocumentToArchive() async {
    setState(() => isSaving = true);
    try {
      final payload = {
        'id': 'doc_${DateTime.now().millisecondsSinceEpoch}',
        'department_id': selectedDept,
        'doc_type': 'letter',
        'title': wordTitleCtrl.text.trim(),
        'date': dateCtrl.text.trim(),
        'content': {
          'title': wordTitleCtrl.text,
          'intro': wordIntroCtrl.text,
          'body': wordBodyCtrl.text,
          'points': wordPointsCtrl.text,
          'conclusion': wordConclusionCtrl.text,
        },
      };

      final messenger = ScaffoldMessenger.of(context);
      // M12፦ ሰነዶች ወደ documents.php ይላካሉ (ወደ plans.php አይደሉም) እና ውጤቱ
      // ከመፈተሹ በፊት "ተቀምጧል" መልእክት አይታይም።
      final result = await ApiService().saveDocument(payload);
      if (mounted) {
        if (result['success'] == true) {
          // PR #46: the save used to show only a brief snackbar, so
          // tapping "በማህደር አስቀምጥ" looked like nothing happened. A
          // confirmation dialog now shows the saved title + department.
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('ሰነዱ ተቀምጧል', style: TextStyle(fontSize: 16)),
              content: Text(
                '«${wordTitleCtrl.text.trim().isEmpty ? 'ሰነድ' : wordTitleCtrl.text.trim()}»\nክፍል፦ ${_deptName(selectedDept)}\n\nሰነዱ በማህደር በተሳካ ሁኔታ ተቀምጧል።',
                style: const TextStyle(fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('ዝጋ'),
                ),
              ],
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text('ሰነዱን ማስቀመጥ አልተቻለም፦ ${result['message'] ?? 'ያልታወቀ ስህተት'}'),
              backgroundColor: AppTheme.redDanger,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ማስቀመጥ አልተቻለም፦ $e'), backgroundColor: AppTheme.redDanger),
        );
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('የሰነዶች የስራ ቦታ (Workspace)'),
        backgroundColor: AppTheme.primaryMaroon,
        foregroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            tooltip: 'በማህደር አስቀምጥ',
            icon: isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            onPressed: isSaving ? null : _saveDocumentToArchive,
          ),
          IconButton(
            tooltip: 'ወደ ቴሌግራም አገናኝ',
            icon: const Icon(Icons.send_rounded),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => const TelegramConnectDialog(),
              );
            },
          ),
        ],
      ),
      body: _buildWordEditorTab(),
    );
  }

  Widget _buildWordEditorTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMetaHeaderCard(),
          const SizedBox(height: 16),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('የሰነዱ ርዕስ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: wordTitleCtrl,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.title, color: AppTheme.primaryMaroon),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('መግቢያ (Introduction)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: wordIntroCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('ዋናው የሰነዱ ዝርዝር ሃሳብ (Body)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: wordBodyCtrl,
                    maxLines: 5,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('ዋና ዋና ነጥቦች (Bullet Points)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: wordPointsCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('ማጠቃለያ እና መደምደሚያ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: wordConclusionCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryMaroon,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('ወደ PDF አውጣ (Export PDF)'),
                  onPressed: isGenerating ? null : _exportWordPdf,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaHeaderCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: orgOrHeaderCtrl,
                    decoration: const InputDecoration(labelText: 'ተቋም / ርዕሰ-አንቀጽ', isDense: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: dateCtrl,
                    decoration: const InputDecoration(labelText: 'ቀን (በኢትዮጵያ ዘመን አቆጣጠር)', isDense: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: authorCtrl,
                    decoration: const InputDecoration(labelText: 'አዘጋጅ / ኃላፊ', isDense: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: authorRoleCtrl,
                    decoration: const InputDecoration(labelText: 'የኃላፊነት ሚና', isDense: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // PR #46: which department the document is filed under.
            // The office picks; a department user is locked to their own.
            DropdownButtonFormField<Department>(
              value: Department.allDepartments.firstWhere(
                (d) => d.id == selectedDept,
                orElse: () => _deptChoices.first,
              ),
              decoration: const InputDecoration(
                labelText: 'ክፍል',
                isDense: true,
              ),
              items: _deptChoices
                  .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text(d.name, style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
              onChanged: AuthService.isSuperAdmin
                  ? (d) => setState(() => selectedDept = d?.id ?? selectedDept)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
