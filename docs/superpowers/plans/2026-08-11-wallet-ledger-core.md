# Wallet Ledger Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Crear el núcleo contable modular: modelos exactos, validación, normalización determinista, proyecciones separadas de custodia/rendimiento y adaptadores mínimos hacia el motor histórico.

**Architecture:** Los movimientos canónicos son eventos inmutables. `MovementNormalizer` valida y deriva piernas sin duplicar persistencia; `CustodyProjector` y `PerformanceProjector` reproducen todo el ledger ordenado; `AccountingLedgerEngine` combina resultados sin duplicar fórmulas.

**Tech Stack:** Dart 3.9 puro, Flutter test, `BigInt` para decimal exacto; sin paquetes nuevos.

## Global Constraints

- Ejecutar desde el worktree `feature/carteras-contables`.
- Conservar costo promedio ponderado para la porción conocida; no cambiar silenciosamente `FinancialEngine`.
- `balanceAdjustment` no entra en rendimiento.
- `knownFirst` sólo para ventas; transferencias proporcionales.
- Una transferencia interna persistida produce dos piernas derivadas.
- Después de cada tarea ejecutar la comparación estructural de análisis definida en el rollout; detener y corregir cualquier diagnóstico nuevo.
- Los fragmentos siguientes son especificaciones de implementación; este documento no autoriza ejecutarlas en la fase de planificación.

---

### Task CORE-1: Definir decimal exacto, modelos y contrato de diagnóstico

**Purpose:** Establecer tipos canónicos sin `double`, serialización estable y el comparador de baseline que usarán todas las tareas.

**Files:**
- Create: `lib/accounting/domain/accounting_amount.dart`
- Create: `lib/accounting/domain/movement_type.dart`
- Create: `lib/accounting/domain/wallet.dart`
- Create: `lib/accounting/domain/accounting_movement.dart`
- Create: `tool/compare_analyze_baseline.dart`
- Create: `test/accounting/domain/accounting_amount_test.dart`
- Create: `test/accounting/domain/wallet_test.dart`
- Create: `test/accounting/domain/accounting_movement_test.dart`
- Create: `test/tool/compare_analyze_baseline_test.dart`
- Modify: `lib/cripto_control_app.dart`
- Existing symbols affected: `MovementType` (24118), `MovementLabel` (24382) y parser de tipo; el enum se extrae sin cambiar los otros modelos monolíticos.

**Consumes:** `BigInt`, ISO-8601 UTC/local-offset strings, analyzer text and the approved baseline Markdown.

**Produces:**

