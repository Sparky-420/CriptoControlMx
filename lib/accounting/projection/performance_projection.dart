import '../domain/accounting_amount.dart';
import '../domain/ledger_validation.dart';
import 'custody_projection.dart';

enum SaleAccountingStatus { complete, partiallyKnown, insufficientCustody }

final class SaleResult {
  const SaleResult({
    required this.movementId,
    required this.status,
    required this.totalQuantity,
    required this.knownQuantity,
    required this.demonstratedCostBasis,
    required this.knownProceeds,
    required this.allocatedKnownFiatFee,
    required this.realizedPnlKnown,
    required this.pendingCostQuantity,
  });

  final String movementId;
  final SaleAccountingStatus status;
  final AccountingAmount totalQuantity;
  final AccountingAmount knownQuantity;
  final AccountingAmount demonstratedCostBasis;
  final AccountingAmount knownProceeds;
  final AccountingAmount allocatedKnownFiatFee;
  final AccountingAmount realizedPnlKnown;
  final AccountingAmount pendingCostQuantity;

  bool get hasDefinitiveTotal => status == SaleAccountingStatus.complete;
}

final class PerformancePosition {
  const PerformancePosition({
    required this.knownQuantity,
    required this.knownCostBasis,
    required this.averageCost,
    required this.investedCapital,
    required this.realizedPnlKnown,
    required this.unrealizedPnlKnown,
    required this.pendingPnlQuantity,
    required this.blockingMovementIds,
    required this.issues,
  });

  final AccountingAmount knownQuantity;
  final AccountingAmount knownCostBasis;
  final AccountingAmount averageCost;
  final AccountingAmount investedCapital;
  final AccountingAmount realizedPnlKnown;
  final AccountingAmount unrealizedPnlKnown;
  final AccountingAmount pendingPnlQuantity;
  final List<String> blockingMovementIds;
  final List<ProjectionIssue> issues;
}

base class TransferAllocation {
  const TransferAllocation({
    required this.totalDebited,
    required this.knownQuantity,
    required this.unknownQuantity,
    required this.transferredCostBasis,
  });

  final AccountingAmount totalDebited;
  final AccountingAmount knownQuantity;
  final AccountingAmount unknownQuantity;
  final AccountingAmount transferredCostBasis;
}

final class PerformanceProjection {
  const PerformanceProjection(
    this.positions,
    this.sales, {
    this.transferAllocations = const <String, TransferAllocation>{},
  });

  final Map<WalletAssetKey, PerformancePosition> positions;
  final List<SaleResult> sales;
  final Map<String, TransferAllocation> transferAllocations;
}
