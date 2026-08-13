import '../persistence/accounting_document.dart';
import 'legacy_migration_problem.dart';

final class MigrationReport {
  const MigrationReport({
    required this.document,
    required this.imported,
    required this.skippedDuplicates,
    required this.unassignedMovementIds,
    required this.problems,
  });
  final AccountingDocument document;
  final int imported;
  final int skippedDuplicates;
  final List<String> unassignedMovementIds;
  final List<LegacyMigrationProblem> problems;
}
