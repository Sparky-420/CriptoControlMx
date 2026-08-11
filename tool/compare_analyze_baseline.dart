import 'dart:io';

final class _Diag {
  const _Diag(this.key, this.path, this.line);
  final String key;
  final String path;
  final int line;
}

int compareAnalyzeReports(
  String baselineMarkdown,
  String currentOutput, {
  int maximumTotal = 30,
  Map<String, String>? sources,
}) {
  final expected = _diags(baselineMarkdown);
  final actual = _diags(currentOutput);
  if (expected.length != actual.length || actual.length > maximumTotal) {
    return 1;
  }
  final anchors = _anchors(baselineMarkdown);
  if (sources != null &&
      anchors.isNotEmpty &&
      anchors.length != expected.length) {
    return 1;
  }
  final remaining = List<_Diag>.from(actual);
  for (var i = 0; i < expected.length; i++) {
    final index = remaining.indexWhere((d) => d.key == expected[i].key);
    if (index < 0) {
      return 1;
    }
    final matched = remaining.removeAt(index);
    if (sources != null && anchors.isNotEmpty) {
      final text = sources[matched.path];
      final lines = text?.split('\n');
      if (lines == null ||
          matched.line < 1 ||
          matched.line > lines.length ||
          !lines[matched.line - 1].contains(anchors[i])) {
        return 1;
      }
    }
  }
  return 0;
}

List<_Diag> _diags(String text) {
  final r = RegExp(
    r'^\s*(info|warning|error) - (.+) - (.+):(\d+):(\d+) - ([\w_]+)\s*$',
    multiLine: true,
  );
  return r.allMatches(text).map((m) {
    final path = m[3]!.replaceAll('\\', '/');
    return _Diag('${m[1]}|$path|${m[6]}|${m[2]}', path, int.parse(m[4]!));
  }).toList();
}

List<String> _anchors(String markdown) {
  final start = markdown.indexOf('### Huella con anclas verificables');
  if (start < 0) return <String>[];
  final section = markdown.substring(start);
  final r = RegExp(r'^\|\s*\d+\s*\|[^\n]*\|\s*`([^`]+)`', multiLine: true);
  return r.allMatches(section).map((m) => m[1]!).toList();
}

void main(List<String> args) {
  if (args.length != 2) {
    exitCode = 64;
    return;
  }
  final root = Directory.current;
  exitCode = compareAnalyzeReports(
    File(args[0]).readAsStringSync(),
    File(args[1]).readAsStringSync(),
    sources: <String, String>{
      'lib/cripto_control_app.dart': File(
        '${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}cripto_control_app.dart',
      ).readAsStringSync(),
    },
  );
}
