import '../domain/assignment_audit.dart';
import '../domain/wallet.dart';

sealed class MovementAssignmentCommand {
  const MovementAssignmentCommand(this.movementId);
  final String movementId;
  WalletAssignmentTarget get target;
}

final class AssignSourceWallet extends MovementAssignmentCommand {
  const AssignSourceWallet(super.movementId, this.walletId);
  final String walletId;
  @override
  WalletAssignmentTarget get target => WalletAssignmentTarget.source;
}

final class AssignDestinationWallet extends MovementAssignmentCommand {
  const AssignDestinationWallet(super.movementId, this.walletId);
  final String walletId;
  @override
  WalletAssignmentTarget get target => WalletAssignmentTarget.destination;
}

final class AssignOwnTransferDestination extends MovementAssignmentCommand {
  const AssignOwnTransferDestination(super.movementId, this.walletId);
  final String walletId;
  DestinationType get destinationType => DestinationType.ownWallet;
  @override
  WalletAssignmentTarget get target => WalletAssignmentTarget.destination;
}

final class ClassifyExternalTransferDestination
    extends MovementAssignmentCommand {
  const ClassifyExternalTransferDestination(super.movementId);
  DestinationType get destinationType => DestinationType.external;
  @override
  WalletAssignmentTarget get target => WalletAssignmentTarget.destination;
}

final class AssignAdjustmentWallet extends MovementAssignmentCommand {
  const AssignAdjustmentWallet(super.movementId, this.walletId);
  final String walletId;
  @override
  WalletAssignmentTarget get target => WalletAssignmentTarget.adjustment;
}
