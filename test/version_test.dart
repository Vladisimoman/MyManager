import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_manager/core/version.dart';

void main() {
  test('версія в налаштуваннях збігається з pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)$').firstMatch(line.trim());
    expect(m, isNotNull, reason: 'version має бути у форматі 1.2.3+4');
    expect(m![1], appVersion);
    // Номер збірки росте з кожною версією (Android не ставить оновлення з меншим номером).
    expect(int.parse(m[2]!), greaterThanOrEqualTo(10));
  });
}
