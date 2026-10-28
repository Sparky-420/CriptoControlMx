import '../domain/accounting_movement.dart';
import '../domain/assignment_audit.dart';
import '../domain/movement_type.dart';
import '../domain/wallet.dart';
import '../persistence/accounting_document.dart';
import 'movement_assignment_command.dart';

final class AssignmentResult {
  const AssignmentResult({
    required this.document,
    required this.changedIds,
    required this.unchangedIds,
  });

  final AccountingDocument document;
  final List<String> changedIds;
  final List<String> unchangedIds;
}

abstract interface class MovementAssignmentService {
  AssignmentResult assignOne(
    AccountingDocument document, {
    required MovementAssignmentCommand command,
    required String operationId,
    required DateTime assignedAt,
  });

  AssignmentResult assignMany(
    AccountingDocument document, {
    required List<MovementAssignmentCommand> commands,
    required String operationId,
    required DateTime assignedAt,
  });
}

final class DefaultMovementAssignmentService
    implements MovementAssignmentService {
  const DefaultMovementAssignmentService();

  @override
  AssignmentResult assignOne(
    AccountingDocument document, {
    required MovementAssignmentCommand command,
    required String operationId,
    required DateTime assignedAt,
  }) => assignMany(
    document,
    commands: <MovementAssignmentCommand>[command],
    operationId: operationId,
    assignedAt: assignedAt,
  );

  @override
  AssignmentResult assignMany(
    AccountingDocument document, {
    required List<MovementAssignmentCommand> commands,
    required String operationId,
    required DateTime assignedAt,
  }) {
    if (operationId.trim().isEmpty) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'No puede estar vacío.',
      );
    }
    final byId = <String, AccountingMovement>{
      for (final movement in document.movements) movement.id: movement,
    };
    final commandsById = <String, List<MovementAssignmentCommand>>{};
    for (final command in commands) {
      (commandsById[command.movementId] ??= <MovementAssignmentCommand>[]).add(
        command,
      );
    }
    for (final entry in commandsById.entries) {
      final targets = <WalletAssignmentTarget>{};
      final movement = byId[entry.key];
      if (movement == null) {
        throw ArgumentError.value(
          entry.key,
          'movementId',
          'Movimiento inexistente.',
        );
      }
      for (final command in entry.value) {
        if (!targets.add(command.target)) {
          throw ArgumentError(
            'Comandos conflictivos para ${entry.key}:${command.target.name}.',
          );
        }
        _validateCommand(document, movement, command);
      }
    }

    final replacements = <String, AccountingMovement>{};
    final audits = <AssignmentAudit>[];
    final changed = <String>[];
    final unchanged = <String>[];
    for (final movementId in commandsById.keys) {
      final beforeMovement = byId[movementId]!;
      var afterMovement = beforeMovement;
      final changedTargets = <WalletAssignmentTarget>{};
      for (final command in commandsById[movementId]!) {
        final applied = _apply(afterMovement, command);
        if (!_sameTarget(afterMovement, applied, command.target)) {
          changedTargets.add(command.target);
        }
        afterMovement = applied;
      }
      if (changedTargets.isEmpty) {
        unchanged.add(movementId);
        continue;
      }
      afterMovement = afterMovement.copyWith(
        walletAssignmentStatus: _status(afterMovement),
      );
      if (afterMovement.destinationType == DestinationType.ownWallet &&
          afterMovement.sourceWalletId == afterMovement.destinationWalletId) {
        throw ArgumentError(
          'Una transferencia interna requiere carteras distintas.',
        );
      }
      afterMovement = afterMovement.copyWith(updatedAt: assignedAt);
      replacements[movementId] = afterMovement;
      changed.add(movementId);
      audits.add(
        AssignmentAudit(
          id: '${operationId.trim()}:$movementId',
          operationId: operationId.trim(),
          movementId: movementId,
          changedTargets: changedTargets,
          before: _snapshot(beforeMovement),
          after: _snapshot(afterMovement),
          assignedAt: assignedAt,
        ),
      );
    }
    changed.sort();
    unchanged.sort();
    if (changed.isEmpty) {
      return AssignmentResult(
        document: document,
        changedIds: changed,
        unchangedIds: unchanged,
      );
    }
    return AssignmentResult(
      document: AccountingDocument(
        schemaVersion: document.schemaVersion,
        wallets: document.wallets,
        movements: <AccountingMovement>[
          for (final movement in document.movements)
            replacements[movement.id] ?? movement,
        ],
        appliedMigrationIds: document.appliedMigrationIds,
        updatedAt: assignedAt,
        legacyMovementMetadata: document.legacyMovementMetadata,
        legacyMovementMigrationMetadata:
            document.legacyMovementMigrationMetadata,
        legacyMigrationProblems: document.legacyMigrationProblems,
        assignmentAudits: <AssignmentAudit>[
          ...document.assignmentAudits,
          ...audits,
        ],
        legacyAccountingPolicy: document.legacyAccountingPolicy,
      ),
      changedIds: changed,
      unchangedIds: unchanged,
    );
  }

  void _validateCommand(
    AccountingDocument document,
    AccountingMovement movement,
    MovementAssignmentCommand command,
  ) {
    final valid = switch (command) {
      AssignDestinationWallet() =>
        movement.type == MovementType.buy ||
            (movement.type == MovementType.transferIn &&
                movement.destinationType == null),
      AssignSourceWallet() =>
        movement.type == MovementType.sell ||
            movement.type == MovementType.transferOut,
      AssignOwnTransferDestination() || ClassifyExternalTransferDestination() =>
        movement.type == MovementType.transferOut,
      AssignAdjustmentWallet() =>
        movement.type == MovementType.balanceAdjustment,
    };
    if (!valid) {
      throw ArgumentError('Asignación incompatible con ${movement.type.name}.');
    }
    final walletId = switch (command) {
      AssignSourceWallet(:final walletId) ||
      AssignDestinationWallet(:final walletId) ||
      AssignOwnTransferDestination(:final walletId) ||
      AssignAdjustmentWallet(:final walletId) => walletId,
      ClassifyExternalTransferDestination() => null,
    };
    if (walletId != null &&
        !document.wallets.any(
          (wallet) =>
              wallet.id == walletId &&
              wallet.status == WalletStatus.active &&
              !wallet.id.startsWith('virtual:'),
        )) {
      throw ArgumentError.value(
        walletId,
        'walletId',
        'La cartera debe ser real y activa.',
      );
    }
  }

  AccountingMovement _apply(
    AccountingMovement movement,
    MovementAssignmentCommand command,
  ) => switch (command) {
    AssignSourceWallet(:final walletId) => movement.copyWith(
      sourceWalletId: walletId,
    ),
    AssignDestinationWallet(:final walletId) => movement.copyWith(
      destinationWalletId: walletId,
    ),
    AssignOwnTransferDestination(:final walletId) => movement.copyWith(
      destinationWalletId: walletId,
      destinationType: DestinationType.ownWallet,
    ),
    ClassifyExternalTransferDestination() => movement.copyWith(
      destinationWalletId: null,
      destinationType: DestinationType.external,
    ),
    AssignAdjustmentWallet(:final walletId) => movement.copyWith(
      adjustmentWalletId: walletId,
    ),
  };

  WalletAssignmentStatus _status(AccountingMovement movement) =>
      switch (movement.type) {
        MovementType.buy =>
          movement.destinationWalletId == null
              ? WalletAssignmentStatus.legacyUnassigned
              : WalletAssignmentStatus.assigned,
        MovementType.sell =>
          movement.sourceWalletId == null
              ? WalletAssignmentStatus.legacyUnassigned
              : WalletAssignmentStatus.assigned,
        MovementType.transferIn =>
          movement.destinationWalletId == null
              ? WalletAssignmentStatus.legacyUnassigned
              : WalletAssignmentStatus.assigned,
        MovementType.balanceAdjustment =>
          movement.adjustmentWalletId == null
              ? WalletAssignmentStatus.legacyUnassigned
              : WalletAssignmentStatus.assigned,
        MovementType.transferOut =>
          movement.sourceWalletId == null && movement.destinationType == null
              ? WalletAssignmentStatus.legacyUnassigned
              : _hasCompleteTransferEndpoints(movement)
              ? WalletAssignmentStatus.assigned
              : WalletAssignmentStatus.partiallyAssigned,
      };

  bool _hasCompleteTransferEndpoints(AccountingMovement movement) =>
      movement.sourceWalletId != null &&
      switch (movement.destinationType) {
        DestinationType.ownWallet => movement.destinationWalletId != null,
        DestinationType.external => movement.destinationWalletId == null,
        null => false,
      };

  AssignmentStateSnapshot _snapshot(AccountingMovement movement) =>
      AssignmentStateSnapshot(
        sourceWalletId: movement.sourceWalletId,
        destinationWalletId: movement.destinationWalletId,
        adjustmentWalletId: movement.adjustmentWalletId,
        destinationType: movement.destinationType,
        status: movement.walletAssignmentStatus,
      );

  bool _sameTarget(
    AccountingMovement before,
    AccountingMovement after,
    WalletAssignmentTarget target,
  ) => switch (target) {
    WalletAssignmentTarget.source =>
      before.sourceWalletId == after.sourceWalletId,
    WalletAssignmentTarget.destination =>
      before.destinationWalletId == after.destinationWalletId &&
          before.destinationType == after.destinationType,
    WalletAssignmentTarget.adjustment =>
      before.adjustmentWalletId == after.adjustmentWalletId,
  };
}
