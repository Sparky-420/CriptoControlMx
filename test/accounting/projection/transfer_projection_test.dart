import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/ledger_validation.dart';
import 'package:cripto_control_mx/accounting/domain/movement_normalizer.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/projection/custody_projection.dart';
import 'package:cripto_control_mx/accounting/projection/custody_projector.dart';
import 'package:cripto_control_mx/accounting/projection/performance_projection.dart';
import 'package:cripto_control_mx/accounting/projection/performance_projector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transfer consumes known and unknown segments proportionally', () {
    final allocation = allocateTransferProportionally(
      custodyBefore: AccountingAmount.parse('12'),
      knownAvailable: AccountingAmount.parse('10'),
      knownCostBasis: AccountingAmount.parse('200'),
      totalDebited: AccountingAmount.parse('6'),
    );

    expect(allocation.totalDebited.toJson(), '6');
    expect(allocation.knownQuantity.toJson(), '5');
    expect(allocation.unknownQuantity.toJson(), '1');
    expect(allocation.transferredCostBasis.toJson(), '100');
  });

  test(
    'transfer allocation partitions periodic ratios and liquidation exactly',
    () {
      final fullKnown = allocateTransferProportionally(
        custodyBefore: AccountingAmount.parse('3'),
        knownAvailable: AccountingAmount.parse('3'),
        knownCostBasis: AccountingAmount.parse('6'),
        totalDebited: AccountingAmount.parse('1'),
      );
      final mixed = allocateTransferProportionally(
        custodyBefore: AccountingAmount.parse('3'),
        knownAvailable: AccountingAmount.parse('1'),
        knownCostBasis: AccountingAmount.parse('6'),
        totalDebited: AccountingAmount.parse('1'),
      );
      final fullUnknown = allocateTransferProportionally(
        custodyBefore: AccountingAmount.parse('3'),
        knownAvailable: AccountingAmount.zero,
        knownCostBasis: AccountingAmount.zero,
        totalDebited: AccountingAmount.parse('1'),
      );
      final finalLiquidation = allocateTransferProportionally(
        custodyBefore: AccountingAmount.parse('2'),
        knownAvailable: AccountingAmount.parse('2'),
        knownCostBasis: AccountingAmount.parse('4'),
        totalDebited: AccountingAmount.parse('2'),
      );

      expect(fullKnown.knownQuantity.toJson(), '1');
      expect(fullKnown.unknownQuantity, AccountingAmount.zero);
      expect(fullKnown.transferredCostBasis.toJson(), '2');
      expect(mixed.knownQuantity.toJson(), '0.333333333333333333');
      expect(mixed.unknownQuantity.toJson(), '0.666666666666666667');
      expect(mixed.knownQuantity + mixed.unknownQuantity, mixed.totalDebited);
      expect(fullUnknown.knownQuantity, AccountingAmount.zero);
      expect(fullUnknown.unknownQuantity.toJson(), '1');
      expect(finalLiquidation.knownQuantity.toJson(), '2');
      expect(finalLiquidation.unknownQuantity, AccountingAmount.zero);
      expect(finalLiquidation.transferredCostBasis.toJson(), '4');
    },
  );

  test('H1-05 deficit transfer multiplies cost before division exactly', () {
    final result = _project(<AccountingMovement>[
      movement(
        id: 'buy',
        type: MovementType.buy,
        quantity: '3',
        unitPrice: '1',
        destinationWalletId: sourceWalletId,
      ).copyWith(fiatFeeAmount: AccountingAmount.parse('1')),
      movement(
        id: 'deficit-adjustment',
        type: MovementType.balanceAdjustment,
        adjustmentWalletId: sourceWalletId,
        adjustmentQuantity: '-1',
        observedBalance: '2',
        adjustmentReason: 'Deficit historico',
      ),
      transfer(
        id: 'deficit-transfer',
        destinationType: DestinationType.external,
        received: '1',
      ),
    ]);

    expect(
      result.performance.positions[sourceKey]!.knownCostBasis.toJson(),
      '2.666666666666666667',
    );
    expect(
      result.performance.positions[sourceKey]!.knownQuantity.toJson(),
      '2',
    );
  });

  test('H1-05 periodic deficit custody liquidation removes exact cost', () {
    final result = _project(<AccountingMovement>[
      movement(
        id: 'buy',
        type: MovementType.buy,
        quantity: '3',
        unitPrice: '1',
        destinationWalletId: sourceWalletId,
      ).copyWith(fiatFeeAmount: AccountingAmount.parse('1')),
      movement(
        id: 'deficit-adjustment',
        type: MovementType.balanceAdjustment,
        adjustmentWalletId: sourceWalletId,
        adjustmentQuantity: '-1',
        observedBalance: '2',
        adjustmentReason: 'Deficit historico',
      ),
      transfer(
        id: 'deficit-transfer-1',
        destinationType: DestinationType.ownWallet,
        destinationWalletId: destinationWalletId,
        received: '1',
      ),
      transfer(
        id: 'deficit-transfer-2',
        destinationType: DestinationType.ownWallet,
        destinationWalletId: thirdWalletId,
        received: '1',
      ),
    ]);

    expect(
      result.custody.positions[sourceKey]!.reconciledQuantity,
      AccountingAmount.zero,
    );
    expect(
      result.performance.positions[sourceKey]!.knownQuantity.toJson(),
      '1',
    );
    expect(
      result.performance.positions[sourceKey]!.knownCostBasis.toJson(),
      '1.333333333333333334',
    );
    expect(
      result.performance.positions[destinationKey]!.knownCostBasis.toJson(),
      '1.333333333333333333',
    );
    expect(
      result.performance.positions[thirdKey]!.knownCostBasis.toJson(),
      '1.333333333333333333',
    );
  });

  test(
    'historical internal periodic transfer preserves exact principal globally',
    () {
      final result = _project(<AccountingMovement>[
        buy(id: 'buy', walletId: sourceWalletId, quantity: '1'),
        transfer(
          id: 'historic-periodic-internal',
          destinationType: DestinationType.ownWallet,
          destinationWalletId: destinationWalletId,
          received: '3',
        ),
      ]);
      final effects = result.custody.effectsFor('historic-periodic-internal');
      final globalDelta =
          result.custody.positions.values.fold<AccountingAmount>(
            AccountingAmount.zero,
            (total, position) => total + position.reconciledQuantity,
          ) -
          AccountingAmount.parse('1');

      expect(effects[0].requested.toJson(), '-3');
      expect(effects[0].applied.toJson(), '-1');
      expect(effects[0].unapplied.toJson(), '-2');
      expect(effects[1].requested.toJson(), '3');
      expect(effects[1].applied.toJson(), '1');
      expect(effects[1].unapplied.toJson(), '2');
      expect(globalDelta, AccountingAmount.zero);
      expect(
        result.performance.positions[sourceKey]!.knownQuantity,
        AccountingAmount.zero,
      );
      expect(
        result.performance.positions[destinationKey]!.knownQuantity.toJson(),
        '1',
      );
      expect(
        result.performance.positions[destinationKey]!.knownCostBasis.toJson(),
        '20',
      );
    },
  );

  test('periodic partial debit divides once and keeps unapplied remainder', () {
    final result = _project(<AccountingMovement>[
      buy(id: 'buy', walletId: sourceWalletId, quantity: '2'),
      transfer(
        id: 'periodic-partial-with-fee',
        destinationType: DestinationType.ownWallet,
        destinationWalletId: destinationWalletId,
        received: '2',
        fee: '1',
      ),
    ]);
    final effects = result.custody.effectsFor('periodic-partial-with-fee');

    expect(effects[0].requested.toJson(), '-3');
    expect(effects[0].applied.toJson(), '-2');
    expect(effects[0].unapplied.toJson(), '-1');
    expect(effects[1].requested.toJson(), '2');
    expect(effects[1].applied.toJson(), '1.333333333333333333');
    expect(effects[1].unapplied.toJson(), '0.666666666666666667');
    expect(effects[1].applied + effects[1].unapplied, effects[1].requested);
  });

  test('fully applied internal debit credits received exactly after fee', () {
    final result = _project(<AccountingMovement>[
      buy(id: 'buy', walletId: sourceWalletId, quantity: '3'),
      transfer(
        id: 'periodic-internal',
        destinationType: DestinationType.ownWallet,
        destinationWalletId: destinationWalletId,
        received: '2',
        fee: '1',
      ),
    ]);
    final effects = result.custody.effectsFor('periodic-internal');

    expect(effects[0].applied.toJson(), '-3');
    expect(effects[1].requested.toJson(), '2');
    expect(effects[1].applied.toJson(), '2');
    expect(effects[1].unapplied, AccountingAmount.zero);
    expect(
      result.performance.positions[sourceKey]!.knownQuantity,
      AccountingAmount.zero,
    );
    expect(
      result.performance.positions[sourceKey]!.knownCostBasis,
      AccountingAmount.zero,
    );
    expect(
      result.performance.positions[destinationKey]!.knownQuantity.toJson(),
      '2',
    );
    expect(
      result.performance.positions[destinationKey]!.knownCostBasis.toJson(),
      '40',
    );
  });

  test('duplicate movement IDs apply transfer and other-asset fee once', () {
    final duplicate = transfer(
      id: 'z-duplicate',
      destinationType: DestinationType.external,
      received: '4',
      fee: '0.5',
      feeAsset: 'ETH',
    );
    final result = _project(<AccountingMovement>[
      buy(id: 'buy', walletId: sourceWalletId, quantity: '10'),
      buy(
        id: 'eth-buy',
        walletId: sourceWalletId,
        quantity: '2',
      ).copyWith(asset: 'ETH'),
      duplicate,
      duplicate,
    ]);
    const ethKey = WalletAssetKey(sourceWalletId, 'ETH');

    expect(
      result.custody.positions[sourceKey]!.reconciledQuantity.toJson(),
      '6',
    );
    expect(
      result.custody.positions[ethKey]!.reconciledQuantity.toJson(),
      '1.5',
    );
    expect(
      result.performance.positions[sourceKey]!.knownQuantity.toJson(),
      '6',
    );
    expect(
      result.performance.positions[sourceKey]!.knownCostBasis.toJson(),
      '120',
    );
    expect(result.performance.positions[ethKey]!.knownQuantity.toJson(), '1.5');
    expect(result.performance.positions[ethKey]!.knownCostBasis.toJson(), '30');
  });

  test(
    'internal transfer from zero custody applies no unobserved destination credit',
    () {
      final result = _project(<AccountingMovement>[
        transfer(
          id: 'zero-source-internal',
          destinationType: DestinationType.ownWallet,
          destinationWalletId: destinationWalletId,
          received: '2',
        ),
      ]);
      final effects = result.custody.effectsFor('zero-source-internal');

      expect(effects[0].requested.toJson(), '-2');
      expect(effects[0].applied, AccountingAmount.zero);
      expect(effects[0].unapplied.toJson(), '-2');
      expect(effects[1].requested.toJson(), '2');
      expect(effects[1].applied, AccountingAmount.zero);
      expect(effects[1].unapplied.toJson(), '2');
      expect(
        result.custody.positions.values.fold<AccountingAmount>(
          AccountingAmount.zero,
          (total, position) => total + position.reconciledQuantity,
        ),
        AccountingAmount.zero,
      );
      expect(
        result.custody.positions[sourceKey]!.issues.map((issue) => issue.code),
        contains(ProjectionIssueCode.insufficientCustody),
      );
      expect(
        result.performance.positions[destinationKey]!.knownQuantity,
        AccountingAmount.zero,
      );
    },
  );

  test(
    'zero-source internal transfer credits only its validated destination link',
    () {
      final destinationAdjustment =
          adjustment(
            id: 'destination-adjustment',
            walletId: destinationWalletId,
            quantity: '1',
          ).copyWith(
            occurredAt: at.add(const Duration(minutes: 3)),
            observedBalance: AccountingAmount.parse('1'),
          );
      final partial =
          transfer(
            id: 'zero-source-partial',
            destinationType: DestinationType.ownWallet,
            destinationWalletId: destinationWalletId,
            received: '1',
          ).copyWith(
            reconciliationLinks: <ReconciliationLink>[
              ReconciliationLink(
                adjustmentMovementId: destinationAdjustment.id,
                quantityResolved: AccountingAmount.parse('0.4'),
              ),
            ],
          );

      final partialResult = _project(<AccountingMovement>[
        destinationAdjustment,
        partial,
      ]);
      final partialEffects = partialResult.custody.effectsFor(partial.id);
      final adjustmentEffect = partialResult.custody
          .effectsFor(destinationAdjustment.id)
          .single;

      expect(adjustmentEffect.requested.toJson(), '0.6');
      expect(partialEffects[1].applied.toJson(), '0.4');
      expect(partialEffects[1].unapplied.toJson(), '0.6');
      expect(
        partialResult.custody.positions[destinationKey]!.reconciledQuantity
            .toJson(),
        '1',
      );

      final total = partial.copyWith(
        id: 'zero-source-total',
        reconciliationLinks: <ReconciliationLink>[
          ReconciliationLink(
            adjustmentMovementId: destinationAdjustment.id,
            quantityResolved: AccountingAmount.parse('1'),
          ),
        ],
      );
      final totalResult = _project(<AccountingMovement>[
        destinationAdjustment,
        total,
      ]);
      expect(totalResult.custody.effectsFor(total.id)[1].applied.toJson(), '1');
    },
  );

  test(
    'zero-source internal transfer ignores invalid and non-credit links',
    () {
      final destinationAdjustment = adjustment(
        id: 'valid-destination-adjustment',
        walletId: destinationWalletId,
        quantity: '1',
      ).copyWith(occurredAt: at, observedBalance: AccountingAmount.parse('1'));
      final wrongWalletAdjustment =
          adjustment(
            id: 'wrong-wallet-adjustment',
            walletId: sourceWalletId,
            quantity: '1',
          ).copyWith(
            occurredAt: at.add(const Duration(minutes: 3)),
            observedBalance: AccountingAmount.parse('1'),
          );
      final wrongAssetAdjustment =
          adjustment(
            id: 'wrong-asset-adjustment',
            walletId: destinationWalletId,
            quantity: '1',
          ).copyWith(
            asset: 'ETH',
            occurredAt: at.add(const Duration(minutes: 3)),
            observedBalance: AccountingAmount.parse('1'),
          );
      final wrongSignAdjustment =
          adjustment(
            id: 'wrong-sign-adjustment',
            walletId: destinationWalletId,
            quantity: '-1',
          ).copyWith(
            occurredAt: at.add(const Duration(minutes: 3)),
            observedBalance: AccountingAmount.zero,
          );
      final sourceDebitAdjustment =
          adjustment(
            id: 'source-debit-adjustment',
            walletId: sourceWalletId,
            quantity: '-1',
          ).copyWith(
            occurredAt: at.add(const Duration(minutes: 3)),
            observedBalance: AccountingAmount.zero,
          );
      final base = transfer(
        id: 'zero-source-invalid-link',
        destinationType: DestinationType.ownWallet,
        destinationWalletId: destinationWalletId,
        received: '1',
      );
      final cases = <AccountingMovement>[
        base.copyWith(
          id: 'missing-link',
          reconciliationLinks: <ReconciliationLink>[
            ReconciliationLink(
              adjustmentMovementId: 'missing',
              quantityResolved: AccountingAmount.parse('1'),
            ),
          ],
        ),
        base.copyWith(
          id: 'wrong-wallet-link',
          reconciliationLinks: <ReconciliationLink>[
            ReconciliationLink(
              adjustmentMovementId: wrongWalletAdjustment.id,
              quantityResolved: AccountingAmount.parse('1'),
            ),
          ],
        ),
        base.copyWith(
          id: 'wrong-asset-link',
          reconciliationLinks: <ReconciliationLink>[
            ReconciliationLink(
              adjustmentMovementId: wrongAssetAdjustment.id,
              quantityResolved: AccountingAmount.parse('1'),
            ),
          ],
        ),
        base.copyWith(
          id: 'wrong-sign-link',
          reconciliationLinks: <ReconciliationLink>[
            ReconciliationLink(
              adjustmentMovementId: wrongSignAdjustment.id,
              quantityResolved: AccountingAmount.parse('1'),
            ),
          ],
        ),
        base.copyWith(
          id: 'source-debit-link',
          reconciliationLinks: <ReconciliationLink>[
            ReconciliationLink(
              adjustmentMovementId: sourceDebitAdjustment.id,
              quantityResolved: AccountingAmount.parse('1'),
            ),
          ],
        ),
      ];

      for (final movement in cases) {
        final result = _project(<AccountingMovement>[
          destinationAdjustment,
          wrongWalletAdjustment,
          wrongAssetAdjustment,
          wrongSignAdjustment,
          sourceDebitAdjustment,
          movement,
        ]);
        expect(
          result.custody.effectsFor(movement.id)[1].applied.toJson(),
          '0',
          reason: movement.id,
        );
      }
    },
  );

  test('internal transfer rejects links beyond its unbacked credit gap', () {
    final destinationAdjustment =
        adjustment(
          id: 'gap-adjustment',
          walletId: destinationWalletId,
          quantity: '1',
        ).copyWith(
          occurredAt: at.add(const Duration(minutes: 1)),
          observedBalance: AccountingAmount.parse('1'),
        );
    AccountingMovement linked(String id, String quantity) =>
        transfer(
          id: id,
          destinationType: DestinationType.ownWallet,
          destinationWalletId: destinationWalletId,
          received: '1',
          fee: '0.25',
        ).copyWith(
          reconciliationLinks: <ReconciliationLink>[
            ReconciliationLink(
              adjustmentMovementId: destinationAdjustment.id,
              quantityResolved: AccountingAmount.parse(quantity),
            ),
          ],
        );

    final valid = _project(<AccountingMovement>[
      buy(id: 'buy', walletId: sourceWalletId, quantity: '1'),
      destinationAdjustment,
      linked('gap-valid', '0.2'),
    ]);
    expect(
      valid.custody
          .effectsFor(destinationAdjustment.id)
          .single
          .requested
          .toJson(),
      '0.8',
    );
    expect(valid.custody.effectsFor('gap-valid')[1].applied.toJson(), '1');

    final invalid = _project(<AccountingMovement>[
      buy(id: 'buy', walletId: sourceWalletId, quantity: '1'),
      destinationAdjustment,
      linked('gap-invalid', '0.4'),
    ]);
    expect(
      invalid.custody
          .effectsFor(destinationAdjustment.id)
          .single
          .requested
          .toJson(),
      '1',
    );
    expect(
      invalid.custody.effectsFor('gap-invalid')[1].applied.toJson(),
      '0.8',
    );
    expect(
      invalid.custody.effectsFor('gap-invalid')[1].unapplied.toJson(),
      '0.2',
    );
    expect(
      invalid.custody.positions[destinationKey]!.issues.map(
        (issue) => issue.code,
      ),
      contains(ProjectionIssueCode.invalidReconciliationLink),
    );
  });

  test('one internal transfer moves its proportional cost mix without pnl', () {
    final result = _project(<AccountingMovement>[
      buy(id: 'buy', walletId: sourceWalletId, quantity: '10'),
      adjustment(id: 'unknown', walletId: sourceWalletId, quantity: '2'),
      transfer(
        id: 'internal',
        destinationType: DestinationType.ownWallet,
        destinationWalletId: destinationWalletId,
        received: '5',
        fee: '1',
      ),
    ]);

    expect(
      result.custody.positions[sourceKey]!.reconciledQuantity.toJson(),
      '6',
    );
    expect(
      result.custody.positions[destinationKey]!.reconciledQuantity.toJson(),
      '5',
    );
    expect(
      result.performance.positions[sourceKey]!.knownQuantity.toJson(),
      '5',
    );
    expect(
      result.performance.positions[destinationKey]!.knownQuantity.toJson(),
      '4.166666666666666666',
    );
    expect(
      result.performance.positions[destinationKey]!.knownCostBasis.toJson(),
      '83.333333333333333333',
    );
    expect(
      result.performance.positions.values.fold<AccountingAmount>(
        AccountingAmount.zero,
        (total, position) => total + position.realizedPnlKnown,
      ),
      AccountingAmount.zero,
    );
  });

  test(
    'external transfer removes applied proportional mix with no owned credit',
    () {
      final result = _project(<AccountingMovement>[
        buy(id: 'buy', walletId: sourceWalletId, quantity: '10'),
        adjustment(id: 'unknown', walletId: sourceWalletId, quantity: '2'),
        transfer(
          id: 'external',
          destinationType: DestinationType.external,
          received: '5',
          fee: '1',
        ),
      ]);

      expect(
        result.custody.positions[sourceKey]!.reconciledQuantity.toJson(),
        '6',
      );
      expect(result.custody.positions.containsKey(destinationKey), isFalse);
      expect(
        result.performance.positions[sourceKey]!.knownQuantity.toJson(),
        '5',
      );
      expect(
        result.performance.positions[sourceKey]!.knownCostBasis.toJson(),
        '100',
      );
      expect(
        result.performance.positions[sourceKey]!.realizedPnlKnown,
        AccountingAmount.zero,
      );
    },
  );

  test(
    'historical insufficient transfer remains visible and applies only custody',
    () {
      final result = _project(<AccountingMovement>[
        buy(id: 'buy', walletId: sourceWalletId, quantity: '1'),
        transfer(
          id: 'historic',
          destinationType: DestinationType.external,
          received: '2',
        ),
      ]);
      final effect = result.custody.effectsFor('historic').single;

      expect(effect.requested.toJson(), '-2');
      expect(effect.applied.toJson(), '-1');
      expect(effect.unapplied.toJson(), '-1');
      expect(
        result.custody.positions[sourceKey]!.issues.map((issue) => issue.code),
        contains(ProjectionIssueCode.insufficientCustody),
      );
      expect(
        result.custody.positions[sourceKey]!.reconciledQuantity,
        AccountingAmount.zero,
      );
      expect(
        result.performance.positions[sourceKey]!.knownQuantity,
        AccountingAmount.zero,
      );
    },
  );

  test(
    'new transfer is rejected against the available custody before saving',
    () {
      final custody = const LedgerRebuilder().rebuild(<AccountingMovement>[
        buy(id: 'buy', walletId: sourceWalletId, quantity: '1'),
      ]);
      final candidate = transfer(
        id: 'new-insufficient',
        destinationType: DestinationType.external,
        received: '2',
      );

      expect(
        () => const TransferCustodyValidator().validateNew(candidate, custody),
        throwsArgumentError,
      );
    },
  );

  test('other-asset fee debits its custody and cost once without pnl', () {
    final result = _project(<AccountingMovement>[
      buy(id: 'buy', walletId: sourceWalletId, quantity: '10'),
      buy(
        id: 'eth-buy',
        walletId: sourceWalletId,
        quantity: '2',
      ).copyWith(asset: 'ETH'),
      transfer(
        id: 'other-asset-fee',
        destinationType: DestinationType.external,
        received: '5',
        fee: '0.5',
        feeAsset: 'ETH',
      ),
    ]);
    const ethKey = WalletAssetKey(sourceWalletId, 'ETH');

    expect(
      result.custody
          .effectsFor('other-asset-fee')
          .map((effect) => effect.requested.toJson()),
      <String>['-5', '-0.5'],
    );
    expect(
      result.custody.positions[sourceKey]!.reconciledQuantity.toJson(),
      '5',
    );
    expect(
      result.custody.positions[ethKey]!.reconciledQuantity.toJson(),
      '1.5',
    );
    expect(result.performance.positions[ethKey]!.knownQuantity.toJson(), '1.5');
    expect(result.performance.positions[ethKey]!.knownCostBasis.toJson(), '30');
    expect(
      result.performance.positions[ethKey]!.realizedPnlKnown,
      AccountingAmount.zero,
    );
  });

  test('Mercado Pago external fixture has no owned credit or realized pnl', () {
    final observedBalance = AccountingAmount.parse('127.75883985');
    const mercadoPagoWalletId = 'Mi Mercado Pago';
    const mercadoPagoKey = WalletAssetKey(mercadoPagoWalletId, 'UNI');
    final result = _project(<AccountingMovement>[
      buy(id: 'buy', walletId: mercadoPagoWalletId, quantity: '128.76051517'),
      transfer(
        id: 'mercado-pago',
        destinationType: DestinationType.external,
        received: '1',
        fee: '0.00167532',
      ).copyWith(sourceWalletId: mercadoPagoWalletId),
    ]);

    expect(
      result.custody.positions[mercadoPagoKey]!.reconciledQuantity,
      observedBalance,
    );
    expect(result.custody.positions.keys, isNot(contains(destinationKey)));
    expect(
      result.performance.positions[mercadoPagoKey]!.realizedPnlKnown,
      AccountingAmount.zero,
    );
  });
}

