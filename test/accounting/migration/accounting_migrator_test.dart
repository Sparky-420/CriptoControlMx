import 'package:cripto_control_mx/accounting/adapters/legacy_movement_adapter.dart';
import 'package:cripto_control_mx/accounting/adapters/legacy_financial_adapter.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/movement_normalizer.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/migration/accounting_migrator.dart';
import 'package:cripto_control_mx/accounting/migration/legacy_migration_problem.dart';
import 'package:cripto_control_mx/accounting/projection/accounting_ledger_engine.dart';
import 'package:cripto_control_mx/accounting/projection/custody_projector.dart';
import 'package:cripto_control_mx/accounting/projection/performance_projector.dart';
import 'package:cripto_control_mx/cripto_control_app.dart' as legacy;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const migrator = AccountingMigrator(LegacyMovementAdapter());

  test('migration keeps legacy movements explicitly unassigned', () {
    final result = migrator.migrateLegacy(
      legacy: <Map<String, Object?>>[
        legacyBuy(id: 'old-1', platform: 'Mercado Pago'),
      ],
    );

    expect(result.document.wallets, isEmpty);
    expect(
      result.document.movements.single.walletAssignmentStatus,
      WalletAssignmentStatus.legacyUnassigned,
    );
    expect(result.unassignedMovementIds, <String>['old-1']);
  });

  test(
    'migration preserves valid legacy fields and quarantines invalid rows',
    () {
      final missingTypeAndDate = <String, Object?>{
        'id': 'bad-missing',
        'coin': 'BTC',
        'platform': 'Mercado Pago',
      };
      final unknownType = <String, Object?>{
        'id': 'bad-unknown',
        'type': 'mystery',
        'coin': 'ETH',
        'date': '2026-08-11T12:00:00Z',
      };

      final result = migrator.migrateLegacy(
        legacy: <Map<String, Object?>>[
          legacyBuy(id: 'buy-1', platform: 'Mercado Pago'),
          legacySell(id: 'sell-1'),
          legacyTransferOut(id: 'transfer-1'),
          missingTypeAndDate,
          unknownType,
        ],
      );

      expect(result.document.wallets, isEmpty);
      expect(result.document.movements, hasLength(3));
      expect(
        result.document.movements.map(
          (movement) => movement.walletAssignmentStatus,
        ),
        everyElement(WalletAssignmentStatus.legacyUnassigned),
      );
      expect(
        result.document.legacyMovementMetadata['buy-1']!['platform'],
        'Mercado Pago',
      );
      expect(
        result
            .document
            .legacyMovementMigrationMetadata['buy-1']!['projectionWalletId'],
        virtualUnassignedWalletId,
      );
      expect(
        result
            .document
            .legacyMovementMigrationMetadata['buy-1']!['accountingPolicy'],
        LegacyAccountingPolicy.preservePreviousGlobal.name,
      );
      expect(
        result.document.movements
            .where((movement) => movement.id == 'buy-1')
            .single
            .destinationWalletId,
        isNull,
      );
      expect(virtualUnassignedWalletId, 'virtual:unassigned');
      expect(result.problems, hasLength(2));
      expect(
        result.problems.first.kind,
        LegacyMigrationProblemKind.unconvertible,
      );
      expect(result.problems.first.sourceIndex, 3);
      expect(result.problems.first.primaryPayload, missingTypeAndDate);
      expect(
        result.problems.first.conversionIssues.map((issue) => issue.code),
        <LegacyConversionIssueCode>[
          LegacyConversionIssueCode.missingMovementType,
          LegacyConversionIssueCode.missingOccurredAt,
        ],
      );
      expect(result.problems[1].primaryPayload, unknownType);
      expect(
        result.document.movements.map((movement) => movement.id),
        isNot(contains('bad-missing')),
      );
    },
  );

  test('migration is idempotent and records the legacy global policy', () {
    final legacy = <Map<String, Object?>>[
      legacyBuy(id: 'same-1', platform: 'Mercado Pago'),
      legacySell(id: 'same-2'),
    ];
    final first = migrator.migrateLegacy(legacy: legacy);
    final second = migrator.migrateLegacy(
      legacy: legacy,
      existing: first.document,
    );

    expect(second.document.toJson(), first.document.toJson());
    expect(second.imported, 0);
    expect(second.skippedDuplicates, legacy.length);
    expect(
      second.document.appliedMigrationIds.where(
        (id) => id == legacyV1ToV3MigrationId,
      ),
      hasLength(1),
    );
    expect(
      second.document.legacyAccountingPolicy,
      LegacyAccountingPolicy.preservePreviousGlobal,
    );
  });

  test(
    'migration keeps the original competing payload for every later conflict',
    () {
      final first = legacyBuy(id: 'conflict', platform: 'A');
      final second = <String, Object?>{...first, 'quantity': '2'};
      final third = <String, Object?>{...first, 'quantity': '3'};

      final result = migrator.migrateLegacy(
        legacy: <Map<String, Object?>>[first, second, third],
      );

      expect(result.document.movements, isEmpty);
      expect(result.problems, hasLength(2));
      expect(
        result.problems.map((problem) => problem.conflictingPayload),
        everyElement(first),
      );
    },
  );

  test(
    'migration preserves an existing canonical movement on same-ID conflict',
    () {
      final original = migrator
          .migrateLegacy(
            legacy: <Map<String, Object?>>[
              legacyBuy(id: 'existing', platform: 'A'),
            ],
          )
          .document;
      final result = migrator.migrateLegacy(
        existing: original,
        legacy: <Map<String, Object?>>[
          <String, Object?>{
            ...legacyBuy(id: 'existing', platform: 'B'),
            'quantity': '9',
          },
        ],
      );

      expect(
        result.document.movements.single.toJson(),
        original.movements.single.toJson(),
      );
      expect(
        result.problems.single.kind,
        LegacyMigrationProblemKind.conflictingId,
      );
    },
  );

  test('missing legacy IDs receive deterministic RFC-4122 v4-shaped IDs', () {
    final source = legacyBuy(id: 'temporary', platform: 'A')..remove('id');

    final first = migrator.migrateLegacy(
      legacy: <Map<String, Object?>>[source],
    );
    final second = migrator.migrateLegacy(
      legacy: <Map<String, Object?>>[source],
    );

    expect(
      first.document.movements.single.id,
      second.document.movements.single.id,
    );
    expect(
      first.document.movements.single.id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test(
    'migration preserves colliding metadata keys and replays them as duplicates',
    () {
      final source = <String, Object?>{
        ...legacyBuy(id: 'opaque-meta', platform: 'A'),
        'legacyProjectionWalletId': 'original-value',
        'legacyAccountingPolicy': 'original-policy',
      };
      final first = migrator.migrateLegacy(
        legacy: <Map<String, Object?>>[source],
      );
      final replay = migrator.migrateLegacy(
        legacy: <Map<String, Object?>>[source],
        existing: first.document,
      );

      expect(first.document.legacyMovementMetadata['opaque-meta'], source);
      expect(replay.document.toJson(), first.document.toJson());
      expect(replay.skippedDuplicates, 1);
      expect(replay.problems, isEmpty);
    },
  );

  test('migration preserves legacy aggregate output before assignment', () {
    final source = <Map<String, Object?>>[
      <String, Object?>{
        'id': 'aggregate-buy',
        'type': 'buy',
        'coin': 'UNI',
        'date': '2026-08-11T12:00:00Z',
        'quantity': 10,
        'unitPrice': 10,
        'fee': 0,
      },
      <String, Object?>{
        'id': 'aggregate-transfer',
        'type': 'transfer_out',
        'coin': 'UNI',
        'date': '2026-08-11T13:00:00Z',
        'quantity': 4,
        'unitPrice': 0,
        'fee': 0,
        'receivedAmount': 4,
        'cryptoFeeAmount': 1,
        'cryptoFeeAsset': 'UNI',
        'totalDebitedAmount': 5,
      },
    ];
    final historical = <legacy.Movement>[
      legacy.Movement(
        id: 'aggregate-buy',
        type: MovementType.buy,
        coin: 'UNI',
        date: DateTime.parse('2026-08-11T12:00:00Z'),
        quantity: 10,
        unitPrice: 10,
        fee: 0,
        note: '',
      ),
      legacy.Movement(
        id: 'aggregate-transfer',
        type: MovementType.transferOut,
        coin: 'UNI',
        date: DateTime.parse('2026-08-11T13:00:00Z'),
        quantity: 4,
        unitPrice: 0,
        fee: 0,
        receivedAmount: 4,
        cryptoFeeAmount: 1,
        cryptoFeeAsset: 'UNI',
        totalDebitedAmount: 5,
        note: '',
      ),
    ];
    final expected = legacy.FinancialEngine.computeStats(
      coins: const <String>['UNI'],
      movements: historical,
      currentPrices: const <String, double>{'UNI': 50},
    )['UNI']!;
    final document = migrator.migrateLegacy(legacy: source).document;
    final projection =
        const AccountingLedgerEngine(
          DefaultMovementNormalizer(),
          DefaultCustodyProjector(),
          DefaultPerformanceProjector(),
        ).project(
          LedgerInput(
            wallets: const [],
            movements: document.movements,
            currentPrices: <String, AccountingAmount>{
              'UNI': AccountingAmount.fromInt(50),
            },
            saleCostConsumptionPolicy: SaleCostConsumptionPolicy.knownFirst,
            transferCostAllocationPolicy:
                TransferCostAllocationPolicy.proportional,
            legacyAccountingPolicy: document.legacyAccountingPolicy,
          ),
        );
    final actual = const LegacyFinancialAdapter().coinStats(projection, const {
      'UNI': 50,
    })['UNI']!;

    expect(actual.custodyQuantity, closeTo(expected.quantity, 0.00000001));
    expect(actual.costBase, closeTo(expected.costBase, 0.00000001));
  });
}

Map<String, Object?> legacyBuy({
  required String id,
  required String platform,
}) => <String, Object?>{
  'id': id,
  'type': 'buy',
  'coin': 'BTC',
  'date': '2026-08-11T12:00:00Z',
  'quantity': '0.25',
  'unitPrice': '1000000',
  'fee': '15',
  'platform': platform,
  'deletedAt': '2026-08-12T12:00:00Z',
  'deviceId': 'device-1',
  'note': 'historial',
};

Map<String, Object?> legacySell({required String id}) => <String, Object?>{
  'id': id,
  'type': 'sell',
  'coin': 'ETH',
  'date': '2026-08-11T13:00:00Z',
  'quantity': '1',
  'unitPrice': '50000',
  'fee': '10',
  'network': 'Ethereum',
};

Map<String, Object?> legacyTransferOut({required String id}) =>
    <String, Object?>{
      'id': id,
      'type': 'transfer_out',
      'coin': 'UNI',
      'date': '2026-08-11T14:00:00Z',
      'quantity': '4',
      'receivedAmount': '4',
      'cryptoFeeAmount': '1',
      'cryptoFeeAsset': 'UNI',
      'totalDebitedAmount': '5',
      'sourcePlatform': 'Mercado Pago',
      'destinationPlatform': 'Bitso',
    };
