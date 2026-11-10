import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class OfficeExportService {
  /// Excel (.xlsx) ሰንጠረዥ ማመንጨት እና ወደ ባይት መቀየር
  static Uint8List generateExcelFile({
    required String sheetName,
    required List<String> headers,
    required List<List<dynamic>> rows,
  }) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheet, sheetName);
    final sheet = excel[sheetName];

    // 1. የርዕስ ረድፍ (Headers)
    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#8B1E24'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      );
    }

    // 2. የውሂብ ረድፎች (Data Rows)
    for (int r = 0; r < rows.length; r++) {
      final rowData = rows[r];
      for (int c = 0; c < rowData.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
        final val = rowData[c];
        if (val is num) {
          cell.value = DoubleCellValue(val.toDouble());
        } else if (val is int) {
          cell.value = IntCellValue(val);
        } else {
          cell.value = TextCellValue(val?.toString() ?? '');
        }
      }
    }

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  /// ሰነድን በውጫዊ አፕሊኬሽን (Microsoft Office) ለመክፈት ወደ ጊዜያዊ ማህደር ማስቀመጥ
  static Future<String?> saveAndGetFilePath({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (kIsWeb) {
      // በዌብ ላይ በቀጥታ የማውረጃ ሊንክ ይሆናል
      return null;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      debugPrint('Error saving file for external office: $e');
      return null;
    }
  }
}
