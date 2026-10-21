import 'package:flutter/material.dart';
import '../models/department.dart';
import '../services/pdf_generator_service.dart';
import '../services/telegram_service.dart';
import '../widgets/telegram_connect_dialog.dart';
import '../theme/app_theme.dart';

class DocumentEditorScreen extends StatefulWidget {
  final int initialTabIndex; // 0: Word, 1: Excel

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

  // የአገልግሎት ሞድ፦ መደበኛ (Normal/General) ወይስ ይፋዊ ሰንበት ት/ቤት (Church Official)
  bool isChurchMode = false; // ነባሪው መደበኛ አጠቃላይ አገልግሎት ነው!

  // አጠቃላይ መረጃ
  final orgOrHeaderCtrl = TextEditingController(text: 'የስራ እና የንግድ ሰነድ');
  String selectedDept = 'ትምህርት እና ስልጠና ክፍል';
  final dateCtrl = TextEditingController(text: '14/02/2019 ዓ.ም');
  final authorCtrl = TextEditingController(text: 'ተስፋሁን ባይህ');
  final authorRoleCtrl = TextEditingController(text: 'ኃላፊ / ባለቤት');

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
  String currentTablePreset = 'expense'; // 'expense', 'sales', 'inventory', 'members'
  List<String> tableHeaders = ['ተ.ቁ', 'የስራው / የእቃው ዝርዝር', 'መለኪያ', 'ብዛት', 'ያንዱ ዋጋ', 'ጠቅላላ ዋጋ'];
  List<Map<String, dynamic>> tableRows = [
    {'col1': 'የቢሮ ቁሳቁስ እና ደብተር', 'col2': 'ደርዘን', 'col3': 5, 'col4': 800.0},
    {'col2': 'የማስታወቂያ ህትመት', 'col2_unit': 'ቅጂ', 'col3': 200, 'col4': 15.0},
    {'col1': 'የባለሙያ ማበረታቻ', 'col2': 'ሰው', 'col3': 4, 'col4': 1000.0},
  ];

  bool isGenerating = false;
  bool isSendingTelegram = false;

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

