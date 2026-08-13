import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_document.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_repository.dart';
import 'package:cripto_control_mx/accounting/persistence/shared_preferences_accounting_repository.dart';
import 'package:cripto_control_mx/accounting/support/entity_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('repository round-trips only the canonical v3 document', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = SharedPreferencesAccountingRepository();
    final document = documentFixture(schemaVersion: 3);

    await repository.write(document);

    expect((await repository.read())!.toJson(), document.toJson());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('movements_json'), isFalse);
    expect(prefs.containsKey('saldo_json'), isFalse);
    expect(prefs.containsKey('ledger_projection'), isFalse);
    expect(document.toJson()['wallets'], hasLength(1));
    expect(document.toJson()['movements'], hasLength(1));
    expect(
      (document.toJson()['movements']! as List<Object?>).first
          as Map<String, Object?>,
      containsPair('quantity', '0.12345678'),
    );
    expect(
      (document.toJson()['wallets']! as List<Object?>).first
          as Map<String, Object?>,
      containsPair('schemaVersion', 1),
    );
  });

  test(
    'repository replaces only its canonical value and clears only it',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'movements_json': '["legacy"]',
        'unrelated': 'preserve',
      });
      final repository = SharedPreferencesAccountingRepository();
      final first = documentFixture(schemaVersion: 3);
      final second = AccountingDocument(
        schemaVersion: 3,
        wallets: first.wallets,
        movements: const <AccountingMovement>[],
        appliedMigrationIds: const <String>{},
        updatedAt: DateTime.utc(2026, 8, 12),
      );

      await repository.write(first);
      await repository.write(second);
      await repository.clear();

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey(accountingDocumentKey), isFalse);
      expect(preferences.getString('movements_json'), '["legacy"]');
      expect(preferences.getString('unrelated'), 'preserve');
    },
  );

  test('entity ids are unique canonical UUID-v4 values without prefixes', () {
    const generator = EntityIdGenerator();
    final walletIds = List<String>.generate(100, (_) => generator.walletId());
    final movementIds = List<String>.generate(
      100,
      (_) => generator.movementId(),
    );
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    expect(<String>{...walletIds, ...movementIds}, hasLength(200));
    expect(walletIds.followedBy(movementIds), everyElement(matches(uuidV4)));
  });

  test(
    'malformed canonical input reports key and cause without replacing it',
    () async {
      const malformed = '{not valid json';
      SharedPreferences.setMockInitialValues(<String, Object>{
        accountingDocumentKey: malformed,
      });
      final repository = SharedPreferencesAccountingRepository();

      await expectLater(
        repository.read(),
        throwsA(
          isA<AccountingPersistenceException>()
              .having((error) => error.key, 'key', accountingDocumentKey)
              .having((error) => error.cause, 'cause', isA<FormatException>()),
        ),
      );
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(accountingDocumentKey), malformed);
    },
  );

  test('wrong typed canonical input reports key and cause', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      accountingDocumentKey: 3,
    });
    final repository = SharedPreferencesAccountingRepository();

    await expectLater(
      repository.read(),
      throwsA(
        isA<AccountingPersistenceException>()
            .having((error) => error.key, 'key', accountingDocumentKey)
            .having((error) => error.cause, 'cause', isA<TypeError>()),
      ),
    );
  });

  test('invalid document schema cannot be persisted', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = SharedPreferencesAccountingRepository();

    await expectLater(
      Future<void>.sync(
        () => repository.write(documentFixture(schemaVersion: 2)),
      ),
      throwsA(
        isA<UnsupportedAccountingSchemaException>().having(
          (error) => error.version,
          'version',
          2,
        ),
      ),
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey(accountingDocumentKey), isFalse);
  });

  test('repository reports unsuccessful canonical write', () async {
    final repository = SharedPreferencesAccountingRepository(
      writeString: (_, _, _) async => false,
    );

    await expectLater(
      repository.write(documentFixture(schemaVersion: 3)),
      throwsA(
        isA<AccountingPersistenceException>().having(
          (error) => error.key,
          'key',
          accountingDocumentKey,
        ),
      ),
    );
  });

  test('repository reports unsuccessful canonical removal', () async {
    final repository = SharedPreferencesAccountingRepository(
      remove: (_, _) async => false,
    );

    await expectLater(
      repository.clear(),
      throwsA(
        isA<AccountingPersistenceException>().having(
          (error) => error.key,
          'key',
          accountingDocumentKey,
        ),
      ),
    );
  });

  test('document rejects future schemas and orders migration ids', () {
    final document = documentFixture(schemaVersion: 3);

    expect(document.toJson()['appliedMigrationIds'], <String>[
      'legacy-v1',
      'legacy-v2',
    ]);
    expect(
      () => AccountingDocument.fromJson(<String, Object?>{
        ...document.toJson(),
        'schemaVersion': 4,
      }),
      throwsA(
        isA<UnsupportedAccountingSchemaException>().having(
          (error) => error.version,
          'version',
          4,
        ),
      ),
    );
  });

  test('document preserves multiple event order', () {
    final first = documentFixture(schemaVersion: 3).movements.single;
    final second = first.copyWith(
      id: '33333333-3333-4333-8333-333333333333',
      occurredAt: first.occurredAt.add(const Duration(minutes: 1)),
    );
    final document = AccountingDocument(
      schemaVersion: 3,
      wallets: documentFixture(schemaVersion: 3).wallets,
      movements: <AccountingMovement>[second, first],
      appliedMigrationIds: const <String>{},
      updatedAt: first.updatedAt,
    );

    expect(
      (document.toJson()['movements']! as List<Object?>)
          .map((movement) => (movement! as Map<Object?, Object?>)['id'])
          .toList(),
      <String>[second.id, first.id],
    );
  });

  test('PERSIST-1 document remains readable without migration problems', () {
    final persistedV1 = documentFixture(schemaVersion: 3).toJson()
      ..remove('legacyMovementMetadata')
      ..remove('legacyMigrationProblems')
      ..remove('legacyAccountingPolicy');

    final restored = AccountingDocument.fromJson(persistedV1);

    expect(restored.legacyMigrationProblems, isEmpty);
    expect(restored.toJson()['legacyMigrationProblems'], isEmpty);
  });

  test(
    'repository round-trip preserves multiple movement event order',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final first = documentFixture(schemaVersion: 3).movements.single;
      final second = first.copyWith(
        id: '33333333-3333-4333-8333-333333333333',
        occurredAt: first.occurredAt.add(const Duration(minutes: 1)),
      );
      final document = AccountingDocument(
        schemaVersion: 3,
        wallets: documentFixture(schemaVersion: 3).wallets,
        movements: <AccountingMovement>[second, first],
        appliedMigrationIds: const <String>{},
        updatedAt: first.updatedAt,
      );
      final repository = SharedPreferencesAccountingRepository();

      await repository.write(document);

      expect(
        (await repository.read())!.movements.map((movement) => movement.id),
        <String>[second.id, first.id],
      );
    },
  );
}