```dart
final class AccountingAmount implements Comparable<AccountingAmount> {
  const AccountingAmount._(this.coefficient, this.scale);
  final BigInt coefficient;
  final int scale;
  static AccountingAmount parse(String value);
  static AccountingAmount fromInt(int value);
  static final AccountingAmount zero = AccountingAmount.fromInt(0);
  AccountingAmount operator +(AccountingAmount other);
  AccountingAmount operator -(AccountingAmount other);
  AccountingAmount operator *(AccountingAmount other);
  AccountingAmount divide(AccountingAmount other, {int scale = 18});
  AccountingAmount min(AccountingAmount other);
  AccountingAmount max(AccountingAmount other);
  String toJson();
}
final class AccountingTolerance {
  static final AccountingAmount legacyImport =
      AccountingAmount.parse('0.00000001');
  const AccountingTolerance._();
}

enum WalletStatus { active, archived }
enum DestinationType { ownWallet, external }
enum WalletAssignmentStatus { assigned, partiallyAssigned, pending, legacyUnassigned }
enum AccountingCompleteness { complete, partiallyKnown, pendingAssignment, unassignedLegacy }
enum FiatFeeTreatment { none, valuationOfCryptoFee, paidSeparately, combined }
enum SaleCostConsumptionPolicy { knownFirst }
enum TransferCostAllocationPolicy { proportional }
enum LegacyAccountingPolicy { preservePreviousGlobal }
enum MovementType { buy, sell, transferIn, transferOut, balanceAdjustment }

final class WalletImageRef {
  const WalletImageRef({required this.id, required this.fileName,
    required this.mimeType, required this.sha256, required this.width,
    required this.height, required this.byteLength});
  final String id;
  final String fileName;
  final String mimeType;
  final String sha256;
  final int width;
  final int height;
  final int byteLength;
  Map<String, Object?> toJson();
  factory WalletImageRef.fromJson(Map<String, Object?> json);
}

final class Wallet {
  const Wallet({required this.id, required this.name, required this.provider,
    required this.status, required this.createdAt, required this.updatedAt,
    this.imageRef, this.colorArgb, this.note, this.schemaVersion = 1});
  final String id;
  final String name;
  final String provider;
  final WalletImageRef? imageRef;
  final int? colorArgb;
  final String? note;
  final WalletStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int schemaVersion;
  Map<String, Object?> toJson();
  factory Wallet.fromJson(Map<String, Object?> json);
}

final class ReconciliationLink {
  const ReconciliationLink({required this.adjustmentMovementId,
    required this.quantityResolved});
  final String adjustmentMovementId;
  final AccountingAmount quantityResolved;
  Map<String, Object?> toJson();
  factory ReconciliationLink.fromJson(Map<String, Object?> json);
}

final class AccountingMovement {
  const AccountingMovement({required this.id, required this.type,
    required this.asset, required this.occurredAt,
    required this.fiatFeeAmount, required this.walletAssignmentStatus,
    required this.cryptoFeeAmount, required this.fiatFeeTreatment,
    required this.reconciliationLinks,
    required this.createdAt, required this.updatedAt,
    this.schemaVersion = 3, this.quantity, this.unitPriceFiat,
    this.sourceWalletId, this.destinationWalletId, this.destinationType,
    this.externalRecipientName, this.externalDestinationPlatform,
    this.receivedAmount, this.cryptoFeeAsset,
    this.totalDebitedAmount, this.feeFiatValue, this.network, this.note,
    this.adjustmentWalletId, this.adjustmentQuantity,
    this.observedBalance, this.adjustmentReason});
  final String id;
  final MovementType type;
  final String asset;
  final DateTime occurredAt;
  final AccountingAmount? quantity;
  final AccountingAmount? unitPriceFiat;
  final AccountingAmount fiatFeeAmount;
  final String? sourceWalletId;
  final String? destinationWalletId;
  final DestinationType? destinationType;
  final String? externalRecipientName;
  final String? externalDestinationPlatform;
  final WalletAssignmentStatus walletAssignmentStatus;
  final AccountingAmount? receivedAmount;
  final AccountingAmount cryptoFeeAmount;
  final String? cryptoFeeAsset;
  final AccountingAmount? totalDebitedAmount;
  final AccountingAmount? feeFiatValue;
  final FiatFeeTreatment fiatFeeTreatment;
  final String? network;
  final String? note;
  final String? adjustmentWalletId;
  final AccountingAmount? adjustmentQuantity;
  final AccountingAmount? observedBalance;
  final String? adjustmentReason;
  final List<ReconciliationLink> reconciliationLinks;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int schemaVersion;
  AccountingMovement copyWith({String? id, MovementType? type, String? asset,
    DateTime? occurredAt, Object? quantity = unset,
    Object? unitPriceFiat = unset, AccountingAmount? fiatFeeAmount,
    Object? sourceWalletId = unset, Object? destinationWalletId = unset,
    Object? destinationType = unset, Object? externalRecipientName = unset,
    Object? externalDestinationPlatform = unset,
    WalletAssignmentStatus? walletAssignmentStatus,
    Object? receivedAmount = unset, AccountingAmount? cryptoFeeAmount,
    Object? cryptoFeeAsset = unset, Object? totalDebitedAmount = unset,
    Object? feeFiatValue = unset, FiatFeeTreatment? fiatFeeTreatment,
    Object? network = unset, Object? note = unset,
    Object? adjustmentWalletId = unset, Object? adjustmentQuantity = unset,
    Object? observedBalance = unset, Object? adjustmentReason = unset,
    List<ReconciliationLink>? reconciliationLinks, DateTime? createdAt,
    DateTime? updatedAt, int? schemaVersion});
  Map<String, Object?> toJson();
  factory AccountingMovement.fromJson(Map<String, Object?> json);
}
final class _Unset { const _Unset(); }
const Object unset = _Unset();
```

**First RED test code:**

The code in Step 1 is written before any production type.

- [ ] **Step 1 — Write RED amount test.** Add this real test first:

```dart
test('keeps Mercado Pago quantities exact through arithmetic and JSON', () {
  final received = AccountingAmount.parse('1');
  final fee = AccountingAmount.parse('0.00167532');
  final observed = AccountingAmount.parse('127.75883985');
  expect((received + fee).toJson(), '1.00167532');
  expect(AccountingAmount.parse(observed.toJson()), observed);
});
```

Run: `flutter test test/accounting/domain/accounting_amount_test.dart`
Expected RED: import/file or `AccountingAmount` not found.

- [ ] **Step 2 — Implement the minimal normalized decimal.** Reject exponent notation and malformed signs; align scales for add/subtract/compare; strip trailing fractional zeroes; make `zero` canonical. V3 equations compare exactly; only adapters of historical numeric doubles may use `AccountingTolerance.legacyImport`, defined once. Run the same command and expect GREEN.

- [ ] **Step 3 — Write RED model round-trip tests.** Instantiate a wallet and a `balanceAdjustment` with `adjustmentQuantity: 0.75883985`, `observedBalance: 127.75883985`, reason and notes; assert exact JSON keys and that `copyWith(sourceWalletId: null)` clears the field. Run: `flutter test test/accounting/domain/wallet_test.dart test/accounting/domain/accounting_movement_test.dart`. Expected RED: types/serializers absent.

- [ ] **Step 4 — Implement models exactly as produced above.** Define `MovementType` in `movement_type.dart`, impórtalo desde el monolito, retira sólo la declaración anterior y añade `balanceAdjustment` a label/parser exhaustivos. Encode amounts as canonical decimal strings, enums by `.name`, dates by `toIso8601String()`, schema as integer `3`, and omit no required field. Run the model tests and existing movement parser tests; expect GREEN.

- [ ] **Step 5 — Test and implement the analyzer comparator.** Fixture baseline/current lines must prove tuple equality independent of order, rejection of a new message under an existing rule, and rejection above 30. Public entry: `int compareAnalyzeReports(String baselineMarkdown, String currentOutput, {int maximumTotal = 30})`. Run: `flutter test test/tool/compare_analyze_baseline_test.dart`; expect RED before and GREEN after implementation.

