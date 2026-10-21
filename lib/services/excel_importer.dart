import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/plan_item.dart';
import '../models/department.dart';

class ExcelImporterService {
  static const List<String> monthNames = [
    'መስ', 'ጥቅ', 'ህዳር', 'ታህ', 'ጥር', 'የካ', 'መጋ', 'ሚያ', 'ግን', 'ሰኔ', 'ሐም', 'ነሐ'
  ];

  static String mapDepartmentName(String title) {
    if (title.contains('ልማት') || title.contains('በጎአድራጎት')) {
      return 'ልማትና በጎ አድራጎት ክፍል';
    } else if (title.contains('መርሐግብር') || title.contains('መርሃግብር') || title.contains('ጉባዔያት') || title.contains('ጉባኤያት')) {
      return 'መርሃግብር እና ጉባኤያት ክፍል';
    } else if (title.contains('መዝሙር') || title.contains('ስነጥበብ')) {
      return 'መዝሙርና ስነጥበብ ክፍል';
    } else if (title.contains('ትምህርት') || title.contains('ስልጠና')) {
      return 'ትምህርት እና ስልጠና ክፍል';
    } else if (title.contains('መረጃ') || title.contains('ግንኙነት')) {
      return 'መረጃና የውስጥ ግንኙነት ክፍል';
    } else if (title.contains('አባላት')) {
      return 'አባላት አስተዳደር ክፍል';
    } else if (title.contains('ቁጥጥር')) {
      return 'ቁጥጥር ክፍል';
    } else if (title.contains('በጀት') || title.contains('ንብረት')) {
      return 'በጀት እና ንብረት አስተዳደር ክፍል';
    } else if (title.contains('ሰው ሀብት')) {
      return 'ሰው ሀብት አስተዳደር ክፍል';
    }
    return 'ጽ/ቤት';
  }

  static String getDepartmentId(String departmentName) {
    for (var dept in Department.allDepartments) {
      if (dept.name == departmentName || departmentName.contains(dept.shortName)) {
        return dept.id;
      }
    }
    return 'admin';
  }

  /// የ 10ሩን ክፍሎች እቅዶች ከ assets/default_plans.json ወይም ከተሰጠ ኤክሴል ባይት ይጭናል
  static Future<List<PlanItem>> loadPlans({Uint8List? fileBytes}) async {
    try {
      // አዲስ ኤክሴል ፋይል ካልተሰጠ አስቀድሞ የተጠናከረውን JSON እንጠቀማለን (ለፍጥነት እና ለ 10ሩም ክፍሎች ሙሉ እቅድ)
      if (fileBytes == null) {
        try {
          final String jsonStr = await rootBundle.loadString('assets/default_plans.json');
          final List<dynamic> jsonList = json.decode(jsonStr);
          return jsonList.map((e) => PlanItem.fromJson(e)).toList();
        } catch (_) {
          // fallback to reading excel
        }
      }

      Uint8List bytes;
      if (fileBytes != null) {
        bytes = fileBytes;
      } else {
        final ByteData data = await rootBundle.load('assets/plan_2019.xlsx');
        bytes = data.buffer.asUint8List();
      }

      final excel = Excel.decodeBytes(bytes);
      final List<PlanItem> plans = [];

      for (var table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet == null) continue;

        String currentDeptName = 'ልማትና በጎ አድራጎት ክፍል';
        String currentSubDept = 'አጠቃላይ';
        String currentMainTask = '';

        for (int r = 0; r < sheet.maxRows; r++) {
          final row = sheet.rows[r];
          if (row.isEmpty) continue;

          final combinedRowText = row.map((c) => c?.value?.toString().trim() ?? '').join(' ');
          if (combinedRowText.contains('ዓመታዊ የክንውን ዕቅድ') || combinedRowText.contains('የክንውን ዕቅድ')) {
            currentDeptName = mapDepartmentName(combinedRowText);
            continue;
          }

          if (combinedRowText.contains('ዐቢይ ተግባራት') || combinedRowText.contains('ዝርዝር ተግባራት') || combinedRowText.contains('1ኛ ሩብ')) {
            continue;
          }

          String subDept = (row.length > 1 ? row[1]?.value?.toString().trim() : '') ?? '';
          String mainTask = (row.length > 2 ? row[2]?.value?.toString().trim() : '') ?? '';
          String detailTask = (row.length > 3 ? row[3]?.value?.toString().trim() : '') ?? '';

          if (subDept.isNotEmpty && !subDept.startsWith('ተ.') && !subDept.contains('ንዑስ')) {
            currentSubDept = subDept;
          }
          if (mainTask.isNotEmpty && !mainTask.contains('ዐቢይ')) {
            currentMainTask = mainTask;
          }

          if (detailTask.isEmpty) {
            if (mainTask.isNotEmpty && mainTask.length > 5 && !mainTask.contains('ዐቢይ')) {
              detailTask = mainTask;
            } else {
              continue;
            }
          }

          String measurement = (row.length > 4 ? row[4]?.value?.toString().trim() : '') ?? '-';
          String quantity = (row.length > 5 ? row[5]?.value?.toString().trim() : '') ?? '-';

          Map<String, String> monthsMap = {};
          List<String> activeTimes = [];
          for (int c = 6; c < row.length && c < 18; c++) {
            final val = row[c]?.value?.toString().trim() ?? '';
            final monthName = (c - 6 < monthNames.length) ? monthNames[c - 6] : '';
            if (val.isNotEmpty && val != '-') {
              monthsMap[monthName] = val;
              activeTimes.add('$monthName ($val)');
            } else {
              monthsMap[monthName] = '';
            }
          }

          String executionTime = activeTimes.isNotEmpty ? activeTimes.join(', ') : 'ዓመቱን ሙሉ';
          String budget = (row.length > 18 ? row[18]?.value?.toString().trim() : '') ?? '-';
          String remarks = (row.length > 19 ? row[19]?.value?.toString().trim() : '') ?? '';

          plans.add(
            PlanItem(
              id: 'plan_${plans.length + 1}',
              departmentId: getDepartmentId(currentDeptName),
              departmentName: currentDeptName,
              subDepartment: currentSubDept,
              mainTask: currentMainTask.isNotEmpty ? currentMainTask : detailTask,
              detailTask: detailTask,
              measurement: measurement,
              quantity: quantity,
              executionTime: executionTime,
              budget: budget,
              remarks: remarks,
              months: monthsMap,
              progressPercent: 0,
            ),
          );
        }
      }

      return plans;
    } catch (e) {
      return [];
    }
  }
}
