import 'accounting_amount.dart';
import 'accounting_movement.dart';

enum ProjectionIssueCode {
  missingSourceWallet,
  missingDestinationWallet,
  externalDestinationHasOwnedWallet,
  sameWalletTransfer,
  inconsistentTransferAmounts,
  incompleteAdjustment,
  invalidAmount,
  duplicateMovementId,
  insufficientCustody,
  observedBalanceMismatch,
  invalidReconciliationLink,
  linkedAdjustmentDeletion,
  malformedHistoricalMovement,
  missingWalletAssignment,
  unknownCostBasis,
  legacyAccountingSemantics,
  missingDestinationClassification,
  unknownWallet,
  inactiveWallet,
}

enum LedgerLegKind { custodyDebit, custodyCredit, performanceEvent, adjustment }

final class ProjectionIssue {
  const ProjectionIssue(this.code, this.movementId, this.message);

  final ProjectionIssueCode code;
  final String movementId;
  final String message;
}

final class LedgerLeg {
  const LedgerLeg({
    required this.movementId,
    required this.walletId,
    required this.asset,
    required this.kind,
    required this.quantity,
    required this.occurredAt,
  });

  final String movementId;
  final String walletId;
  final String asset;
  final LedgerLegKind kind;
  final AccountingAmount quantity;
  final DateTime occurredAt;
}

final class NormalizedLedger {
  const NormalizedLedger({
    required this.movements,
    required this.legs,
    required this.issues,
    required this.acceptedMovementIds,
  });

  final List<AccountingMovement> movements;
  final List<LedgerLeg> legs;
  final List<ProjectionIssue> issues;
  final Set<String> acceptedMovementIds;

  bool get isValid => issues.isEmpty;
}