- [ ] **Step 6 — Verify regressions and diagnostics.** Run `dart format --output=none --set-exit-if-changed lib/accounting/domain tool test/accounting/domain test/tool`, the four new test files, `flutter test`, the rollout analysis comparison, and `git diff --check`. Expected: all tests GREEN; no new analyzer tuple.

- [ ] **Step 7 — Commit only the enumerated files.** Run `git add lib/accounting/domain/accounting_amount.dart lib/accounting/domain/movement_type.dart lib/accounting/domain/wallet.dart lib/accounting/domain/accounting_movement.dart lib/cripto_control_app.dart tool/compare_analyze_baseline.dart test/accounting/domain/accounting_amount_test.dart test/accounting/domain/wallet_test.dart test/accounting/domain/accounting_movement_test.dart test/tool/compare_analyze_baseline_test.dart && git commit -m "feat(accounting): define exact wallet ledger domain"`.

---

### Task CORE-2: Validar y normalizar movimientos con orden determinista

**Purpose:** Convertir movimientos canónicos en una secuencia inequívoca de piernas válidas, sin persistir duplicados.

**Files:**
- Create: `lib/accounting/domain/ledger_validation.dart`
- Create: `lib/accounting/domain/movement_normalizer.dart`
- Create: `test/accounting/domain/movement_normalizer_test.dart`
- Modify: `lib/accounting/domain/accounting_movement.dart`
- Existing symbols affected: `AccountingMovement` from CORE-1 only.

**Consumes:** `AccountingMovement`, `Wallet`, `DestinationType`.

**Produces:**

```dart
enum ProjectionIssueCode { missingSourceWallet, missingDestinationWallet,
  externalDestinationHasOwnedWallet, sameWalletTransfer,
  inconsistentTransferAmounts, incompleteAdjustment, invalidAmount,
  duplicateMovementId, insufficientCustody, observedBalanceMismatch,
  invalidReconciliationLink, linkedAdjustmentDeletion,
  malformedHistoricalMovement }
enum LedgerLegKind { custodyDebit, custodyCredit, performanceEvent, adjustment }
final class ProjectionIssue {
  const ProjectionIssue(this.code, this.movementId, this.message);
  final ProjectionIssueCode code;
  final String movementId;
  final String message;
}
final class LedgerLeg {
  const LedgerLeg({required this.movementId, required this.walletId,
    required this.asset, required this.kind, required this.quantity,
    required this.occurredAt});
}
final class NormalizedLedger {
  const NormalizedLedger({required this.movements, required this.legs,
    required this.issues});
  final List<AccountingMovement> movements;
  final List<LedgerLeg> legs;
  final List<ProjectionIssue> issues;
  bool get isValid => issues.isEmpty;
}
abstract interface class MovementNormalizer {
  NormalizedLedger normalize(List<AccountingMovement> movements);
}
final class DefaultMovementNormalizer implements MovementNormalizer {
  const DefaultMovementNormalizer();
  @override NormalizedLedger normalize(List<AccountingMovement> movements);
}
```

**First RED test code:**

```dart
test('sorts by instant and then id without mutating input', () {
  final input = <AccountingMovement>[
    movement(id: 'b', occurredAt: DateTime.utc(2026, 7, 30, 20, 54)),
    movement(id: 'z', occurredAt: DateTime.utc(2026, 7, 30, 20, 53)),
    movement(id: 'a', occurredAt: DateTime.utc(2026, 7, 30, 20, 54)),
  ];
  final result = const DefaultMovementNormalizer().normalize(input);
  expect(result.movements.map((value) => value.id), <String>['z', 'a', 'b']);
  expect(input.map((value) => value.id), <String>['b', 'z', 'a']);
});
```

- [ ] **Step 1 — Write RED deterministic-order test.** Use three events with equal/different `occurredAt` and IDs `b`, `a`, `z`; assert exact order `z,a,b` where `z` has earlier time. Run `flutter test test/accounting/domain/movement_normalizer_test.dart`; expected RED: normalizer missing.

- [ ] **Step 2 — Implement stable ordering.** Copy before sorting; compare `occurredAt.toUtc()`, then case-sensitive `id`; reject duplicate IDs with an issue rather than discard history. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED internal-transfer test.** The test creates one `transferOut` with `destinationType: ownWallet`, source `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa`, destination `bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb`, quantity/received `1`, fee `0.00167532`, debit `1.00167532`; assert input length one and exactly one debit plus one credit leg sharing the movement ID. Run the test; expected RED: legs absent/wrong.

- [ ] **Step 4 — Implement role, transfer and adjustment validation.** New `buy` requires only `destinationWalletId`; new `sell` requires only `sourceWalletId`. A persisted internal movement is only `transferOut`: `ownWallet` requires distinct source/destination IDs and forbids external fields. External `transferOut` requires source, external recipient/platform and null destination wallet. `transferIn` is reserved for external incoming or historical input; an assigned one requires `destinationWalletId`, null source and null `destinationType`, while legacy-unassigned input may omit the wallet. It never models the credit leg of an internal transfer. `balanceAdjustment` requires adjustment wallet, signed nonzero quantity, observed balance and reason. Never examine platform names to infer ownership. Re-run; expect GREEN.

