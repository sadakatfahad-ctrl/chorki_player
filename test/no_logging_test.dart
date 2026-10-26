import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/ never writes to the console', () {
    final forbidden = RegExp(
      r'\b(print|debugPrint|debugPrintStack|log)\s*\('
      r'|dart:developer'
      r'|LogInterceptor'
      r'|FlutterError\.(reportError|presentError|dumpErrorToConsole)'
      r'|\b(stdout|stderr)\b',
    );

    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('//')) continue;
        if (forbidden.hasMatch(line)) offenders.add('${file.path}:${i + 1}');
      }
    }

    expect(offenders, isEmpty, reason: 'Logging found in: $offenders');
  });
}
