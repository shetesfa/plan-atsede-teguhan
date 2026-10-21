import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/official_letter.dart';
import '../models/proposal.dart';

class PdfGeneratorService {
  static Future<pw.Font> _loadNyalaFont() async {
    final fontData = await rootBundle.load('assets/nyala.ttf');
    return pw.Font.ttf(fontData);
  }

  static Future<Uint8List> _loadLogoBytes() async {
    final ByteData data = await rootBundle.load('assets/icon.png');
    return data.buffer.asUint8List();
  }

  /// ይፋዊ ደብዳቤን ወደ PDF መቀየር
  static Future<Uint8List> generateLetterPdf(OfficialLetter letter) async {
    final pdf = pw.Document();
    final font = await _loadNyalaFont();
    final logoBytes = await _loadLogoBytes();
    final logoImage = pw.MemoryImage(logoBytes);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 35),
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // የራስጌ ክፍል (Header with Logo & Titles)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    width: 70,
                    height: 70,
                    child: pw.Image(logoImage),
                  ),
                  pw.SizedBox(width: 16),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'አጸደ ትጉሃን ሰንበት ትምህርት ቤት',
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#7A1315'),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          letter.senderDepartment,
                          style: pw.TextStyle(
                            fontSize: 15,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1.5, color: PdfColor.fromHex('#7A1315')),
              pw.SizedBox(height: 12),

              // ቀን (Date aligned to the right)
              pw.Align(
                alignment: pw.Alignment.topRight,
                child: pw.Text(
                  'ቀን (Date)፡ ${letter.date}',
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 14),

              // አድራሻ (Recipient)
              pw.Text(
                letter.recipientName,
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              if (letter.recipientDepartment.isNotEmpty)
                pw.Text(
                  letter.recipientDepartment,
                  style: pw.TextStyle(fontSize: 13),
                ),
              pw.SizedBox(height: 14),

              // ጉዳዩ (Subject)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 4),
                child: pw.Text(
                  'ጉዳዩ፡ ${letter.subject}',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 12),

              // ዝርዝር መልዕክት (Body)
              pw.Paragraph(
                text: letter.body,
                style: const pw.TextStyle(fontSize: 13, lineSpacing: 4),
                textAlign: pw.TextAlign.justify,
              ),
              pw.SizedBox(height: 14),

              // ማሳሰቢያ (Remarks)
              if (letter.remarks.isNotEmpty) ...[
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F8F9FA'),
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    'ማሳሰቢያ፦ ${letter.remarks}',
                    style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic),
                  ),
                ),
                pw.SizedBox(height: 16),
              ],

              // ከመንፈሳዊ ሰላምታ ጋር!
              pw.Text(
                'ከመንፈሳዊ ሰላምታ ጋር!',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 25),

              // ፊርማ እና ማህተም (Signee)
              pw.Align(
                alignment: pw.Alignment.bottomRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('________________________'),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      letter.signeeName,
                      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      letter.signeeTitle,
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                    pw.Text(
                      '(ፊርማ እና ማህተም)',
                      style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),

              // ግልባጭ (cc)
              if (letter.ccList.isNotEmpty) ...[
                pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                pw.SizedBox(height: 4),
                pw.Text(
                  'ግልባጭ (cc)፡',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
                ...letter.ccList.map(
                  (cc) => pw.Text('• $cc', style: const pw.TextStyle(fontSize: 10)),
                ),
              ],
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// ይፋዊ ፕሮፖዛልን ወደ PDF መቀየር
  static Future<Uint8List> generateProposalPdf(Proposal proposal) async {
    final pdf = pw.Document();
    final font = await _loadNyalaFont();
    final logoBytes = await _loadLogoBytes();
    final logoImage = pw.MemoryImage(logoBytes);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 35, vertical: 30),
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (pw.Context context) {
          return [
            // Header
            pw.Row(
              children: [
                pw.Container(width: 60, height: 60, child: pw.Image(logoImage)),
                pw.SizedBox(width: 14),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'አጸደ ትጉሃን ሰንበት ትምህርት ቤት',
                        style: pw.TextStyle(
                          fontSize: 17,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#7A1315'),
                        ),
                      ),
                      pw.Text(
                        proposal.departmentName,
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                pw.Text('ቀን፡ ${proposal.date}', style: const pw.TextStyle(fontSize: 12)),
              ],
            ),
            pw.Divider(thickness: 1.5, color: PdfColor.fromHex('#7A1315')),
            pw.SizedBox(height: 12),

            // Title
            pw.Center(
              child: pw.Text(
                proposal.title,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#7A1315'),
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 14),

            // Objective
            _buildSectionHeader('፩. የመርሃግብሩ / የፕሮጀክቱ ዓላማ'),
            pw.Paragraph(text: proposal.objective, style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 10),

            // Location & Date
            _buildSectionHeader('፪. የክንውን ጊዜ እና ቦታ'),
            pw.Paragraph(text: proposal.targetLocationAndDate, style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 10),

            // Activities
            _buildSectionHeader('፫. ዝርዝር ተግባራት እና አፈፃፀም'),
            pw.Paragraph(text: proposal.activities, style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 10),

            // Budget Table
            _buildSectionHeader('፬. የሚያስፈልግ በጀት እና ቁሳቁስ'),
            if (proposal.budgetItems.isNotEmpty)
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F5ECE8')),
                    children: [
                      _cell('ተ.ቁ', isHeader: true),
                      _cell('የእቃው/የአገልግሎቱ አይነት', isHeader: true),
                      _cell('መለኪያ', isHeader: true),
                      _cell('ብዛት', isHeader: true),
                      _cell('ያንዱ ዋጋ (ብር)', isHeader: true),
                      _cell('ጠቅላላ ዋጋ (ብር)', isHeader: true),
                    ],
                  ),
                  ...proposal.budgetItems.asMap().entries.map((entry) {
                    final idx = entry.key + 1;
                    final item = entry.value;
                    return pw.TableRow(
                      children: [
                        _cell('$idx'),
                        _cell(item.itemName),
                        _cell(item.unit),
                        _cell(item.quantity.toStringAsFixed(0)),
                        _cell(item.unitPrice.toStringAsFixed(2)),
                        _cell(item.totalPrice.toStringAsFixed(2)),
                      ],
                    );
                  }),
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColor.fromHex('#FFF6E5')),
                    children: [
                      _cell(''),
                      _cell('ጠቅላላ ድምር በጀት', isHeader: true),
                      _cell(''),
                      _cell(''),
                      _cell(''),
                      _cell('${proposal.grandTotalBudget.toStringAsFixed(2)} ብር', isHeader: true),
                    ],
                  ),
                ],
              )
            else
              pw.Text('የተለየ በጀት አይጠይቅም', style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 12),

            // Manpower
            _buildSectionHeader('፭. የሚያስፈልግ የሰው ኃይል'),
            pw.Paragraph(text: proposal.manpower, style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 20),

            // Signatures
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('አዘጋጅ / አቅራቢ፡', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                    pw.SizedBox(height: 6),
                    pw.Text('ስም፡ ${proposal.preparedByName}'),
                    pw.Text('ኃላፊነት፡ ${proposal.preparedByTitle}'),
                    pw.Text('ፊርማ፡ ____________________'),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('የፅ/ቤት ውሳኔ እና ማፅደቂያ፡', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                    pw.SizedBox(height: 6),
                    pw.Text('ሁኔታ፡ ${proposal.approvalStatus}'),
                    pw.Text('ፊርማና ማህተም፡ ____________________'),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildSectionHeader(String title) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: PdfColor.fromHex('#7A1315'),
        ),
      ),
    );
  }

  static pw.Widget _cell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  /// ብጁ የሞባይል ሰነድ እና የኤክሴል ሰንጠረዥን ወደ PDF መቀየር (ለመደበኛ አገልግሎት ወይም ለሰንበት ት/ቤት)
  static Future<Uint8List> generateCustomDocumentPdf({
    required String title,
    required String department,
    required String date,
    required String content,
    List<String>? tableHeaders,
    List<List<String>>? tableRows,
    String? totalLabel,
    String? totalValue,
    String? signeeName,
    String? signeeTitle,
    bool isChurchOfficial = false,
    String? organizationName,
  }) async {
    final pdf = pw.Document();
    final font = await _loadNyalaFont();
    final logoBytes = await _loadLogoBytes();
    final logoImage = pw.MemoryImage(logoBytes);

    final primaryColor = isChurchOfficial ? PdfColor.fromHex('#7A1315') : PdfColor.fromHex('#1E293B');
    final accentColor = isChurchOfficial ? PdfColor.fromHex('#C5A059') : PdfColor.fromHex('#2563EB');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 35),
        theme: pw.ThemeData.withFont(base: font, bold: font),
        header: (pw.Context context) {
          if (isChurchOfficial) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      width: 60,
                      height: 60,
                      child: pw.Image(logoImage),
                    ),
                    pw.SizedBox(width: 14),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'አጸደ ትጉሃን ሰንበት ትምህርት ቤት',
                            style: pw.TextStyle(
                              fontSize: 17,
                              fontWeight: pw.FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            department,
                            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                          ),
                        ],
                      ),
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('ቀን፡ $date', style: const pw.TextStyle(fontSize: 11)),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 1.5, color: accentColor),
                pw.SizedBox(height: 10),
              ],
            );
          } else {
            // ለመደበኛ / አጠቃላይ አገልግሎት የሚሆን ንጹህ ፕሮፌሽናል ራስጌ (General / Normal Service Header)
            final orgTitle = organizationName != null && organizationName.trim().isNotEmpty
                ? organizationName.trim()
                : (department.isNotEmpty ? department : 'ሰነድ / Document');

            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          orgTitle,
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                        if (signeeTitle != null && signeeTitle.isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(signeeTitle, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                        ],
                      ],
                    ),
                    pw.Text('ቀን (Date)፡ $date', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey800)),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Divider(thickness: 1.5, color: accentColor),
                pw.SizedBox(height: 10),
              ],
            );
          }
        },
        build: (pw.Context context) {
          return [
            // ርዕስ
            pw.Center(
              child: pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryColor,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 14),

            // ዋና ይዘት / ጽሑፍ
            if (content.trim().isNotEmpty) ...[
              pw.Text(
                content,
                style: const pw.TextStyle(fontSize: 11, lineSpacing: 4),
              ),
              pw.SizedBox(height: 16),
            ],

            // ሰንጠረዥ (Table/Excel)
            if (tableHeaders != null && tableRows != null && tableRows.isNotEmpty) ...[
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColor.fromHex('#7A1315')),
                    children: tableHeaders.map((h) => pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        h,
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                        textAlign: pw.TextAlign.center,
                      ),
                    )).toList(),
                  ),
                  ...tableRows.map((row) => pw.TableRow(
                    children: row.map((cell) => pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(cell, style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
                    )).toList(),
                  )),
                ],
              ),
              if (totalValue != null) ...[
                pw.SizedBox(height: 6),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    '${totalLabel ?? 'ጠቅላላ ድምር'}፡ $totalValue',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primaryColor),
                  ),
                ),
              ],
              pw.SizedBox(height: 20),
            ],

            // ፊርማ
            if (signeeName != null && signeeName.isNotEmpty) ...[
              pw.SizedBox(height: 20),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Container(),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('አዘጋጅ፡ $signeeName', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      if (signeeTitle != null && signeeTitle.isNotEmpty)
                        pw.Text(signeeTitle, style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 6),
                      pw.Text('ፊርማ፡ _______________', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ],
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// የክፍሎች አጠቃላይ አፈፃፀም ግምገማ እና የቁጥጥር ሪፖርት ወደ PDF መቀየር
  static Future<Uint8List> generateAuditEvaluationPdf({
    required List<Map<String, dynamic>> deptStats,
    required List<String> overdueWarnings,
    required String periodName,
    required int totalPlansCount,
    required int completedCount,
    required int overdueCount,
    String? remarks,
  }) async {
    final pdf = pw.Document();
    final font = await _loadNyalaFont();
    final logoBytes = await _loadLogoBytes();
    final logoImage = pw.MemoryImage(logoBytes);

    final overallPercent = totalPlansCount > 0 ? ((completedCount / totalPlansCount) * 100).toInt() : 0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 35, vertical: 30),
        theme: pw.ThemeData.withFont(base: font, bold: font),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(width: 55, height: 55, child: pw.Image(logoImage)),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'አጸደ ትጉሃን ሰንበት ትምህርት ቤት - ጽ/ቤት',
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#7A1315'),
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'የ2019 ዓ.ም የክፍሎች እቅድ አፈፃፀም ግምገማ እና የቁጥጥር ሪፖርት ($periodName)',
                          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey800),
                        ),
                      ],
                    ),
                  ),
                  pw.Text('ቀን፡ ዛሬ', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.Divider(thickness: 1.5, color: PdfColor.fromHex('#C5A059')),
              pw.SizedBox(height: 8),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            // ማጠቃለያ ካርዶች
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                      color: PdfColor.fromHex('#F5F5F5'),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text('ጠቅላላ እቅዶች', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                        pw.Text('$totalPlansCount', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#E8F5E9'),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text('የተጠናቀቁ', style: const pw.TextStyle(fontSize: 9, color: PdfColors.green900)),
                        pw.Text('$completedCount ($overallPercent%)', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#FFEBEE'),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text('ያዘገዩ (ቀናቸው ያለፈ)', style: const pw.TextStyle(fontSize: 9, color: PdfColors.red900)),
                        pw.Text('$overdueCount', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 14),

            // የክፍሎች አፈጻጸም ሰንጠረዥ
            pw.Text(
              '1. የ 10ሩ ክፍሎች ንጽጽራዊ አፈፃፀም እና የግምገማ ደረጃ',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#7A1315')),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColor.fromHex('#7A1315')),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('ተ.ቁ', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('የክፍሉ ስም', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('ጠቅላላ', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('የተጠናቀቀ', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('ያዘገየ', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('አፈጻጸም (%)', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('የግምገማ ሁኔታ', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
                  ],
                ),
                ...deptStats.map((d) {
                  final status = d['status'] as String? ?? 'ጥሩ';
                  final percent = d['percent'] as int? ?? 0;
                  return pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${d['index']}', style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(d['name'] ?? '', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${d['total']}', style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${d['completed']}', style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${d['overdue']}', style: pw.TextStyle(fontSize: 8, color: d['overdue'] > 0 ? PdfColors.red : PdfColors.black), textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('$percent%', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(status, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: percent >= 75 ? PdfColors.green800 : (percent < 40 ? PdfColors.red800 : PdfColors.orange800)), textAlign: pw.TextAlign.center)),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 14),

            // ያዘገዩ እቅዶች ማስጠንቀቂያ
            if (overdueWarnings.isNotEmpty) ...[
              pw.Text(
                '2. አፋጣኝ ክትትል የሚሹ / ያዘገዩ ዋና ዋና እቅዶች',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
              ),
              pw.SizedBox(height: 4),
              ...overdueWarnings.take(8).map((w) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text('⚠️ $w', style: const pw.TextStyle(fontSize: 8, color: PdfColors.red800)),
              )),
              pw.SizedBox(height: 14),
            ],

            // የጽ/ቤት ውሳኔ እና ማጠቃለያ
            pw.Text(
              '3. የጽ/ቤት ውሳኔ እና የአመራር መመሪያ',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#7A1315')),
            ),
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(
                remarks ?? 'አፈፃፀማቸው ከፍተኛ የሆኑ ክፍሎች ተጠናክረው እንዲቀጥሉ፤ አፈፃፀማቸው ዝቅተኛ የሆኑ ወይም ያዘገዩ ክፍሎች ባልተከናወኑት እቅዶች ላይ በ 7 ቀናት ውስጥ የጽሑፍ ማብራሪያ እና አፋጣኝ የክንውን ሪፖርት ለጽ/ቤት እንዲያቀርቡ በጥብቅ ታዟል።',
                style: const pw.TextStyle(fontSize: 9, lineSpacing: 3),
              ),
            ),
            pw.SizedBox(height: 25),

            // ፊርማዎች
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('የቁጥጥር ክፍል ኃላፊ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 15),
                    pw.Text('ፊርማ፡ _______________', style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('የሰንበት ት/ቤቱ ዋና ጸሐፊ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 15),
                    pw.Text('ፊርማ፡ _______________', style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('የሰንበት ት/ቤቱ ሰብሳቢ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 15),
                    pw.Text('ፊርማ፡ _______________', style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// PDFን በስክሪኑ ለማየት ወይም ለሌላ ሰው ለማጋራት
  static Future<void> printOrSharePdf(Uint8List pdfBytes, String fileName) async {
    await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
  }
}