- [ ] **Step 5 — Add invalid-case tests.** Assert issue codes for same-wallet internal transfer, owned wallet on external destination, inconsistent received+fee/debit and incomplete adjustment. Run: `flutter test test/accounting/domain/movement_normalizer_test.dart`; expect RED before checks, GREEN after.

- [ ] **Step 6 — Verify regression/analyze.** Run formatter check, the normalizer test, all accounting domain tests, `flutter test`, structured analyzer comparison, and `git diff --check`. Expected: no new tuple and all previous tests green.

- [ ] **Step 7 — Commit.** `git add lib/accounting/domain/accounting_movement.dart lib/accounting/domain/ledger_validation.dart lib/accounting/domain/movement_normalizer.dart test/accounting/domain/movement_normalizer_test.dart && git commit -m "feat(accounting): normalize wallet ledger events"`.

---

### Task CORE-3: Proyectar custodia y reconstruir ajustes exactamente

**Purpose:** Derivar tenencia conciliada, posición conocida, diferencia desconocida y déficit sin contaminar rendimiento.

**Files:**
- Create: `lib/accounting/projection/custody_projection.dart`
- Create: `lib/accounting/projection/custody_projector.dart`
- Create: `test/accounting/projection/custody_projection_test.dart`
- Create: `test/accounting/projection/ledger_rebuild_test.dart`
- Existing symbols affected: none.

**Consumes:** `NormalizedLedger`, `AccountingAmount`.

**Produces:**

```dart
final class WalletAssetKey {
  const WalletAssetKey(this.walletId, this.asset);
  final String walletId;
  final String asset;
  @override bool operator ==(Object other);
  @override int get hashCode;
}
final class CustodyPosition {
  const CustodyPosition({required this.reconciledQuantity,
    required this.appliedCredits, required this.appliedDebits,
    required this.signedAdjustments, required this.resolvedAdjustmentQuantity,
    required this.requestedQuantity, required this.unappliedQuantity,
    required this.contributingMovementIds, required this.issues,
    this.lastObservedBalance});
  final AccountingAmount reconciledQuantity;
  final AccountingAmount appliedCredits;
  final AccountingAmount appliedDebits;
  final AccountingAmount signedAdjustments;
  final AccountingAmount resolvedAdjustmentQuantity;
  final AccountingAmount? lastObservedBalance;
  final AccountingAmount requestedQuantity;
  final AccountingAmount unappliedQuantity;
  final List<String> contributingMovementIds;
  final List<ProjectionIssue> issues;
}
final class CustodyProjection {
  const CustodyProjection(this.positions, this.adjustmentHistory,
    this.effectsByMovementId);
  final Map<WalletAssetKey, CustodyPosition> positions;
  final List<AccountingMovement> adjustmentHistory;
  final Map<String, List<CustodyMovementEffect>> effectsByMovementId;
}
final class CustodyMovementEffect {
  const CustodyMovementEffect({required this.key, required this.before,
    required this.requested, required this.applied,
    required this.unapplied, required this.after});
  final WalletAssetKey key;
  final AccountingAmount before;
  final AccountingAmount requested;
  final AccountingAmount applied;
  final AccountingAmount unapplied;
  final AccountingAmount after;
}
abstract interface class CustodyProjector {
  CustodyProjection project(NormalizedLedger ledger);
}
final class DifferenceReconciliationService {
  AccountingMovement link(AccountingMovement accountingMovement,
    {required AccountingMovement adjustment,
    required AccountingAmount justifiedQuantity});
}
```

**First RED test code:**

```dart
test('positive adjustment changes custody but not known position', () {
  final result = projectCustody(<AccountingMovement>[
    buy(quantity: '127', walletId: '11111111-1111-4111-8111-111111111111'),
    adjustment(quantity: '0.75883985', observed: '127.75883985'),
  ]).positions[const WalletAssetKey(
      '11111111-1111-4111-8111-111111111111', 'UNI')]!;
  expect(result.reconciledQuantity.toJson(), '127.75883985');
  expect(result.signedAdjustments.toJson(), '0.75883985');
  expect(result.lastObservedBalance!.toJson(), '127.75883985');
  expect(result.unappliedQuantity, AccountingAmount.zero);
});
```

- [ ] **Step 1 — Write RED positive/negative custody tests.** Buy 127 UNI in one wallet, apply `+0.75883985`, assert reconciled `127.75883985`, signed adjustment and observed balance; separately apply `-2` and assert reconciled `125`, without any performance field in `CustodyPosition`. The difference/unknown/deficit assertions are written in CORE-6 where both projections exist. Run `flutter test test/accounting/projection/custody_projection_test.dart`; expected RED: projector missing.

- [ ] **Step 2 — Implement custody replay only.** Compute credits, debits, signed/resolved adjustments, observed balance, requested/applied/unapplied quantities, contributors and issues. Do not read cost basis or calculate known/unknown pools here. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED adjustment-isolation and observed-balance tests.** Project the same ledger before/after changing an adjustment and assert only custody fields and adjustment history change; no performance type is accepted by this result. Supply an `observedBalance` inconsistent with prior custody plus adjustment and assert `ProjectionIssueCode.observedBalanceMismatch` without rewriting the entered values. Run the custody test; expected RED until strict event handling exists.

