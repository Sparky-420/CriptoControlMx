import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_document.dart';
import 'package:cripto_control_mx/wallets/application/wallet_portfolio_summary_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DefaultWalletPortfolioSummaryService', () {
    test('summarizes assigned movements and assets by wallet', () {
      final bitso = _wallet(id: walletOneId, name: 'Bitso');
      final ledger = _wallet(id: walletTwoId, name: 'Ledger');
      final document = _document(
        wallets: <Wallet>[bitso, ledger],
        movements: <AccountingMovement>[
          _buy(
            id: 'bitso-uni',
            asset: 'UNI',
            quantity: '2',
            price: '10',
            walletId: bitso.id,
          ),
          _buy(
            id: 'ledger-btc',
            asset: 'BTC',
            quantity: '1',
            price: '100',
            walletId: ledger.id,
          ),
        ],
      );

      final summaries = const DefaultWalletPortfolioSummaryService().summarize(
        document,
      );
      final bitsoSummary = summaries.singleWhere(
        (summary) => summary.wallet.id == bitso.id,
      );

      expect(bitsoSummary.assignedMovementCount, 1);
      expect(bitsoSummary.assets, <String>['UNI']);
      expect(bitsoSummary.knownCostBasis.toJson(), '20');
      expect(bitsoSummary.positions.single.reconciledQuantity.toJson(), '2');
      expect(bitsoSummary.positions.single.knownQuantity.toJson(), '2');
      expect(bitsoSummary.completenessStates, <AccountingCompleteness>{
        AccountingCompleteness.complete,
      });
    });

    test('marks summaries with unknown cost as incomplete', () {
      final wallet = _wallet(id: walletOneId, name: 'Mercado Pago');
      final summaries = const DefaultWalletPortfolioSummaryService().summarize(
        _document(
          wallets: <Wallet>[wallet],
          movements: <AccountingMovement>[
            _transferIn(id: 'unknown-uni', walletId: wallet.id),
          ],
        ),
      );

      final summary = summaries.single;

      expect(summary.assignedMovementCount, 1);
      expect(summary.assets, <String>['UNI']);
      expect(summary.hasIncompleteData, isTrue);
      expect(summary.completenessStates, <AccountingCompleteness>{
        AccountingCompleteness.partiallyKnown,
      });
      expect(summary.knownCostBasis, AccountingAmount.zero);
    });
  });
}

const walletOneId = '11111111-1111-4111-8111-111111111111';
const walletTwoId = '22222222-2222-4222-8222-222222222222';

AccountingDocument _document({
  required List<Wallet> wallets,
  required List<AccountingMovement> movements,
}) => AccountingDocument(
  schemaVersion: accountingSchemaVersion,
  wallets: wallets,
  movements: movements,
  appliedMigrationIds: const <String>{},
  updatedAt: DateTime.utc(2026, 8, 23),
);

Wallet _wallet({required String id, required String name}) => Wallet.create(
  id: id,
  name: name,
  provider: name,
  createdAt: DateTime.utc(2026, 8, 23),
);

AccountingMovement _buy({
  required String id,
  required String asset,
  required String quantity,
  required String price,
  required String walletId,
}) => _movement(
  id: id,
  type: MovementType.buy,
  asset: asset,
  quantity: quantity,
  unitPriceFiat: price,
  destinationWalletId: walletId,
);

AccountingMovement _transferIn({
  required String id,
  required String walletId,
}) => _movement(
  id: id,
  type: MovementType.transferIn,
  asset: 'UNI',
  quantity: '0.75883985',
  destinationWalletId: walletId,
);

AccountingMovement _movement({
  required String id,
  required MovementType type,
  required String asset,
  required String quantity,
  String? unitPriceFiat,
  String? sourceWalletId,
  String? destinationWalletId,
}) => AccountingMovement(
  id: id,
  type: type,
  asset: asset,
  occurredAt: DateTime.utc(2026, 8, 23),
  quantity: AccountingAmount.parse(quantity),
  unitPriceFiat: unitPriceFiat == null
      ? null
      : AccountingAmount.parse(unitPriceFiat),
  fiatFeeAmount: AccountingAmount.zero,
  sourceWalletId: sourceWalletId,
  destinationWalletId: destinationWalletId,
  walletAssignmentStatus: WalletAssignmentStatus.assigned,
  cryptoFeeAmount: AccountingAmount.zero,
  fiatFeeTreatment: FiatFeeTreatment.none,
  reconciliationLinks: const <ReconciliationLink>[],
  createdAt: DateTime.utc(2026, 8, 23),
  updatedAt: DateTime.utc(2026, 8, 23),
);
