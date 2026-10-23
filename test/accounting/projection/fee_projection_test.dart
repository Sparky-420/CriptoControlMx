import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/ledger_validation.dart';
import 'package:cripto_control_mx/accounting/domain/movement_normalizer.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/projection/custody_projection.dart';
import 'package:cripto_control_mx/accounting/projection/custody_projector.dart';
import 'package:cripto_control_mx/accounting/projection/fee_effect.dart';
import 'package:cripto_control_mx/accounting/projection/ledger_projection.dart';
import 'package:cripto_control_mx/accounting/projection/performance_projector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same-asset crypto fee is consumed once from the transferred asset', () {
    final effect = resolveFeeEffect(transfer(fee: '0.1', feeAsset: 'UNI'));

    expect(effect.assetCustodyDebit.toJson(), '0.1');
    expect(effect.otherAssetCustodyDebit, isEmpty);
    expect(effect.fiatCostEffect, AccountingAmount.zero);
  });

  test('other-asset crypto fee debits only that other asset', () {
    final effect = resolveFeeEffect(transfer(fee: '0.2', feeAsset: 'ETH'));

    expect(effect.assetCustodyDebit, AccountingAmount.zero);
    expect(effect.otherAssetCustodyDebit['ETH']!.toJson(), '0.2');
  });

  test('fiat-only paid separately is valid with no crypto custody or pnl', () {
    final movement = transfer(
      fiatFee: '15',
      treatment: FiatFeeTreatment.paidSeparately,
    );
    final ledger = const DefaultMovementNormalizer().normalize(
      <AccountingMovement>[movement],
    );
    final custody = const DefaultCustodyProjector().project(ledger);
    final performance = const DefaultPerformanceProjector().project(
      ledger,
      custody,
      const <String, AccountingAmount>{},
      salePolicy: SaleCostConsumptionPolicy.knownFirst,
      transferPolicy: TransferCostAllocationPolicy.proportional,
    );
    final effect = resolveFeeEffect(movement);

    expect(ledger.isValid, isTrue);
    expect(ledger.legs, hasLength(1));
    expect(effect.assetCustodyDebit, AccountingAmount.zero);
    expect(effect.otherAssetCustodyDebit, isEmpty);
    expect(effect.fiatCostEffect.toJson(), '15');
    expect(custody.effectsFor(movement.id), hasLength(1));
    expect(
      performance.positions.values.map((position) => position.realizedPnlKnown),
      everyElement(AccountingAmount.zero),
    );
  });

  test('fiat valuation is informational and creates no second debit', () {
    final effect = resolveFeeEffect(
      transfer(
        fee: '0.1',
        feeAsset: 'UNI',
        feeFiatValue: '20',
        treatment: FiatFeeTreatment.valuationOfCryptoFee,
      ),
    );

    expect(effect.assetCustodyDebit.toJson(), '0.1');
    expect(effect.fiatCostEffect, AccountingAmount.zero);
  });

  test('combined treatment applies crypto and fiat effects once each', () {
    final effect = resolveFeeEffect(
      transfer(
        fee: '0.2',
        feeAsset: 'ETH',
        fiatFee: '15',
        treatment: FiatFeeTreatment.combined,
      ),
    );

    expect(effect.assetCustodyDebit, AccountingAmount.zero);
    expect(effect.otherAssetCustodyDebit['ETH']!.toJson(), '0.2');
    expect(effect.fiatCostEffect.toJson(), '15');
  });

  test('R1-02 FeeEffect snapshots input and exposes immutable maps', () {
    final one = AccountingAmount.fromInt(1);
    final source = <String, AccountingAmount>{'ETH': one};
    final effect = FeeEffect(
      assetCustodyDebit: AccountingAmount.zero,
      otherAssetCustodyDebit: source,
      fiatCostEffect: AccountingAmount.zero,
    );

    source['ETH'] = AccountingAmount.fromInt(2);
    source['BTC'] = one;

    expect(effect.otherAssetCustodyDebit, <String, AccountingAmount>{
      'ETH': one,
    });
    expect(
      () => effect.otherAssetCustodyDebit['BTC'] = one,
      throwsUnsupportedError,
    );
    expect(effect.otherAssetCustodyDebit, <String, AccountingAmount>{
      'ETH': one,
    });
  });

  test('R1-02 FeeEffect.zero has a const immutable empty map', () {
    expect(FeeEffect.zero.otherAssetCustodyDebit, isEmpty);
    expect(
      () => FeeEffect.zero.otherAssetCustodyDebit['ETH'] =
          AccountingAmount.fromInt(1),
      throwsUnsupportedError,
    );
    expect(FeeEffect.zero.otherAssetCustodyDebit, isEmpty);
  });

  test('R1-02 MovementEffect snapshots every collection input', () {
    final leg = MovementCustodyLegEffect(
      key: const WalletAssetKey('wallet', 'UNI'),
      kind: LedgerLegKind.custodyDebit,
      before: AccountingAmount.fromInt(2),
      requested: AccountingAmount.fromInt(-1),
      applied: AccountingAmount.fromInt(-1),
      unapplied: AccountingAmount.zero,
      after: AccountingAmount.fromInt(1),
    );
    final issue = const ProjectionIssue(
      ProjectionIssueCode.insufficientCustody,
      'movement',
      'Incidencia original',
    );
    final legs = <MovementCustodyLegEffect>[leg];
    final deltas = <String, AccountingAmount>{
      'UNI': AccountingAmount.fromInt(-1),
    };
    final issues = <ProjectionIssue>[issue];
    final effect = MovementEffect(
      movementId: 'movement',
      requestedQuantity: AccountingAmount.fromInt(1),
      appliedQuantity: AccountingAmount.fromInt(1),
      unappliedQuantity: AccountingAmount.zero,
      custodyLegs: legs,
      globalDeltasByAsset: deltas,
      feeEffect: FeeEffect.zero,
      issues: issues,
    );

    legs.clear();
    deltas['UNI'] = AccountingAmount.zero;
    issues.clear();

    expect(effect.custodyLegs, <MovementCustodyLegEffect>[leg]);
    expect(effect.globalDeltasByAsset['UNI']!.toJson(), '-1');
    expect(effect.issues, <ProjectionIssue>[issue]);
  });

  test('R1-02 MovementEffect exposed collections reject mutation', () {
    final effect = MovementEffect(
      movementId: 'movement',
      requestedQuantity: AccountingAmount.zero,
      appliedQuantity: AccountingAmount.zero,
      unappliedQuantity: AccountingAmount.zero,
      custodyLegs: <MovementCustodyLegEffect>[],
      globalDeltasByAsset: <String, AccountingAmount>{},
      feeEffect: FeeEffect.zero,
      issues: <ProjectionIssue>[],
    );

    expect(
      () => effect.custodyLegs.add(
        MovementCustodyLegEffect(
          key: const WalletAssetKey('wallet', 'UNI'),
          kind: LedgerLegKind.custodyCredit,
          before: AccountingAmount.zero,
          requested: AccountingAmount.fromInt(1),
          applied: AccountingAmount.fromInt(1),
          unapplied: AccountingAmount.zero,
          after: AccountingAmount.fromInt(1),
        ),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => effect.globalDeltasByAsset['UNI'] = AccountingAmount.zero,
      throwsUnsupportedError,
    );
    expect(
      () => effect.issues.add(
        const ProjectionIssue(
          ProjectionIssueCode.invalidAmount,
          'movement',
          'No debe agregarse',
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('normalizer rejects invalid fiat fee treatment matrix without legs', () {
    final invalid = <AccountingMovement>[
      transfer(fiatFee: '1'),
      transfer(treatment: FiatFeeTreatment.valuationOfCryptoFee),
      transfer(
        fee: '0.1',
        feeAsset: 'UNI',
        fiatFee: '1',
        treatment: FiatFeeTreatment.valuationOfCryptoFee,
      ),
      transfer(treatment: FiatFeeTreatment.paidSeparately),
      transfer(
        fiatFee: '1',
        feeFiatValue: '1',
        treatment: FiatFeeTreatment.paidSeparately,
      ),
      transfer(
        fee: '0.1',
        feeAsset: 'UNI',
        fiatFee: '1',
        treatment: FiatFeeTreatment.paidSeparately,
      ),
      transfer(
        fee: '0.1',
        feeAsset: 'UNI',
        treatment: FiatFeeTreatment.combined,
      ),
      transfer(fiatFee: '1', treatment: FiatFeeTreatment.combined),
    ];
    final ledger = const DefaultMovementNormalizer()
        .normalize(<AccountingMovement>[
          for (var index = 0; index < invalid.length; index++)
            invalid[index].copyWith(id: 'invalid-$index'),
        ]);

    expect(ledger.legs, isEmpty);
    expect(
      ledger.issues.map((issue) => issue.code),
      everyElement(ProjectionIssueCode.invalidAmount),
    );
  });
}

AccountingMovement transfer({
  String fee = '0',
  String? feeAsset,
  String fiatFee = '0',
  String? feeFiatValue,
  FiatFeeTreatment treatment = FiatFeeTreatment.none,
}) {
  final at = DateTime.utc(2026, 7, 30, 20, 54);
  return AccountingMovement(
    id: 'transfer',
    type: MovementType.transferOut,
    asset: 'UNI',
    occurredAt: at,
    quantity: AccountingAmount.fromInt(1),
    fiatFeeAmount: AccountingAmount.parse(fiatFee),
    sourceWalletId: '11111111-1111-4111-8111-111111111111',
    destinationType: DestinationType.external,
    externalRecipientName: 'Primo',
    externalDestinationPlatform: 'Bitso',
    walletAssignmentStatus: WalletAssignmentStatus.assigned,
    receivedAmount: AccountingAmount.fromInt(1),
    cryptoFeeAmount: AccountingAmount.parse(fee),
    cryptoFeeAsset: feeAsset,
    totalDebitedAmount: fee == '0' || feeAsset != 'UNI'
        ? AccountingAmount.fromInt(1)
        : AccountingAmount.fromInt(1) + AccountingAmount.parse(fee),
    feeFiatValue: feeFiatValue == null
        ? null
        : AccountingAmount.parse(feeFiatValue),
    fiatFeeTreatment: treatment,
    reconciliationLinks: const <ReconciliationLink>[],
    createdAt: at,
    updatedAt: at,
  );
}