- [ ] **Step 4 — Implement adjustment replay.** Index every real movement’s links by `adjustmentMovementId`; apply `sign(adjustmentQuantity) * (abs(adjustmentQuantity) - sum(quantityResolved))` only to `adjustmentWalletId`/asset. `quantityResolved` is always positive. Retain motive, observed balance, note and timestamps in ordered audit history; do not synthesize buy/sell/transfer legs. Re-run; expect GREEN.

- [ ] **Step 5 — Write and satisfy exact rebuild/reconciliation tests.** Create ledger, edit adjustment by replacing same ID, then delete it and replay from the complete remaining event list; assert byte-equivalent canonical position maps to expected stages. Then add `ReconciliationLink(adjustmentMovementId: 'adj-1', quantityResolved: 0.5)` to a real buy of the same wallet/asset: assert the buy contributes custody/cost and the referenced adjustment contributes only its unlinked remainder, so tenencia is not duplicated. Reject link magnitude above adjustment and mismatched wallet/asset/sign; deleting a linked adjustment is blocked until links are resolved. Run `flutter test test/accounting/projection/ledger_rebuild_test.dart`; expected RED before `LedgerRebuilder.rebuild(List<AccountingMovement>)` and `DifferenceReconciliationService`, GREEN after their minimal implementations.

- [ ] **Step 6 — Verify regression/analyze.** Run formatter, both new tests, all `test/accounting/`, full `flutter test`, analyzer tuple comparison and `git diff --check`.

- [ ] **Step 7 — Commit.** `git add lib/accounting/projection/custody_projection.dart lib/accounting/projection/custody_projector.dart test/accounting/projection/custody_projection_test.dart test/accounting/projection/ledger_rebuild_test.dart && git commit -m "feat(accounting): derive wallet custody projection"`.

---

### Task CORE-4: Proyectar rendimiento con ventas known-first

**Purpose:** Mantener costo promedio histórico para cantidad conocida y representar ventas parcial o totalmente demostradas sin costo cero ficticio.

**Files:**
- Create: `lib/accounting/projection/performance_projection.dart`
- Create: `lib/accounting/projection/performance_projector.dart`
- Create: `test/accounting/projection/sale_known_first_test.dart`
- Modify: `lib/accounting/projection/custody_projection.dart`
- Existing symbols affected: `FinancialEngine.computeStats` (`lib/cripto_control_app.dart:24449`) sólo como oráculo de regresión, no se modifica aquí.

**Consumes:** `NormalizedLedger`, `CustodyProjection`, `SaleCostConsumptionPolicy.knownFirst`.

**Produces:**

```dart
enum SaleAccountingStatus { complete, partiallyKnown, insufficientCustody }
final class SaleResult {
  const SaleResult({required this.movementId, required this.status,
    required this.totalQuantity, required this.knownQuantity,
    required this.demonstratedCostBasis, required this.knownProceeds,
    required this.allocatedKnownFiatFee, required this.realizedPnlKnown,
    required this.pendingCostQuantity});
  final String movementId;
  final SaleAccountingStatus status;
  final AccountingAmount totalQuantity;
  final AccountingAmount knownQuantity;
  final AccountingAmount demonstratedCostBasis;
  final AccountingAmount knownProceeds;
  final AccountingAmount allocatedKnownFiatFee;
  final AccountingAmount realizedPnlKnown;
  final AccountingAmount pendingCostQuantity;
}
final class PerformancePosition {
  const PerformancePosition({required this.knownQuantity,
    required this.knownCostBasis, required this.averageCost,
    required this.investedCapital, required this.realizedPnlKnown,
    required this.unrealizedPnlKnown, required this.pendingPnlQuantity,
    required this.blockingMovementIds, required this.issues});
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
final class PerformanceProjection {
  const PerformanceProjection(this.positions, this.sales);
  final Map<WalletAssetKey, PerformancePosition> positions;
  final List<SaleResult> sales;
}
abstract interface class PerformanceProjector {
  PerformanceProjection project(NormalizedLedger ledger,
    CustodyProjection custody,
    Map<String, AccountingAmount> currentPrices,
    {required SaleCostConsumptionPolicy salePolicy,
    required TransferCostAllocationPolicy transferPolicy});
}
```

**First RED test code:**

```dart
test('sale below known quantity has a definitive known result', () {
  final result = projectSales(known: '10', custody: '12', sold: '4',
      averageCost: '20', proceeds: '100').sales.single;
  expect(result.status, SaleAccountingStatus.complete);
  expect(result.knownQuantity.toJson(), '4');
  expect(result.demonstratedCostBasis.toJson(), '80');
  expect(result.knownProceeds.toJson(), '100');
  expect(result.allocatedKnownFiatFee, AccountingAmount.zero);
  expect(result.realizedPnlKnown.toJson(), '20');
  expect(result.pendingCostQuantity, AccountingAmount.zero);
});
```

