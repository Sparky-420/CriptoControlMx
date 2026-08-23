import '../../accounting/application/movement_assignment_command.dart';
import '../../accounting/application/movement_assignment_service.dart';
import '../../accounting/domain/accounting_movement.dart';
import '../../accounting/domain/movement_type.dart';
import '../../accounting/domain/wallet.dart';
import '../../accounting/persistence/accounting_document.dart';
import '../../accounting/persistence/accounting_repository.dart';

enum WalletMovementAssignmentRole { source, destination, adjustment }

typedef WalletAssignmentOperationIdFactory = String Function();
typedef WalletAssignmentClock = DateTime Function();

final class DefaultWalletMovementAssignmentService {
  const DefaultWalletMovementAssignmentService(
    this.repository, {
    this.assignmentService = const DefaultMovementAssignmentService(),
    this.operationIdFactory = _defaultOperationId,
    this.clock = _defaultClock,
  });

  final AccountingRepository repository;
  final MovementAssignmentService assignmentService;
  final WalletAssignmentOperationIdFactory operationIdFactory;
  final WalletAssignmentClock clock;

  Future<AccountingDocument> assignWallet(
    AccountingDocument current, {
    required String movementId,
    required String walletId,
    required WalletMovementAssignmentRole role,
  }) async {
    final movement = current.movements.firstWhere(
      (movement) => movement.id == movementId,
      orElse: () => throw ArgumentError.value(
        movementId,
        'movementId',
        'Movimiento inexistente.',
      ),
    );
    final result = assignmentService.assignOne(
      current,
      command: walletAssignmentCommandFor(movement, role, walletId),
      operationId: operationIdFactory(),
      assignedAt: clock().toUtc(),
    );
    await repository.write(result.document);
    return result.document;
  }
}

MovementAssignmentCommand walletAssignmentCommandFor(
  AccountingMovement movement,
  WalletMovementAssignmentRole role,
  String walletId,
) => switch (role) {
  WalletMovementAssignmentRole.source =>
    movement.type == MovementType.sell ||
            movement.type == MovementType.transferOut
        ? AssignSourceWallet(movement.id, walletId)
        : throw ArgumentError('Asignación de origen incompatible.'),
  WalletMovementAssignmentRole.destination =>
    movement.type == MovementType.buy ||
            movement.type == MovementType.transferIn
        ? AssignDestinationWallet(movement.id, walletId)
        : movement.type == MovementType.transferOut
        ? AssignOwnTransferDestination(movement.id, walletId)
        : throw ArgumentError('Asignación de destino incompatible.'),
  WalletMovementAssignmentRole.adjustment =>
    movement.type == MovementType.balanceAdjustment
        ? AssignAdjustmentWallet(movement.id, walletId)
        : throw ArgumentError('Asignación de ajuste incompatible.'),
};

List<WalletMovementAssignmentRole> walletPendingAssignmentRoles(
  AccountingMovement movement,
) {
  if (movement.walletAssignmentStatus == WalletAssignmentStatus.assigned) {
    return const <WalletMovementAssignmentRole>[];
  }
  return switch (movement.type) {
    MovementType.buy || MovementType.transferIn =>
      movement.destinationWalletId == null
          ? const <WalletMovementAssignmentRole>[
              WalletMovementAssignmentRole.destination,
            ]
          : const <WalletMovementAssignmentRole>[],
    MovementType.sell =>
      movement.sourceWalletId == null
          ? const <WalletMovementAssignmentRole>[
              WalletMovementAssignmentRole.source,
            ]
          : const <WalletMovementAssignmentRole>[],
    MovementType.balanceAdjustment =>
      movement.adjustmentWalletId == null
          ? const <WalletMovementAssignmentRole>[
              WalletMovementAssignmentRole.adjustment,
            ]
          : const <WalletMovementAssignmentRole>[],
    MovementType.transferOut => <WalletMovementAssignmentRole>[
      if (movement.sourceWalletId == null) WalletMovementAssignmentRole.source,
      if (movement.destinationWalletId == null &&
          movement.destinationType != DestinationType.external)
        WalletMovementAssignmentRole.destination,
    ],
  };
}

String _defaultOperationId() =>
    'wallet-ui-${DateTime.now().toUtc().microsecondsSinceEpoch}';

DateTime _defaultClock() => DateTime.now().toUtc();
