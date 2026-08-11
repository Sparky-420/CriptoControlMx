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
  final expectedByKey = <String, List<int>>{};
  for (var i = 0; i < expected.length; i++) {
    expectedByKey.putIfAbsent(expected[i].key, () => <int>[]).add(i);
  }
  final actualByKey = <String, List<_Diag>>{};
  for (final diagnostic in actual) {
    actualByKey.putIfAbsent(diagnostic.key, () => <_Diag>[]).add(diagnostic);
  }
  for (final entry in expectedByKey.entries) {
    final candidates = actualByKey[entry.key];
    if (candidates == null || candidates.length != entry.value.length) {
      return 1;
    }
    if (sources != null &&
        anchors.isNotEmpty &&
        !_hasPerfectAnchorMatching(entry.value, candidates, anchors, sources)) {
      return 1;
    }
  }
  return 0;
}

bool _hasPerfectAnchorMatching(
  List<int> expectedIndices,
  List<_Diag> candidates,
  List<String> anchors,
  Map<String, String> sources,
) {
  final matchedExpectedByCandidate = List<int>.filled(candidates.length, -1);

  bool assign(int expectedIndex, Set<int> visitedCandidates) {
    for (
      var candidateIndex = 0;
      candidateIndex < candidates.length;
      candidateIndex++
    ) {
      if (visitedCandidates.contains(candidateIndex) ||
          !_anchorMatches(
            candidates[candidateIndex],
            anchors[expectedIndex],
            sources,
          )) {
        continue;
      }
      visitedCandidates.add(candidateIndex);
      final previousExpected = matchedExpectedByCandidate[candidateIndex];
      if (previousExpected < 0 || assign(previousExpected, visitedCandidates)) {
        matchedExpectedByCandidate[candidateIndex] = expectedIndex;
        return true;
      }
    }
    return false;
  }

  for (final expectedIndex in expectedIndices) {
    if (!assign(expectedIndex, <int>{})) {
      return false;
    }
  }
  return true;
}

bool _anchorMatches(
  _Diag candidate,
  String anchor,
  Map<String, String> sources,
) {
  final lines = sources[candidate.path]?.split('\n');
  return lines != null &&
      candidate.line >= 1 &&
      candidate.line <= lines.length &&
      lines[candidate.line - 1].contains(anchor);
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
