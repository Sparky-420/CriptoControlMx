import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('.gitignore keeps generated files and private backups out of git', () {
    final String content = File('.gitignore').readAsStringSync();

    expect(content, contains('.dart_tool/'));
    expect(content, contains('build/'));
    expect(content, contains('assets/import/backup_v2.json'));
    expect(content, contains('*.log'));
  });
}