- [ ] **Step 1 — Write RED tests for sale below and exactly known quantity.** Buy 10 at MXN 20 plus existing fiat fee behavior; sell 4, then in a separate case 10. Assert weighted-average cost removal, complete status, pending zero and same result as `FinancialEngine.computeStats` for known-only input. Run `flutter test test/accounting/projection/sale_known_first_test.dart`; expected RED: projector missing.

- [ ] **Step 2 — Implement weighted-average known segment.** Calculate `averageCost=knownCostBasis/knownQuantity`, consume `min(sold, knownAvailable)` and preserve the legacy fee treatment; do not round internally. Populate invested capital and known P&L fields without reading adjustments. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED partially-known test.** Known 10, reconciled 12, sell 11; assert total 11, known 10, demonstrated cost exact, proceeds and fiat sale fee allocated to the known portion by quantity at the same unit price, known P&L only, pending 1, `partiallyKnown`; assert display-facing result does not expose known P&L as a definitive total. Run test; expected RED: unknown portion treated incorrectly.

- [ ] **Step 4 — Implement known-first explicitly.** Switch on `SaleCostConsumptionPolicy`; consume known first and then unknown; never assume zero cost for pending quantity. Add `bool get hasDefinitiveTotal => status == SaleAccountingStatus.complete`. Re-run; expect GREEN.

- [ ] **Step 5 — Write RED insufficient-custody test.** Reconciled 8, attempt sale 9; assert `insufficientCustody`, no negative projected holding, movement remains in `sales`, and a typed ledger issue is retained. Implement validation-before-processing without deleting the event. Run test; expect RED then GREEN.

- [ ] **Step 6 — Verify regression/analyze.** Run formatter, sale test, accounting tests, `test/accounting_hotfix_test.dart`, full suite, analyzer tuple comparison and diff check.

- [ ] **Step 7 — Commit.** `git add lib/accounting/projection/custody_projection.dart lib/accounting/projection/performance_projection.dart lib/accounting/projection/performance_projector.dart test/accounting/projection/sale_known_first_test.dart && git commit -m "feat(accounting): project known-first sale results"`.

---

### Task CORE-5: Proyectar transferencias proporcionales y comisiones explícitas

**Purpose:** Trasladar/retirar proporcionalmente segmentos conocidos y desconocidos, y aplicar cada comisión una sola vez.

**Files:**
- Create: `lib/accounting/projection/fee_effect.dart`
- Modify: `lib/accounting/projection/custody_projector.dart`
- Modify: `lib/accounting/projection/performance_projector.dart`
- Create: `test/accounting/projection/transfer_projection_test.dart`
- Create: `test/accounting/projection/fee_projection_test.dart`
- Existing symbols affected: none in monolith.

**Consumes:** `TransferCostAllocationPolicy.proportional`, normalized internal/external transfer legs, `FiatFeeTreatment`.

**Produces:**

```dart
final class TransferAllocation {
  const TransferAllocation({required this.totalDebited,
    required this.knownQuantity, required this.unknownQuantity,
    required this.transferredCostBasis});
  final AccountingAmount totalDebited;
  final AccountingAmount knownQuantity;
  final AccountingAmount unknownQuantity;
  final AccountingAmount transferredCostBasis;
}
final class FeeEffect {
  const FeeEffect({required this.assetCustodyDebit,
    required this.otherAssetCustodyDebit, required this.fiatCostEffect});
  final AccountingAmount assetCustodyDebit;
  final Map<String, AccountingAmount> otherAssetCustodyDebit;
  final AccountingAmount fiatCostEffect;
}
FeeEffect resolveFeeEffect(AccountingMovement movement);
```

**First RED test code:**

```dart
test('transfer consumes known and unknown segments proportionally', () {
  final allocation = projectTransfer(custody: '12', known: '10', debit: '6');
  expect(allocation.knownQuantity.toJson(), '5');
  expect(allocation.unknownQuantity.toJson(), '1');
  expect(allocation.totalDebited.toJson(), '6');
});
```

- [ ] **Step 1 — Write RED proportional-policy test.** With custody 12 and known 10, transfer 6; assert allocation known 5, unknown 1, not known 6/unknown 0. Run `flutter test test/accounting/projection/transfer_projection_test.dart`; expected RED: transfer allocation absent.

- [ ] **Step 2 — Implement proportional allocation once.** Ratio is debit/custody-before; known and unknown segments multiply by the ratio; cost basis moves with known ratio. Internal credit receives the same segment mix; external transfer removes it. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED one-event internal/external tests.** Internal: one persisted `transferOut` yields source debit and owned destination credit without P&L. External: null destination wallet, recipient/platform text, no owned credit, realized P&L zero. Add historical transfer requesting 2 from custody 1 and assert applied 1, unapplied 1, typed issue and no negative balance; a new equivalent transfer is rejected before save. Run test; expected RED before projection integration, GREEN after.

- [ ] **Step 4 — Write RED fee matrix.** Cover: same-asset crypto fee (`received + fee = totalDebited`), another cryptoasset fee, fiat paid separately, crypto valuation-only, and `combined`. Assert custody/cost effects and that valuation does not debit twice. Run `flutter test test/accounting/projection/fee_projection_test.dart`; expected RED: resolver absent.