  // የ Word ቅጾች (Templates for Normal / General Services)
  void _applyWordTemplate(String type) {
    setState(() {
      if (type == 'general_report') {
        wordTitleCtrl.text = 'አጠቃላይ የስራ አፈፃፀም ሪፖርት';
        wordIntroCtrl.text = 'ለሚመለከተው የስራ አመራር አካል፦\nየተከናወኑ ዋና ዋና ተግባራትን ሪፖርት በሚከተለው መልኩ አቅርበናል።';
        wordBodyCtrl.text = 'በዚህ የስራ ምዕራፍ የተከናወኑ ተግባራት አበረታች ውጤት ያስመዘገቡ ሲሆን፣ ግቦችን ለማሳካት የተደረገው ጥረት ፍሬያማ ሆኗል።';
        wordPointsCtrl.text = '• የታቀዱ ስራዎች 90% በሰዓቱ ተጠናቀዋል\n• ወጪ ቆጣቢ በሆነ መንገድ ስራዎች ተከናውነዋል\n• የደንበኞች እና የአባላት እርካታ ጨምሯል';
        wordConclusionCtrl.text = 'ለቀጣይ የስራ ምዕራፍ አስፈላጊው ግብዓት እንዲሟላ በአክብሮት እናሳስባለን።';
      } else if (type == 'minutes') {
        wordTitleCtrl.text = 'የስራ ስብሰባ ቃለ-ጉባኤ (Meeting Minutes)';
        wordIntroCtrl.text = 'በዛሬው እለት የተካሄደው መደበኛ ውይይት የሚከተሉትን ዋና ዋና አጀንዳዎች ተመልክቷል።';
        wordBodyCtrl.text = 'በስብሰባው ላይ የተገኙ የስራ ኃላፊዎችና አባላት የነበሩ ጠንካራ እና ደካማ ጎኖችን በስፋት የገመገሙ ሲሆን፣ በቀጣይ መሻሻል ባለባቸው ጉዳዮች ላይ የጋራ ስምምነት ተደርሷል።';
        wordPointsCtrl.text = '• አጀንዳ 1፡ የስራ ክንውን ግምገማ\n• አጀንዳ 2፡ የበጀት እና ወጪ አጠቃቀም\n• አጀንዳ 3፡ አዲስ የስራ ክፍፍልና ኃላፊነት መስጠት';
        wordConclusionCtrl.text = 'ስብሰባው በጋራ ስምምነት የተጠናቀቀ ሲሆን፣ ቀጣዩ ውይይት ለሚቀጥለው ሳምንት ተቀጥሯል።';
      } else if (type == 'application') {
        wordTitleCtrl.text = 'ይፋዊ ማመልከቻ / የጥያቄ ደብዳቤ';
        wordIntroCtrl.text = 'ለተከበሩ የስራ ኃላፊ / ድርጅት፦';
        wordBodyCtrl.text = 'ይህንን ማመልከቻ ያስገባሁበት ዋና ምክንያት ከዚህ በታች በዝርዝር የተጠቀሱትን ጉዳዮች በማየት አስፈላጊው ውሳኔ እንዲሰጥልኝ በአክብሮት ለመጠየቅ ነው።';
        wordPointsCtrl.text = '• አስፈላጊ የሆኑ የሰነድ ማስረጃዎች ተያይዘዋል\n• የቀረበው ጥያቄ አፋጣኝ ምላሽ የሚሻ ነው\n• ለሚደረገው ትብብር በቅድሚያ ምስጋናዬን አቀርባለሁ';
        wordConclusionCtrl.text = 'ጉዳዩን በጥሞና ተመልክታችሁ ውሳኔ እንድትሰጡኝ በአክብሮት እጠይቃለሁ።';
      } else if (type == 'business_note') {
        wordTitleCtrl.text = 'የንግድና የስራ ስምምነት ማስታወሻ';
        wordIntroCtrl.text = 'በሁለቱ ወገኖች መካከል የተደረገውን የጋራ ስምምነት ነጥቦች ያብራራል።';
        wordBodyCtrl.text = 'ሁለቱም ወገኖች በጋራ ለመስራት እና የተሰጣቸውን ኃላፊነት በታማኝነት ለመወጣት ተስማምተዋል።';
        wordPointsCtrl.text = '• የመጀመሪያ ወገን የስራ ድርሻ\n• የሁለተኛ ወገን ክፍያ እና ግዴታ\n• የስራው መጠናቀቂያ ጊዜ እና ሁኔታ';
        wordConclusionCtrl.text = 'ይህ ስምምነት በሁለቱም ወገኖች ፊርማ ጸንቶ የሚቆይ ይሆናል።';
      } else if (type == 'blank') {
        wordTitleCtrl.clear();
        wordIntroCtrl.clear();
        wordBodyCtrl.clear();
        wordPointsCtrl.clear();
        wordConclusionCtrl.clear();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('የሰነድ ቅጹ ተዘጋጅቷል!'), duration: Duration(milliseconds: 800)),
    );
  }

  // የሰንጠረዥ ቅጾች (Excel Table Presets)
  void _switchTablePreset(String preset) {
    setState(() {
      currentTablePreset = preset;
      if (preset == 'expense') {
        tableTitleCtrl.text = 'የወጪ እና የበጀት ዝርዝር ሰንጠረዥ';
        tableRows = [
          {'name': 'የቢሮ እቃዎችና ቁሳቁስ', 'unit': 'ደርዘን', 'qty': 5, 'price': 800.0},
          {'name': 'የህትመትና ማስታወቂያ ወጪ', 'unit': 'ቅጂ', 'qty': 200, 'price': 15.0},
          {'name': 'የትራንስፖርት አገልግሎት', 'unit': 'ዙር', 'qty': 3, 'price': 500.0},
        ];
      } else if (preset == 'sales') {
        tableTitleCtrl.text = 'የእለታዊ ሽያጭ እና የገቢ መዝገብ';
        tableRows = [
          {'name': 'የተሸጠ እቃ ወይም አገልግሎት A', 'unit': 'ቁጥር', 'qty': 10, 'price': 250.0},
          {'name': 'የተሸጠ እቃ ወይም አገልግሎት B', 'unit': 'ቁጥር', 'qty': 4, 'price': 600.0},
          {'name': 'ተጨማሪ አገልግሎት', 'unit': 'ሰው', 'qty': 2, 'price': 1200.0},
        ];
      } else if (preset == 'inventory') {
        tableTitleCtrl.text = 'የዕቃዎች ቆጠራ እና ንብረት መዝገብ (Inventory)';
        tableRows = [
          {'name': 'ኮምፒውተር / ላፕቶፕ', 'unit': 'ፍሬ', 'qty': 3, 'price': 45000.0},
          {'name': 'ፕሪንተር (Printer)', 'unit': 'ፍሬ', 'qty': 1, 'price': 28000.0},
          {'name': 'የቢሮ ወንበርና ጠረጴዛ', 'unit': 'ስብስብ', 'qty': 6, 'price': 4500.0},
        ];
      } else if (preset == 'blank_table') {
        tableTitleCtrl.text = 'አዲስ ሰንጠረዥ';
        tableRows = [];
      }
    });
  }

  // አዲስ ረድፍ መጨመር
  void _addTableRow() {
    final nameCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'ቁጥር');
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_box_rounded, color: Color(0xFF217346)),
            SizedBox(width: 8),
            Text('አዲስ ረድፍ ጨምር (Add Row)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'የስራው / የእቃው ዝርዝር',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: unitCtrl,
                      decoration: const InputDecoration(
                        labelText: 'መለኪያ (ቁጥር/ኪሎ/ቀን)',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'ብዛት',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'ያንዱ ዋጋ (ብር)',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ይቅር')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF217346), foregroundColor: Colors.white),
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                final qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
                final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                setState(() {
                  tableRows.add({
                    'name': name,
                    'unit': unitCtrl.text.trim(),
                    'qty': qty,
                    'price': price,
                  });
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('አስገባ'),
          ),
        ],
      ),
    );
  }

  // ረድፍ ማስተካከል
  void _editTableRow(int index) {
    final row = tableRows[index];
    final nameCtrl = TextEditingController(text: row['name']);
    final unitCtrl = TextEditingController(text: row['unit']);
    final qtyCtrl = TextEditingController(text: '${row['qty']}');
    final priceCtrl = TextEditingController(text: '${row['price']}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ረድፉን አስተካክል (Edit Row)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'የስራው / የእቃው ዝርዝር', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(controller: unitCtrl, decoration: const InputDecoration(labelText: 'መለኪያ', border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ብዛት', border: OutlineInputBorder()))),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ያንዱ ዋጋ (ብር)', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ይቅር')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF217346), foregroundColor: Colors.white),
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                final qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
                final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                setState(() {
                  tableRows[index] = {
                    'name': name,
                    'unit': unitCtrl.text.trim(),
                    'qty': qty,
                    'price': price,
                  };
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('አዘምን'),
          ),
        ],
      ),
    );
  }

  // ይፋዊ PDF ማመንጨት (ለመደበኛ አገልግሎት ወይም ለሰንበት ት/ቤት)
  Future<void> _exportPdf() async {
    setState(() => isGenerating = true);
    try {
      final isWordTab = _tabController.index == 0;
      final title = isWordTab ? wordTitleCtrl.text.trim() : tableTitleCtrl.text.trim();

      String content = '';
      List<String>? headers;
      List<List<String>>? rows;
      String? totalLabel;
      String? totalValue;

      if (isWordTab) {
        content = '${wordIntroCtrl.text.trim()}\n\n'
            '${wordBodyCtrl.text.trim()}\n\n'
            'ዋና ዋና ነጥቦች፦\n${wordPointsCtrl.text.trim()}\n\n'
            '${wordConclusionCtrl.text.trim()}';
      } else {
        headers = ['ተ.ቁ', 'የስራው/የእቃው ዝርዝር', 'መለኪያ', 'ብዛት', 'ያንዱ ዋጋ', 'ጠቅላላ ዋጋ'];
        rows = [];
        for (int i = 0; i < tableRows.length; i++) {
          final r = tableRows[i];
          final q = (r['qty'] as num?)?.toDouble() ?? 0.0;
          final p = (r['price'] as num?)?.toDouble() ?? 0.0;
          final total = q * p;
          rows.add([
            '${i + 1}',
            r['name'] ?? '',
            r['unit'] ?? '',
            '${r['qty']}',
            '${p.toStringAsFixed(2)} ብር',
            '${total.toStringAsFixed(2)} ብር',
          ]);
        }
        totalLabel = 'ጠቅላላ ድምር';
        totalValue = '${_tableGrandTotal.toStringAsFixed(2)} ብር';
      }

      final deptOrOrg = isChurchMode ? selectedDept : orgOrHeaderCtrl.text.trim();

      final pdfBytes = await PdfGeneratorService.generateCustomDocumentPdf(
        title: title,
        department: deptOrOrg,
        date: dateCtrl.text.trim(),
        content: content,
        tableHeaders: headers,
        tableRows: rows,
        totalLabel: totalLabel,
        totalValue: totalValue,
        signeeName: authorCtrl.text.trim(),
        signeeTitle: authorRoleCtrl.text.trim(),
        isChurchOfficial: isChurchMode,
        organizationName: isChurchMode ? null : orgOrHeaderCtrl.text.trim(),
      );

      final fileName = isWordTab ? 'ሰነድ_${DateTime.now().millisecondsSinceEpoch}.pdf' : 'ሰንጠረዥ_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await PdfGeneratorService.printOrSharePdf(pdfBytes, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$fileName በተሳካ ሁኔታ ተዘጋጅቷል!'),
            backgroundColor: AppTheme.greenSuccess,
          ),
        );
      }
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

  // ወደ ቴሌግራም መላክ
  Future<void> _sendToTelegram() async {
    if (TelegramService.savedChatId == null || TelegramService.savedChatId!.isEmpty) {
      final connected = await TelegramConnectDialog.show(context);
      if (connected != true) return;
    }

    setState(() => isSendingTelegram = true);
    try {
      final isWordTab = _tabController.index == 0;
      final title = isWordTab ? wordTitleCtrl.text.trim() : tableTitleCtrl.text.trim();

      String content = '';
      List<String>? headers;
      List<List<String>>? rows;
      String? totalLabel;
      String? totalValue;

      if (isWordTab) {
        content = '${wordIntroCtrl.text.trim()}\n\n'
            '${wordBodyCtrl.text.trim()}\n\n'
            'ዋና ዋና ነጥቦች፦\n${wordPointsCtrl.text.trim()}\n\n'
            '${wordConclusionCtrl.text.trim()}';
      } else {
        headers = ['ተ.ቁ', 'የስራው/የእቃው ዝርዝር', 'መለኪያ', 'ብዛት', 'ያንዱ ዋጋ', 'ጠቅላላ ዋጋ'];
        rows = [];
        for (int i = 0; i < tableRows.length; i++) {
          final r = tableRows[i];
          final q = (r['qty'] as num?)?.toDouble() ?? 0.0;
          final p = (r['price'] as num?)?.toDouble() ?? 0.0;
          final total = q * p;
          rows.add([
            '${i + 1}',
            r['name'] ?? '',
            r['unit'] ?? '',
            '${r['qty']}',
            '${p.toStringAsFixed(2)} ብር',
            '${total.toStringAsFixed(2)} ብር',
          ]);
        }
        totalLabel = 'ጠቅላላ ድምር';
        totalValue = '${_tableGrandTotal.toStringAsFixed(2)} ብር';
      }

      final deptOrOrg = isChurchMode ? selectedDept : orgOrHeaderCtrl.text.trim();

      final pdfBytes = await PdfGeneratorService.generateCustomDocumentPdf(
        title: title,
        department: deptOrOrg,
        date: dateCtrl.text.trim(),
        content: content,
        tableHeaders: headers,
        tableRows: rows,
        totalLabel: totalLabel,
        totalValue: totalValue,
        signeeName: authorCtrl.text.trim(),
        signeeTitle: authorRoleCtrl.text.trim(),
        isChurchOfficial: isChurchMode,
        organizationName: isChurchMode ? null : orgOrHeaderCtrl.text.trim(),
      );

      final caption = '<b>${isChurchMode ? "ይፋዊ የሰንበት ት/ቤት ሰነድ" : "አጠቃላይ ይፋዊ ሰነድ"}</b>\n'
          '<b>ርዕስ፦</b> $title\n'
          '<b>ድርጅት/ክፍል፦</b> $deptOrOrg\n'
          '<b>አዘጋጅ፦</b> ${authorCtrl.text.trim()} (${authorRoleCtrl.text.trim()})\n'
          '<b>ቀን፦</b> ${dateCtrl.text.trim()}';

      final success = await TelegramService.sendDocument(
        fileBytes: pdfBytes,
        fileName: isWordTab ? 'ማስታወሻ.pdf' : 'ሰንጠረዥ.pdf',
        caption: caption,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ሰነዱ በተሳካ ሁኔታ ወደ ቴሌግራም ግሩፕ ተልኳል!'),
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
        title: const Text('የሰነድ እና ሰንጠረዥ አዘጋጅ (Word & Excel)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.telegram, color: Colors.white),
            tooltip: 'የቴሌግራም ማገናኛ',
            onPressed: () => TelegramConnectDialog.show(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.secondaryGold,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.article_outlined), text: 'Word / ጽሑፍ መጻፊያ'),
            Tab(icon: Icon(Icons.table_chart_outlined), text: 'Excel / ሰንጠረዥና በጀት'),
          ],
        ),
      ),
      body: Column(
        children: [
          // የሰነድ አይነት መራጭ ባነር (መደበኛ አጠቃላይ አገልግሎት ወይስ ይፋዊ ሰንበት ት/ቤት)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: isChurchMode ? AppTheme.lightGold : const Color(0xFFF1F5F9),
            child: Row(
              children: [
                Icon(
                  isChurchMode ? Icons.church : Icons.public,
                  color: isChurchMode ? AppTheme.primaryMaroon : const Color(0xFF2563EB),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isChurchMode
                        ? 'የሰነድ አይነት፦ የሰንበት ት/ቤት ይፋዊ ሰነድ (ከአርማና ማህተም ጋር)'
                        : 'የሰነድ አይነት፦ መደበኛ አጠቃላይ ሰነድ (ለግል፣ ለስራ፣ ለንግድ)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isChurchMode ? AppTheme.primaryMaroon : const Color(0xFF1E293B),
                    ),
                  ),
                ),
                Switch(
                  value: isChurchMode,
                  activeThumbColor: AppTheme.primaryMaroon,
                  onChanged: (val) {
                    setState(() {
                      isChurchMode = val;
                      if (!isChurchMode) {
                        orgOrHeaderCtrl.text = 'የስራ እና የንግድ ሰነድ';
                      }
                    });
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ቋሚ ራስጌ፦ ክፍል ወይም ድርጅት፣ ቀን እና አዘጋጅ
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: isChurchMode
                          ? DropdownButtonFormField<String>(
                              initialValue: Department.allDepartments.any((d) => d.name == selectedDept)
                                  ? selectedDept
                                  : Department.allDepartments.first.name,
                              decoration: const InputDecoration(
                                labelText: 'ክፍል',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                isDense: true,
                              ),
                              items: Department.allDepartments
                                  .map((d) => DropdownMenuItem(value: d.name, child: Text(d.name, style: const TextStyle(fontSize: 12))))
                                  .toList(),
                              onChanged: (val) => setState(() => selectedDept = val!),
                            )
                          : TextField(
                              controller: orgOrHeaderCtrl,
                              decoration: const InputDecoration(
                                labelText: 'የድርጅት / የግል / የስራ ርዕስ',
                                hintText: 'ለምሳሌ፦ የግል ስራ፣ የንግድ ድርጅት፣ ማህበር',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                isDense: true,
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: dateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'ቀን',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: authorCtrl,
                        decoration: const InputDecoration(
                          labelText: 'የአዘጋጁ ስም',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: authorRoleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'የስራ ድርሻ / ኃላፊነት',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // የታብ ዋና ይዘት
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildWordEditorTab(),
                _buildExcelTableTab(),
              ],
            ),
          ),

          // ቋሚ የታችኛው የድርጊት አዝራሮች ባር
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(20),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isGenerating ? null : _exportPdf,
                      icon: isGenerating
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.picture_as_pdf, size: 18),
                      label: Text(isGenerating ? 'በማዘጋጀት ላይ...' : 'ይፋዊ PDF አውጣ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isChurchMode ? AppTheme.primaryMaroon : const Color(0xFF1E293B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isSendingTelegram ? null : _sendToTelegram,
                      icon: isSendingTelegram
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded, color: Color(0xFF0088CC), size: 18),
                      label: Text(
                        isSendingTelegram ? 'በመላክ ላይ...' : 'ወደ ቴሌግራም ላክ',
                        style: const TextStyle(color: Color(0xFF0088CC), fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF0088CC), width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 1. Word የጽሑፍ አዘጋጅ
  Widget _buildWordEditorTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // የቅጾች ፈጣን መምረጫ
        Row(
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFF2563EB), size: 18),
            const SizedBox(width: 6),
            const Text('ፈጣን የጽሑፍ ቅጾች (Templates)፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const Spacer(),
            TextButton(onPressed: () => _applyWordTemplate('blank'), child: const Text('አጽዳ (Blank)', style: TextStyle(fontSize: 11))),
          ],
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ActionChip(
                avatar: const Icon(Icons.summarize, size: 14),
                label: const Text('አጠቃላይ ሪፖርት', style: TextStyle(fontSize: 11)),
                onPressed: () => _applyWordTemplate('general_report'),
              ),
              const SizedBox(width: 6),
              ActionChip(
                avatar: const Icon(Icons.groups, size: 14),
                label: const Text('ቃለ-ጉባኤ (Minutes)', style: TextStyle(fontSize: 11)),
                onPressed: () => _applyWordTemplate('minutes'),
              ),
              const SizedBox(width: 6),
              ActionChip(
                avatar: const Icon(Icons.mail, size: 14),
                label: const Text('ማመልከቻ / ደብዳቤ', style: TextStyle(fontSize: 11)),
                onPressed: () => _applyWordTemplate('application'),
              ),
              const SizedBox(width: 6),
              ActionChip(
                avatar: const Icon(Icons.handshake, size: 14),
                label: const Text('ስራ / ውል / ስምምነት', style: TextStyle(fontSize: 11)),
                onPressed: () => _applyWordTemplate('business_note'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // የሰነዱ ርዕስ
        TextField(
          controller: wordTitleCtrl,
          decoration: const InputDecoration(
            labelText: 'የሰነዱ / የማስታወሻው ርዕስ',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.title),
          ),
        ),
        const SizedBox(height: 12),

        // መግቢያ / ሰላምታ
        TextField(
          controller: wordIntroCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'መግቢያ / ሰላምታ',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),

        // ዋናው ዝርዝር ጽሑፍ
        TextField(
          controller: wordBodyCtrl,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'ዋናው ዝርዝር ጽሑፍ (Word Content)',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
            hintText: 'ዝርዝር መልዕክቱን፣ እውነታዎችንና ሁኔታዎችን እዚህ ይጻፉ...',
          ),
        ),
        const SizedBox(height: 12),

        // ዋና ዋና ነጥቦች
        TextField(
          controller: wordPointsCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'ዋና ዋና ነጥቦች (በነጠብጣብ / Bullets)',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
            hintText: '• ነጥብ 1\n• ነጥብ 2\n• ነጥብ 3',
          ),
        ),
        const SizedBox(height: 12),

        // ማጠቃለያ / ውሳኔ
        TextField(
          controller: wordConclusionCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'ማጠቃለያ / ጥያቄ ወይም ውሳኔ',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // 2. Excel የሰንጠረዥና የበጀት አዘጋጅ
  Widget _buildExcelTableTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // ፈጣን የሰንጠረዥ አይነቶች
        Row(
          children: [
            const Icon(Icons.table_view_rounded, color: Color(0xFF217346), size: 18),
            const SizedBox(width: 6),
            const Text('የሰንጠረዥ አይነቶች (Presets)፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('💰 ወጪ / በጀት', style: TextStyle(fontSize: 11)),
                selected: currentTablePreset == 'expense',
                selectedColor: const Color(0xFF217346),
                labelStyle: TextStyle(color: currentTablePreset == 'expense' ? Colors.white : Colors.black87),
                onSelected: (_) => _switchTablePreset('expense'),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('🛒 ሽያጭና ገቢ', style: TextStyle(fontSize: 11)),
                selected: currentTablePreset == 'sales',
                selectedColor: const Color(0xFF217346),
                labelStyle: TextStyle(color: currentTablePreset == 'sales' ? Colors.white : Colors.black87),
                onSelected: (_) => _switchTablePreset('sales'),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('📦 ንብረት / Inventory', style: TextStyle(fontSize: 11)),
                selected: currentTablePreset == 'inventory',
                selectedColor: const Color(0xFF217346),
                labelStyle: TextStyle(color: currentTablePreset == 'inventory' ? Colors.white : Colors.black87),
                onSelected: (_) => _switchTablePreset('inventory'),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('⬜ ባዶ ሰንጠረዥ', style: TextStyle(fontSize: 11)),
                selected: currentTablePreset == 'blank_table',
                selectedColor: const Color(0xFF217346),
                labelStyle: TextStyle(color: currentTablePreset == 'blank_table' ? Colors.white : Colors.black87),
                onSelected: (_) => _switchTablePreset('blank_table'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: TextField(
                controller: tableTitleCtrl,
                decoration: const InputDecoration(
                  labelText: 'የሰንጠረዡ ርዕስ (Table Title)',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _addTableRow,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('ረድፍ ጨምር'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF217346),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ሰንጠረዡ ራሱ
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 4, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            children: [
              // የሰንጠረዥ ራስጌ ባር
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E293B),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
                ),
                child: const Row(
                  children: [
                    Text('ተ.ቁ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    SizedBox(width: 14),
                    Expanded(child: Text('የስራው / የእቃው ዝርዝር', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                    Text('ጠቅላላ ዋጋ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    SizedBox(width: 40),
                  ],
                ),
              ),

              if (tableRows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('ምንም ረድፍ አልተጨመረም፤ "ረድፍ ጨምር" የሚለውን ይጫኑ።', style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: tableRows.length,
                  separatorBuilder: (ctx, idx) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final r = tableRows[idx];
                    final q = (r['qty'] as num?)?.toDouble() ?? 0.0;
                    final p = (r['price'] as num?)?.toDouble() ?? 0.0;
                    final total = q * p;

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor: const Color(0xFF217346),
                        child: Text('${idx + 1}', style: const TextStyle(fontSize: 10, color: Colors.white)),
                      ),
                      title: Text(r['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(
                        'መለኪያ፦ ${r['unit']} | ብዛት፦ ${r['qty']} | ያንዱ፦ ${p.toStringAsFixed(2)} ብር',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${total.toStringAsFixed(2)} ብር',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF217346), fontSize: 13),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
                            tooltip: 'አስተካክል',
                            onPressed: () => _editTableRow(idx),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                            tooltip: 'ሰርዝ',
                            onPressed: () {
                              setState(() {
                                tableRows.removeAt(idx);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // የድምር ሳጥን (Auto-sum Grand Total)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF217346), width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.functions, color: Color(0xFF217346), size: 22),
                  SizedBox(width: 8),
                  Text(
                    'ጠቅላላ ድምር (በራስ-ሰር የተሰላ)፦',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                  ),
                ],
              ),
              Text(
                '${_tableGrandTotal.toStringAsFixed(2)} ብር',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: Color(0xFF217346),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
