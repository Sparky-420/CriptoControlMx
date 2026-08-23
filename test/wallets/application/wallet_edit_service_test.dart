import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_document.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_repository.dart';
import 'package:cripto_control_mx/wallets/application/wallet_edit_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DefaultWalletEditService', () {
    test('creates a wallet in the canonical v3 document', () async {
      final repository = _MemoryAccountingRepository();
      final service = DefaultWalletEditService(repository);
      final current = _document(wallets: const <Wallet>[]);
      final now = DateTime.utc(2026, 8, 24);

      final result = await service.createWallet(
        current,
        id: '11111111-1111-4111-8111-111111111111',
        name: '  Mercado Pago  ',
        provider: '  Mercado Pago  ',
        now: now,
      );

      expect(result.wallet.name, 'Mercado Pago');
      expect(result.wallet.provider, 'Mercado Pago');
      expect(result.document.wallets, <Wallet>[result.wallet]);
      expect(repository.written, same(result.document));
    });

    test(
      'updates only wallet identity fields without touching movements',
      () async {
        final repository = _MemoryAccountingRepository();
        final service = DefaultWalletEditService(repository);
        final createdAt = DateTime.utc(2026, 8, 23);
        final updatedAt = DateTime.utc(2026, 8, 24);
        final existing = Wallet.create(
          id: '11111111-1111-4111-8111-111111111111',
          name: 'Bitso',
          provider: 'Bitso',
          createdAt: createdAt,
        );
        final current = _document(wallets: <Wallet>[existing]);

        final result = await service.updateWallet(
          current,
          walletId: existing.id,
          name: '  Bitso Principal  ',
          provider: '  Bitso México  ',
          now: updatedAt,
        );

        expect(result.wallet.id, existing.id);
        expect(result.wallet.name, 'Bitso Principal');
        expect(result.wallet.provider, 'Bitso México');
        expect(result.wallet.status, existing.status);
        expect(result.wallet.createdAt, createdAt);
        expect(result.wallet.updatedAt, updatedAt);
        expect(result.document.movements, isEmpty);
        expect(repository.written, same(result.document));
      },
    );
  });
}

AccountingDocument _document({required List<Wallet> wallets}) =>
    AccountingDocument(
      schemaVersion: accountingSchemaVersion,
      wallets: wallets,
      movements: const <Never>[],
      appliedMigrationIds: const <String>{},
      updatedAt: DateTime.utc(2026, 8, 23),
    );

final class _MemoryAccountingRepository implements AccountingRepository {
  AccountingDocument? written;

  @override
  Future<void> clear() async {}

  @override
  Future<AccountingDocument?> read() async => written;

  @override
  Future<void> write(AccountingDocument document) async {
    written = document;
  }
}