const String sourceWalletId = '11111111-1111-4111-8111-111111111111';
const String destinationWalletId = '22222222-2222-4222-8222-222222222222';
const String thirdWalletId = '33333333-3333-4333-8333-333333333333';
const WalletAssetKey sourceKey = WalletAssetKey(sourceWalletId, 'UNI');
const WalletAssetKey destinationKey = WalletAssetKey(
  destinationWalletId,
  'UNI',
);
const WalletAssetKey thirdKey = WalletAssetKey(thirdWalletId, 'UNI');
final DateTime at = DateTime.utc(2026, 7, 30, 20, 54);

_ProjectionResult _project(List<AccountingMovement> movements) {
  final ledger = const DefaultMovementNormalizer().normalize(movements);
  final custody = const DefaultCustodyProjector().project(ledger);
  return _ProjectionResult(
    custody,
    const DefaultPerformanceProjector().project(
      ledger,
      custody,
      const <String, AccountingAmount>{},
      salePolicy: SaleCostConsumptionPolicy.knownFirst,
      transferPolicy: TransferCostAllocationPolicy.proportional,
    ),
  );
}

AccountingMovement buy({
  required String id,
  required String walletId,
  required String quantity,
}) => movement(
  id: id,
  type: MovementType.buy,
  quantity: quantity,
  unitPrice: '20',
  destinationWalletId: walletId,
);