- [ ] **Step 5 — Implement one fee resolver.** `FiatFeeTreatment.valuationOfCryptoFee` records fiat valuation but not a second payment; `paidSeparately` affects fiat cost once; `combined` permits both explicit effects; other-asset crypto fee debits that asset’s custody without inventing P&L. Re-run; expect GREEN.

- [ ] **Step 6 — Add mandatory Mercado Pago case.** In `transfer_projection_test.dart`, source `Mi Mercado Pago`, external recipient `Primo`, platform `Bitso`, received `1`, fee `0.00167532 UNI`, debit `1.00167532`, observed balance fixture `127.75883985`; assert no owned destination credit and realized P&L `0`. The observed value appears only in this test data. Run both tests plus all accounting tests and expect GREEN.

- [ ] **Step 7 — Verify and commit.** Run formatter, full suite, analyzer tuple comparison, diff check; then `git add lib/accounting/projection/fee_effect.dart lib/accounting/projection/custody_projector.dart lib/accounting/projection/performance_projector.dart test/accounting/projection/transfer_projection_test.dart test/accounting/projection/fee_projection_test.dart && git commit -m "feat(accounting): allocate transfers and fees explicitly"`.

---

### Task CORE-6: Combinar proyecciones y adaptar el motor histórico

**Purpose:** Exponer una lectura coherente por cartera/activo y mantener pantallas antiguas operativas sin duplicar fórmulas.

**Files:**
- Create: `lib/accounting/projection/ledger_projection.dart`
- Create: `lib/accounting/projection/accounting_ledger_engine.dart`
- Create: `lib/accounting/adapters/legacy_movement_adapter.dart`
- Create: `lib/accounting/adapters/legacy_financial_adapter.dart`
- Create: `test/accounting/projection/accounting_ledger_engine_test.dart`
- Create: `test/accounting/adapters/legacy_financial_adapter_test.dart`
- Modify: `lib/cripto_control_app.dart`
- Existing symbols affected: `FinancialEngine` (24444), `Movement` (25093), `CoinStats` (25344), `CoinAudit` (25404), `PortfolioTotals` (25453); `MovementType`/`MovementLabel` ya quedaron cubiertos en CORE-1.

**Consumes:** `CustodyProjector`, `PerformanceProjector`, current `Movement` JSON and `FinancialEngine` weighted-average semantics.

**Produces:**

```dart
final class AccountingCompletenessResult {
  const AccountingCompletenessResult({required this.state,
    required this.totalQuantity, required this.knownQuantity,
    required this.unknownQuantity, required this.cause,
    required this.causingMovementIds});
  final AccountingCompleteness state;
  final AccountingAmount totalQuantity;
  final AccountingAmount knownQuantity;
  final AccountingAmount unknownQuantity;
  final ProjectionIssueCode? cause;
  final List<String> causingMovementIds;
}
final class WalletAssetProjection {
  const WalletAssetProjection({required this.key, required this.custody,
    required this.performance, required this.completeness,
    required this.custodyMarketValue, required this.knownPositionMarketValue});
  final WalletAssetKey key;
  final CustodyPosition custody;
  final PerformancePosition performance;
  final AccountingCompletenessResult completeness;
  final AccountingAmount custodyMarketValue;
  final AccountingAmount knownPositionMarketValue;
  AccountingAmount get reconciliationDifference;
  AccountingAmount get knownAvailable;
  AccountingAmount get unknownAvailable;
  AccountingAmount get custodyDeficit;
}
final class MovementEffect {
  const MovementEffect({required this.movementId,
    required this.requestedQuantity, required this.appliedQuantity,
    required this.unappliedQuantity, required this.issues, this.sale});
  final String movementId;
  final AccountingAmount requestedQuantity;
  final AccountingAmount appliedQuantity;
  final AccountingAmount unappliedQuantity;
  final List<ProjectionIssue> issues;
  final SaleResult? sale;
}
final class LedgerTotals {
  const LedgerTotals({required this.custodyMarketValue,
    required this.knownPositionMarketValue, required this.knownCostBasis,
    required this.realizedPnlKnown, required this.unrealizedPnlKnown});
  final AccountingAmount custodyMarketValue;
  final AccountingAmount knownPositionMarketValue;
  final AccountingAmount knownCostBasis;
  final AccountingAmount realizedPnlKnown;
  final AccountingAmount unrealizedPnlKnown;
}
final class MigrationProgress {
  const MigrationProgress({required this.assigned, required this.total});
  final int assigned;
  final int total;
}
final class LedgerProjection {
  const LedgerProjection({required this.positions, required this.sales,
    required this.effects, required this.totals, required this.issues,
    required this.migrationProgress});
  final Map<WalletAssetKey, WalletAssetProjection> positions;
  final List<SaleResult> sales;
  final Map<String, MovementEffect> effects;
  final LedgerTotals totals;
  final List<ProjectionIssue> issues;
  final MigrationProgress migrationProgress;
}
final class LedgerInput {
  const LedgerInput({required this.wallets, required this.movements,
    required this.currentPrices, required this.saleCostConsumptionPolicy,
    required this.transferCostAllocationPolicy,
    required this.legacyAccountingPolicy});
  final List<Wallet> wallets;
  final List<AccountingMovement> movements;
  final Map<String, AccountingAmount> currentPrices;
  final SaleCostConsumptionPolicy saleCostConsumptionPolicy;
  final TransferCostAllocationPolicy transferCostAllocationPolicy;
  final LegacyAccountingPolicy legacyAccountingPolicy;
}
final class AccountingLedgerEngine {
  const AccountingLedgerEngine(this.normalizer, this.custody, this.performance);
  final MovementNormalizer normalizer;
  final CustodyProjector custody;
  final PerformanceProjector performance;
  LedgerProjection project(LedgerInput input);
}
final class LegacyMovementAdapter {
  LegacyMovementConversion fromLegacyJson(Map<String, Object?> value);
  Map<String, Object?> toLegacyJson(AccountingMovement value,
    {Map<String, Object?> preservedFields = const <String, Object?>{}});
}
final class LegacyMovementConversion {
  const LegacyMovementConversion(this.movement, this.preservedFields);
  final AccountingMovement movement;
  final Map<String, Object?> preservedFields;
}
final class LegacyCoinStatsData {
  const LegacyCoinStatsData({required this.coin, required this.quantity,
    required this.costBase, required this.realizedProfit});
  final String coin;
  final double quantity;
  final double costBase;
  final double realizedProfit;
}
final class LegacyPortfolioTotalsData {
  const LegacyPortfolioTotalsData({required this.costBase,
    required this.currentValue, required this.realizedProfit});
  final double costBase;
  final double currentValue;
  final double realizedProfit;
}
final class LegacyCoinAuditData {
  const LegacyCoinAuditData({required this.coin,
    required this.reconciledCostBase});
  final String coin;
  final double reconciledCostBase;
}
final class LegacyFinancialAdapter {
  Map<String, LegacyCoinStatsData> coinStats(LedgerProjection projection,
    Map<String, double> currentPrices);
  Map<String, LegacyCoinAuditData> audits(LedgerProjection projection);
  LegacyPortfolioTotalsData totals(LedgerProjection projection,
    Map<String, double> currentPrices);
}
```

