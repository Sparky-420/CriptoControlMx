import 'package:cripto_control_mx/accounting/adapters/legacy_movement_adapter.dart';
import 'package:cripto_control_mx/accounting/adapters/legacy_persistence_bridge.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/migration/accounting_migrator.dart';
import 'package:cripto_control_mx/accounting/migration/legacy_migration_problem.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_document.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_repository.dart';
import 'package:cripto_control_mx/accounting/persistence/shared_preferences_accounting_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const adapter = LegacyMovementAdapter();

  test(
    'load migrates legacy source once and persists only the v3 document',
    () async {
      const legacyEncoded =
          '[{"id":"old-1","type":"buy","coin":"BTC","date":"2026-08-11T12:00:00Z","quantity":"0.25","unitPrice":"1000000","fee":"15","platform":"Mercado Pago","note":"historial"}]';
      SharedPreferences.setMockInitialValues(<String, Object>{
        'movements_json': legacyEncoded,
      });
      final repository = SharedPreferencesAccountingRepository();
      final bridge = LegacyPersistenceBridge(
        repository,
        AccountingMigrator(adapter),
        adapter,
      );

      final loaded = await bridge.load(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'old-1',
          'type': 'buy',
          'coin': 'BTC',
          'date': '2026-08-11T12:00:00Z',
          'quantity': '0.25',
          'unitPrice': '1000000',
          'fee': '15',
          'platform': 'Mercado Pago',
          'note': 'historial',
        },
      ]);

      expect(loaded.migrationReport!.imported, 1);
      expect((await repository.read())!.toJson(), loaded.document.toJson());
      expect(loaded.legacyView.single['platform'], 'Mercado Pago');
      expect(loaded.legacyView.single['note'], 'historial');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('movements_json'), legacyEncoded);
      expect(preferences.containsKey(accountingDocumentKey), isTrue);
    },
  );

  test(
    'legacy-view save preserves v3 wallet fields without dual persistence',
    () async {
      const legacyEncoded = '[{"legacy":"unchanged"}]';
      SharedPreferences.setMockInitialValues(<String, Object>{
        'movements_json': legacyEncoded,
      });
      final current = assignedDocumentFixture();
      final repository = SharedPreferencesAccountingRepository();
      final bridge = LegacyPersistenceBridge(
        repository,
        const AccountingMigrator(adapter),
        adapter,
      );
      final legacy =
          adapter.toLegacyJson(
              current.movements.single,
              preservedFields: current.legacyMovementMetadata['old-1']!,
            )
            ..['note'] = 'nota editada'
            ..['date'] = '2026-08-15T16:30:00Z'
            ..['quantity'] = '0.75'
            ..['fee'] = '21';

      final saved = await bridge.saveLegacyView(current, <Map<String, Object?>>[
        legacy,
      ]);

      final movement = saved.movements.single;
      expect(movement.note, 'nota editada');
      expect(movement.occurredAt, DateTime.utc(2026, 8, 15, 16, 30));
      expect(movement.quantity, AccountingAmount.parse('0.75'));
      expect(movement.fiatFeeAmount, AccountingAmount.fromInt(21));
      expect(
        movement.destinationWalletId,
        '11111111-1111-4111-8111-111111111111',
      );
      expect(movement.destinationType, DestinationType.ownWallet);
      expect(
        movement.adjustmentWalletId,
        '11111111-1111-4111-8111-111111111111',
      );
      expect(
        movement.reconciliationLinks.single.adjustmentMovementId,
        'adjust-1',
      );
      expect(
        saved.wallets.map((wallet) => wallet.toJson()).toList(),
        current.wallets.map((wallet) => wallet.toJson()).toList(),
      );
      expect(saved.legacyMovementMetadata, current.legacyMovementMetadata);
      expect(
        saved.legacyMovementMigrationMetadata,
        current.legacyMovementMigrationMetadata,
      );
      expect(
        saved.legacyMigrationProblems.map((problem) => problem.toJson()),
        current.legacyMigrationProblems.map((problem) => problem.toJson()),
      );
      expect((await repository.read())!.toJson(), saved.toJson());
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('movements_json'), legacyEncoded);
    },
  );
}

AccountingDocument assignedDocumentFixture() {
  final updatedAt = DateTime.utc(2026, 8, 12);
  const walletId = '11111111-1111-4111-8111-111111111111';
  final wallet = Wallet.create(
    id: walletId,
    name: 'Bitso',
    provider: 'Bitso',
    createdAt: updatedAt,
    imageRef: WalletImageRef.create(
      id: 'a' * 64,
      fileName: 'bitso.png',
      mimeType: 'image/png',
      sha256: 'a' * 64,
      width: 40,
      height: 40,
      byteLength: 123,
    ),
  );
  return AccountingDocument(
    schemaVersion: accountingSchemaVersion,
    wallets: <Wallet>[wallet],
    movements: <AccountingMovement>[
      AccountingMovement(
        id: 'old-1',
        type: MovementType.buy,
        asset: 'BTC',
        occurredAt: DateTime.utc(2026, 8, 11, 12),
        quantity: AccountingAmount.parse('0.25'),
        unitPriceFiat: AccountingAmount.fromInt(1000000),
        fiatFeeAmount: AccountingAmount.fromInt(15),
        sourceWalletId: walletId,
        destinationWalletId: walletId,
        destinationType: DestinationType.ownWallet,
        walletAssignmentStatus: WalletAssignmentStatus.assigned,
        cryptoFeeAmount: AccountingAmount.zero,
        fiatFeeTreatment: FiatFeeTreatment.paidSeparately,
        adjustmentWalletId: walletId,
        adjustmentQuantity: AccountingAmount.parse('0.01'),
        reconciliationLinks: <ReconciliationLink>[
          ReconciliationLink(
            adjustmentMovementId: 'adjust-1',
            quantityResolved: AccountingAmount.parse('0.01'),
          ),
        ],
        createdAt: updatedAt,
        updatedAt: updatedAt,
      ),
    ],
    appliedMigrationIds: const <String>{legacyV1ToV3MigrationId},
    updatedAt: updatedAt,
    legacyMovementMetadata: <String, Map<String, Object?>>{
      'old-1': <String, Object?>{
        'id': 'old-1',
        'type': 'buy',
        'coin': 'BTC',
        'date': '2026-08-11T12:00:00Z',
        'quantity': '0.25',
        'unitPrice': '1000000',
        'fee': '15',
        'platform': 'Mercado Pago',
      },
    },
    legacyMovementMigrationMetadata: <String, Map<String, Object?>>{
      'old-1': <String, Object?>{'projectionWalletId': 'virtual:unassigned'},
    },
    legacyMigrationProblems: <LegacyMigrationProblem>[
      LegacyMigrationProblem.create(
        kind: LegacyMigrationProblemKind.unconvertible,
        sourceIndex: 1,
        primaryPayload: const <String, Object?>{'id': 'broken'},
      ),
    ],
  );
}