AccountingDocument documentFixture({required int schemaVersion}) {
  final at = DateTime.utc(2026, 8, 11, 20, 54);
  return AccountingDocument(
    schemaVersion: schemaVersion,
    wallets: <Wallet>[
      Wallet(
        id: '11111111-1111-4111-8111-111111111111',
        name: 'Principal',
        provider: 'Bitso',
        status: WalletStatus.active,
        imageRef: const WalletImageRef(
          id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          fileName: 'bitso.png',
          mimeType: 'image/png',
          sha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          width: 24,
          height: 24,
          byteLength: 128,
        ),
        createdAt: at,
        updatedAt: at,
      ),
    ],
    movements: <AccountingMovement>[
      AccountingMovement(
        id: '22222222-2222-4222-8222-222222222222',
        type: MovementType.transferOut,
        asset: 'BTC',
        occurredAt: at,
        quantity: AccountingAmount.parse('0.12345678'),
        fiatFeeAmount: AccountingAmount.parse('0.50'),
        sourceWalletId: '11111111-1111-4111-8111-111111111111',
        destinationWalletId: '33333333-3333-4333-8333-333333333333',
        destinationType: DestinationType.ownWallet,
        walletAssignmentStatus: WalletAssignmentStatus.assigned,
        receivedAmount: AccountingAmount.parse('0.12000001'),
        cryptoFeeAmount: AccountingAmount.parse('0.00345677'),
        cryptoFeeAsset: 'BTC',
        totalDebitedAmount: AccountingAmount.parse('0.12345678'),
        fiatFeeTreatment: FiatFeeTreatment.valuationOfCryptoFee,
        reconciliationLinks: const <ReconciliationLink>[],
        createdAt: at,
        updatedAt: at,
      ),
    ],
    appliedMigrationIds: <String>{'legacy-v2', 'legacy-v1'},
    updatedAt: at,
  );
}