**First RED test code:**

```dart
test('reports all four accounting completeness states', () {
  final projection = projectCompletenessFixture();
  expect(projection.positions.values
      .map((value) => value.completeness.state).toSet(),
      <AccountingCompleteness>{
        AccountingCompleteness.complete,
        AccountingCompleteness.partiallyKnown,
        AccountingCompleteness.pendingAssignment,
        AccountingCompleteness.unassignedLegacy,
      });
});
```

- [ ] **Step 1 — Write RED completeness tests.** Build four fixtures and assert `AccountingCompletenessResult` states `complete`, `partiallyKnown`, `pendingAssignment`, `unassignedLegacy`, with quantities/cause/IDs; the last two must not be silently attributed to a wallet. Run `flutter test test/accounting/projection/accounting_ledger_engine_test.dart`; expected RED: combined engine absent.

- [ ] **Step 2 — Implement the only cross-projection formulas.** Join custody/performance by `WalletAssetKey`; calculate exactly `reconciliationDifference`, `knownAvailable`, `unknownAvailable`, `custodyDeficit`, custody/known market values, totals, movement effects and migration progress in `AccountingLedgerEngine`. Derive completeness from assignment state, sale statuses and issues. UI/exporters only read these outputs. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED legacy conversion tests.** Cover buy/sell/transfer aliases and maps produced by every current `Movement.toJson` field, including `sourcePlatform`, `destinationPlatform`, `deletedAt`, `deviceId`, null-clearing and `balanceAdjustment`. Assert `LegacyMovementConversion.preservedFields` permits lossless reverse JSON but never participates in ownership. Run `flutter test test/accounting/adapters/legacy_financial_adapter_test.dart`; expected RED: adapters absent.

- [ ] **Step 4 — Make the minimal compatibility adapter.** Accounting adapters consume/produce JSON maps and neutral legacy DTOs, never import `cripto_control_app.dart`; the monolith remains responsible for `Movement.fromJson` and constructing `CoinStats`/`PortfolioTotals` from DTOs. Preserve existing constructors/JSON defaults. Do not move `FinancialEngine`, `Movement` or UI classes. Re-run; expect GREEN and verify no cyclic import.

- [ ] **Step 5 — Lock known-cost compatibility.** For a known-only fixture of multiple buys, sale and transfer, compare legacy `FinancialEngine.computeStats`, `computeAudit` and `totals` with adapter output within existing tolerance. If mismatch occurs, change the adapter/projection, not the historical method, unless a failing test proves incompatibility. Run adapter test and `test/accounting_hotfix_test.dart`; expect GREEN.

- [ ] **Step 6 — Verify the whole core and H1 evidence.** Run formatter, `flutter test test/accounting`, `flutter test`, analyzer tuple comparison and diff check. Record API signatures, sale/transfer/adjustment results and remaining baseline diagnostics for human gate H1.

- [ ] **Step 7 — Commit.** `git add lib/accounting/projection/ledger_projection.dart lib/accounting/projection/accounting_ledger_engine.dart lib/accounting/adapters/legacy_movement_adapter.dart lib/accounting/adapters/legacy_financial_adapter.dart lib/cripto_control_app.dart test/accounting/projection/accounting_ledger_engine_test.dart test/accounting/adapters/legacy_financial_adapter_test.dart && git commit -m "feat(accounting): expose combined ledger projection"`.