AccountingMovement adjustment({
  required String id,
  required String walletId,
  required String quantity,
}) => movement(
  id: id,
  type: MovementType.balanceAdjustment,
  adjustmentWalletId: walletId,
  adjustmentQuantity: quantity,
  observedBalance: '12',
  adjustmentReason: 'Conciliacion',
);

AccountingMovement transfer({
  required String id,
  required DestinationType destinationType,
  String? destinationWalletId,
  required String received,
  String fee = '0',
  String? feeAsset,
}) => movement(
  id: id,
  type: MovementType.transferOut,
  quantity: received,
  sourceWalletId: sourceWalletId,
  destinationWalletId: destinationWalletId,
  destinationType: destinationType,
  externalRecipientName: destinationType == DestinationType.external
      ? 'Primo'
      : null,
  externalDestinationPlatform: destinationType == DestinationType.external
      ? 'Bitso'
      : null,
  receivedAmount: received,
  cryptoFeeAmount: fee,
  cryptoFeeAsset: fee == '0' ? null : feeAsset ?? 'UNI',
  totalDebitedAmount:
      (fee != '0' && (feeAsset ?? 'UNI') == 'UNI'
              ? AccountingAmount.parse(received) + AccountingAmount.parse(fee)
              : AccountingAmount.parse(received))
          .toJson(),
);

