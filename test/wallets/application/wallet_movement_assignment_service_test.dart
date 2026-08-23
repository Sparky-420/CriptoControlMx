import 'package:cripto_control_mx/accounting/application/movement_assignment_command.dart';
import 'package:cripto_control_mx/accounting/application/movement_assignment_service.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_document.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_repository.dart';
import 'package:cripto_control_mx/wallets/application/wallet_movement_assignment_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DefaultWalletMovementAssignmentService', () {
    test(
      'persists a destination assignment through the accounting service',
      () async {
        final repository = _MemoryAccountingRepository();
        final assignmentService = _FakeMovementAssignmentService();
        final service = DefaultWalletMovementAssignmentService(
          repository,
          assignmentService: assignmentService,
          operationIdFactory: () => 'wallet-ui-op',
          clock: () => DateTime.utc(2026, 8, 24),
        );
        final wallet = _wallet(id: walletOneId, name: 'Bitso');
        final movement = _movement(
          id: 'buy-1',
          type: MovementType.buy,
          status: WalletAssignmentStatus.legacyUnassigned,
        );
        final current = _document(
          wallets: <Wallet>[wallet],
          movements: <AccountingMovement>[movement],
        );
        final assignedDocument = _document(
          wallets: <Wallet>[wallet],
          movements: <AccountingMovement>[
            movement.copyWith(
              destinationWalletId: wallet.id,
              walletAssignmentStatus: WalletAssignmentStatus.assigned,
            ),
          ],
        );
        assignmentService.next = AssignmentResult(
          document: assignedDocument,
          changedIds: const <String>['buy-1'],
          unchangedIds: const <String>[],
        );

        final result = await service.assignWallet(
          current,
          movementId: movement.id,
          walletId: wallet.id,
          role: WalletMovementAssignmentRole.destination,
        );

        expect(result, same(assignedDocument));
        expect(repository.written, same(assignedDocument));
        expect(assignmentService.command, isA<AssignDestinationWallet>());
        expect(assignmentService.command!.movementId, 'buy-1');
        expect(
          (assignmentService.command! as AssignDestinationWallet).walletId,
          wallet.id,
        );
        expect(assignmentService.operationId, 'wallet-ui-op');
        expect(assignmentService.assignedAt, DateTime.utc(2026, 8, 24));
      },
    );

    test('maps supported pending roles to existing accounting commands', () {
      expect(
        walletAssignmentCommandFor(
          _movement(id: 'sell-1', type: MovementType.sell),
          WalletMovementAssignmentRole.source,
          walletOneId,
        ),
        isA<AssignSourceWallet>(),
      );
      expect(
        walletAssignmentCommandFor(
          _movement(
            id: 'transfer-1',
            type: MovementType.transferOut,
            destinationType: DestinationType.ownWallet,
          ),
          WalletMovementAssignmentRole.destination,
          walletTwoId,
        ),
        isA<AssignOwnTransferDestination>(),
      );
      expect(
        walletAssignmentCommandFor(
          _movement(id: 'adjust-1', type: MovementType.balanceAdjustment),
          WalletMovementAssignmentRole.adjustment,
          walletOneId,
        ),
        isA<AssignAdjustmentWallet>(),
      );
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

AccountingMovement _movement({
  required String id,
  required MovementType type,
  WalletAssignmentStatus status = WalletAssignmentStatus.pending,
  DestinationType? destinationType,
}) => AccountingMovement(
  id: id,
  type: type,
  asset: 'UNI',
  occurredAt: DateTime.utc(2026, 8, 23),
  quantity: AccountingAmount.parse('1.5'),
  fiatFeeAmount: AccountingAmount.zero,
  walletAssignmentStatus: status,
  cryptoFeeAmount: AccountingAmount.zero,
  fiatFeeTreatment: FiatFeeTreatment.none,
  reconciliationLinks: const <ReconciliationLink>[],
  createdAt: DateTime.utc(2026, 8, 23),
  updatedAt: DateTime.utc(2026, 8, 23),
  destinationType: destinationType,
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

final class _FakeMovementAssignmentService
    implements MovementAssignmentService {
  late AssignmentResult next;
  MovementAssignmentCommand? command;
  String? operationId;
  DateTime? assignedAt;

  @override
  AssignmentResult assignMany(
    AccountingDocument document, {
    required List<MovementAssignmentCommand> commands,
    required String operationId,
    required DateTime assignedAt,
  }) {
    throw UnimplementedError();
  }

  @override
  AssignmentResult assignOne(
    AccountingDocument document, {
    required MovementAssignmentCommand command,
    required String operationId,
    required DateTime assignedAt,
  }) {
    this.command = command;
    this.operationId = operationId;
    this.assignedAt = assignedAt;
    return next;
  }
}
