import 'dart:typed_data';

import 'office_export_service.dart';

/// Non-web implementation: save the bytes to the app documents folder.
/// Returns true when the file was written.
Future<bool> downloadBytes({
  required Uint8List bytes,
  required String fileName,
}) async {
  final path = await OfficeExportService.saveAndGetFilePath(
    fileName: fileName,
    bytes: bytes,
  );
  return path != null;
}