AccountingMovement movement({
  required String id,
  required MovementType type,
  String? quantity,
  String? unitPrice,
  String? sourceWalletId,
  String? destinationWalletId,
  DestinationType? destinationType,
  String? externalRecipientName,
  String? externalDestinationPlatform,
  String? receivedAmount,
  String cryptoFeeAmount = '0',
  String? cryptoFeeAsset,
  String? totalDebitedAmount,
  String? adjustmentWalletId,
  String? adjustmentQuantity,
  String? observedBalance,
  String? adjustmentReason,
}) {
  final occurredAt = at.add(
    Duration(
      minutes: id == 'buy'
          ? 0
          : id == 'unknown'
          ? 1
          : 2,
    ),
  );
  return AccountingMovement(
    id: id,
    type: type,
    asset: 'UNI',
    occurredAt: occurredAt,
    quantity: quantity == null ? null : AccountingAmount.parse(quantity),
    unitPriceFiat: unitPrice == null ? null : AccountingAmount.parse(unitPrice),
    fiatFeeAmount: AccountingAmount.zero,
    sourceWalletId: sourceWalletId,
    destinationWalletId: destinationWalletId,
    destinationType: destinationType,
    externalRecipientName: externalRecipientName,
    externalDestinationPlatform: externalDestinationPlatform,
    walletAssignmentStatus: WalletAssignmentStatus.assigned,
    receivedAmount: receivedAmount == null
        ? null
        : AccountingAmount.parse(receivedAmount),
    cryptoFeeAmount: AccountingAmount.parse(cryptoFeeAmount),
    cryptoFeeAsset: cryptoFeeAsset,
    totalDebitedAmount: totalDebitedAmount == null
        ? null
        : AccountingAmount.parse(totalDebitedAmount),
    fiatFeeTreatment: FiatFeeTreatment.none,
    reconciliationLinks: const <ReconciliationLink>[],
    createdAt: occurredAt,
    updatedAt: occurredAt,
    adjustmentWalletId: adjustmentWalletId,
    adjustmentQuantity: adjustmentQuantity == null
        ? null
        : AccountingAmount.parse(adjustmentQuantity),
    observedBalance: observedBalance == null
        ? null
        : AccountingAmount.parse(observedBalance),
    adjustmentReason: adjustmentReason,
  );
}

final class _ProjectionResult {
  const _ProjectionResult(this.custody, this.performance);

  final CustodyProjection custody;
  final PerformanceProjection performance;
}
