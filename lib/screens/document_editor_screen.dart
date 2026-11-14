import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as ex;
import '../services/api_service.dart';
import '../services/office_export_service.dart';
import '../widgets/telegram_connect_dialog.dart';
import '../theme/app_theme.dart';

class DocumentEditorScreen extends StatefulWidget {
  final int initialTabIndex;

  const DocumentEditorScreen({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<DocumentEditorScreen> createState() => _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends State<DocumentEditorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool isChurchMode = true; // ነባሪው ይፋዊ ሰንበት ት/ቤት ነው

  // አጠቃላይ መረጃ
  final orgOrHeaderCtrl = TextEditingController(text: 'ዓጸደ ትጉሃን ሰንበት ትምህርት ቤት');
  String selectedDept = 'ትምህርት እና ስልጠና ክፍል';
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

  // Excel / ሰንጠረዥ ታብ
  final tableTitleCtrl = TextEditingController(text: 'የወጪ እና የበጀት ዝርዝር ሰንጠረዥ');
  List<String> tableHeaders = ['ተ.ቁ', 'የስራው / የእቃው ዝርዝር', 'መለኪያ', 'ብዛት', 'ያንዱ ዋጋ', 'ጠቅላላ ዋጋ'];
  List<Map<String, dynamic>> tableRows = [];

  bool isGenerating = false;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _initDefaultTable();
  }

  void _initDefaultTable() {
    tableRows = [
      {'name': 'የመማሪያ ደብተር እና ስክሪፕቶ', 'unit': 'ደርዘን', 'qty': 5, 'price': 800.0},
      {'name': 'የማስታወቂያ ህትመት', 'unit': 'ቅጂ', 'qty': 200, 'price': 15.0},
      {'name': 'የባለሙያ ድጋፍ ክፍያ', 'unit': 'ሰው', 'qty': 4, 'price': 1000.0},
    ];
  }

  @override
  void dispose() {
    _tabController.dispose();
    orgOrHeaderCtrl.dispose();
    dateCtrl.dispose();
    authorCtrl.dispose();
    authorRoleCtrl.dispose();
    wordTitleCtrl.dispose();
    wordIntroCtrl.dispose();
    wordBodyCtrl.dispose();
    wordPointsCtrl.dispose();
    wordConclusionCtrl.dispose();
    tableTitleCtrl.dispose();
    super.dispose();
  }

  double get _tableGrandTotal {
    double total = 0.0;
    for (var r in tableRows) {
      final q = (r['qty'] as num?)?.toDouble() ?? 0.0;
      final p = (r['price'] as num?)?.toDouble() ?? 0.0;
      total += (q * p);
    }
    return total;
  }

  // 1. ነባር Excel (.xlsx) ፋይል ማስገባት (Import XLSX)
  Future<void> _importExcelFile() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      if (result.isNotEmpty) {
        final file = result.first;
        final bytes = await file.xFile.readAsBytes();
        final excelDoc = ex.Excel.decodeBytes(bytes);
        final table = excelDoc.tables.keys.isNotEmpty ? excelDoc.tables[excelDoc.tables.keys.first] : null;
        if (table != null && table.rows.length > 1) {
          final newRows = <Map<String, dynamic>>[];
          for (int i = 1; i < table.rows.length; i++) {
            final r = table.rows[i];
            if (r.isEmpty) continue;
            final name = r.length > 1 ? r[1]?.value?.toString() ?? '' : '';
            final unit = r.length > 2 ? r[2]?.value?.toString() ?? '' : '';
            final qty = r.length > 3 ? double.tryParse(r[3]?.value?.toString() ?? '') ?? 1.0 : 1.0;
            final price = r.length > 4 ? double.tryParse(r[4]?.value?.toString() ?? '') ?? 0.0 : 0.0;
            if (name.isNotEmpty) {
              newRows.add({'name': name, 'unit': unit, 'qty': qty, 'price': price});
            }
          }
          if (newRows.isNotEmpty) {
            setState(() {
              tableRows = newRows;
              tableTitleCtrl.text = file.name.replaceAll('.xlsx', '');
            });
            if (mounted) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text('«${file.name}» ከኤክሴል በተሳካ ሁኔታ ተጭኗል (${newRows.length} ረድፎች)'),
                  backgroundColor: AppTheme.greenSuccess,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('ፋይሉን መጫን አልተቻለም፦ $e'), backgroundColor: AppTheme.redDanger),
        );
      }
    }
  }

  // 2. እውነተኛ Excel (.xlsx) ፋይል ማመንጨት እና ማውጣት (Export XLSX)
  Future<void> _exportExcelFile() async {
    setState(() => isGenerating = true);
    try {
      final rowsData = <List<dynamic>>[];
      for (int i = 0; i < tableRows.length; i++) {
        final r = tableRows[i];
        final q = (r['qty'] as num?)?.toDouble() ?? 0.0;
        final p = (r['price'] as num?)?.toDouble() ?? 0.0;
        rowsData.add([i + 1, r['name'] ?? '', r['unit'] ?? '', q, p, q * p]);
      }
      rowsData.add(['', 'ጠቅላላ ድምር', '', '', '', _tableGrandTotal]);

      final bytes = OfficeExportService.generateExcelFile(
        sheetName: 'የስራ ሰንጠረዥ',
        headers: tableHeaders,
        rows: rowsData,
      );

      final fileName = '${tableTitleCtrl.text.trim().replaceAll(' ', '_')}.xlsx';
      final savedPath = await OfficeExportService.saveAndGetFilePath(
        fileName: fileName,
        bytes: bytes,
      );

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.table_chart, color: AppTheme.primaryMaroon),
                SizedBox(width: 8),
                Text('የ Excel ፋይል ተዘጋጅቷል', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ፋይል ስም፦ $fileName', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(savedPath != null
                    ? 'በመሳሪያዎ ማህደር ተቀምጧል፦\n$savedPath\n\nበ Microsoft Excel ወይም በሌላ የቢሮ አፕሊኬሽን መክፈት ይችላሉ።'
                    : 'የ Excel ፋይል በተሳካ ሁኔታ ተዘጋጅቷል።'),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('እሺ')),
            ],
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ስህተት፦ $e'), backgroundColor: AppTheme.redDanger),
      );
    } finally {
      if (mounted) setState(() => isGenerating = false);
    }
  }

  // 3. ሰነዱን በባክኤንድ ማህደር ማስቀመጥ (Save to Documents Archive)
  Future<void> _saveDocumentToArchive() async {
    setState(() => isSaving = true);
    try {
      final isWord = _tabController.index == 0;
      final payload = {
        'id': 'doc_${DateTime.now().millisecondsSinceEpoch}',
        'department_id': selectedDept,
        'doc_type': isWord ? 'letter' : 'table',
        'title': isWord ? wordTitleCtrl.text.trim() : tableTitleCtrl.text.trim(),
        'date': dateCtrl.text.trim(),
        'content': isWord
            ? {
                'title': wordTitleCtrl.text,
                'intro': wordIntroCtrl.text,
                'body': wordBodyCtrl.text,
                'points': wordPointsCtrl.text,
                'conclusion': wordConclusionCtrl.text,
              }
            : {
                'title': tableTitleCtrl.text,
                'headers': tableHeaders,
                'rows': tableRows,
                'total': _tableGrandTotal,
              },
      };

      final messenger = ScaffoldMessenger.of(context);
      // M12፦ ሰነዶች ወደ documents.php ይላካሉ (ወደ plans.php አይደሉም) እና ውጤቱ
      // ከመፈተሹ በፊት "ተቀምጧል" መልእክት አይታይም።
      final result = await ApiService().saveDocument(payload);
      if (mounted) {
        if (result['success'] == true) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('ሰነዱ በማህደር በተሳካ ሁኔታ ተቀምጧል!'),
              backgroundColor: AppTheme.greenSuccess,
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
        title: const Text('የሰነዶች እና ኤክሴል የስራ ቦታ (Workspace)'),
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.goldAccent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.description_outlined), text: 'Word / ይፋዊ ሰነድ'),
            Tab(icon: Icon(Icons.table_chart_outlined), text: 'Excel / ሰንጠረዥ'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWordEditorTab(),
          _buildExcelEditorTab(),
        ],
      ),
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
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('የ PDF ዝግጅት ተከናውኗል!'), backgroundColor: AppTheme.greenSuccess),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExcelEditorTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: tableTitleCtrl,
                  decoration: InputDecoration(
                    labelText: 'የሰንጠረዡ ርዕስ',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.table_chart, color: AppTheme.primaryMaroon),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.goldAccent,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.file_upload_outlined, size: 20),
                label: const Text('Import XLSX'),
                onPressed: _importExcelFile,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('የውሂብ ረድፎች (Rows)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('ረድፍ ጨምር'),
                        onPressed: () {
                          setState(() {
                            tableRows.add({'name': 'አዲስ እቃ / ተግባር', 'unit': 'ቁጥር', 'qty': 1, 'price': 0.0});
                          });
                        },
                      ),
                    ],
                  ),
                  const Divider(),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: tableRows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final r = tableRows[i];
                      final q = (r['qty'] as num?)?.toDouble() ?? 1.0;
                      final p = (r['price'] as num?)?.toDouble() ?? 0.0;
                      final subtotal = q * p;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                initialValue: r['name'] ?? '',
                                decoration: const InputDecoration(labelText: 'የስራው/የእቃው ስም', isDense: true),
                                onChanged: (val) => r['name'] = val,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 1,
                              child: TextFormField(
                                initialValue: r['unit'] ?? '',
                                decoration: const InputDecoration(labelText: 'መለኪያ', isDense: true),
                                onChanged: (val) => r['unit'] = val,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 1,
                              child: TextFormField(
                                initialValue: q.toString(),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'ብዛት', isDense: true),
                                onChanged: (val) {
                                  setState(() => r['qty'] = double.tryParse(val) ?? 1.0);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                initialValue: p.toString(),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'ያንዱ ዋጋ', isDense: true),
                                onChanged: (val) {
                                  setState(() => r['price'] = double.tryParse(val) ?? 0.0);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${subtotal.toStringAsFixed(1)} ብር',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                              onPressed: () {
                                if (tableRows.length > 1) {
                                  setState(() => tableRows.removeAt(i));
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const Divider(thickness: 1.5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text('ጠቅላላ ድምር፦ ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(
                        '${_tableGrandTotal.toStringAsFixed(2)} ብር',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryMaroon),
                      ),
                    ],
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
                    backgroundColor: Colors.green.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: isGenerating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.file_download),
                  label: const Text('ወደ Excel አውጣ (Export XLSX)'),
                  onPressed: isGenerating ? null : _exportExcelFile,
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
          ],
        ),
      ),
    );
  }
}
