import 'dart:io';

void main() {
  final List<String> protectedFiles = <String>[
    'lib/cripto_control_app.dart',
    'assets/import/backup_v2.json',
  ];

  stdout.writeln('CriptoControlMx safe refactor guard');
  stdout.writeln('Protected files:');

  for (final String file in protectedFiles) {
    stdout.writeln('- $file');
  }

  stdout.writeln('Rule: UI extraction must not change finance behavior without tests.');
}
