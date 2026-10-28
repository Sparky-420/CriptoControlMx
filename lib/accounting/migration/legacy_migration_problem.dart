import '../adapters/legacy_movement_adapter.dart';
import '../support/sha256.dart';

enum LegacyMigrationProblemKind { unconvertible, conflictingId }

final class LegacyMigrationProblem {
  const LegacyMigrationProblem({
    required this.id,
    required this.kind,
    required this.sourceIndex,
    required this.primaryPayload,
    required this.conflictingPayload,
    required this.conversionIssues,
  });

  final String id;
  final LegacyMigrationProblemKind kind;
  final int sourceIndex;
  final Map<String, Object?> primaryPayload;
  final Map<String, Object?>? conflictingPayload;
  final List<LegacyConversionIssue> conversionIssues;

  factory LegacyMigrationProblem.create({
    required LegacyMigrationProblemKind kind,
    required int sourceIndex,
    required Map<String, Object?> primaryPayload,
    Map<String, Object?>? conflictingPayload,
    List<LegacyConversionIssue> conversionIssues =
        const <LegacyConversionIssue>[],
  }) => LegacyMigrationProblem(
    id: sha256Hex(
      canonicalJson(<String, Object?>{
        'kind': kind.name,
        'sourceIndex': sourceIndex,
        'primaryPayload': primaryPayload,
        'conflictingPayload': conflictingPayload,
      }),
    ),
    kind: kind,
    sourceIndex: sourceIndex,
    primaryPayload: Map<String, Object?>.unmodifiable(primaryPayload),
    conflictingPayload: conflictingPayload == null
        ? null
        : Map<String, Object?>.unmodifiable(conflictingPayload),
    conversionIssues: List<LegacyConversionIssue>.unmodifiable(
      conversionIssues,
    ),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind.name,
    'sourceIndex': sourceIndex,
    'primaryPayload': primaryPayload,
    'conflictingPayload': conflictingPayload,
    'conversionIssues': conversionIssues
        .map((issue) => issue.toJson())
        .toList(),
  };

  factory LegacyMigrationProblem.fromJson(Map<String, Object?> json) =>
      LegacyMigrationProblem(
        id: json['id']! as String,
        kind: LegacyMigrationProblemKind.values.byName(json['kind']! as String),
        sourceIndex: json['sourceIndex']! as int,
        primaryPayload: Map<String, Object?>.from(
          json['primaryPayload']! as Map,
        ),
        conflictingPayload: json['conflictingPayload'] == null
            ? null
            : Map<String, Object?>.from(json['conflictingPayload']! as Map),
        conversionIssues: (json['conversionIssues']! as List)
            .map(
              (value) => LegacyConversionIssue.fromJson(
                Map<String, Object?>.from(value as Map),
              ),
            )
            .toList(),
      );
}
