import 'dart:io';
import 'dart:convert';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: (data) async {
      if (data == null) return;
      final file = File(
        '${Platform.environment['D2F_SCREENSHOT_DIR'] ?? 'design/verification'}/journey-result.json',
      );
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert(Map<String, dynamic>.from(data)..remove('screenshots')),
      );
    },
    onScreenshot: (name, bytes, [args]) async {
      final file = File(
        '${Platform.environment['D2F_SCREENSHOT_DIR'] ?? 'design/verification'}/$name.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
