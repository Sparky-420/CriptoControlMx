import 'wallet.dart';

enum WalletAssignmentTarget { source, destination, adjustment }

final class AssignmentStateSnapshot {
  const AssignmentStateSnapshot({
    required this.sourceWalletId,
    required this.destinationWalletId,
    required this.adjustmentWalletId,
    required this.destinationType,
    required this.status,
  });

  final String? sourceWalletId;
  final String? destinationWalletId;
  final String? adjustmentWalletId;
  final DestinationType? destinationType;
  final WalletAssignmentStatus status;

  Map<String, Object?> toJson() => <String, Object?>{
    'sourceWalletId': sourceWalletId,
    'destinationWalletId': destinationWalletId,
    'adjustmentWalletId': adjustmentWalletId,
    'destinationType': destinationType?.name,
    'status': status.name,
  };

  factory AssignmentStateSnapshot.fromJson(Map<String, Object?> json) =>
      AssignmentStateSnapshot(
        sourceWalletId: json['sourceWalletId'] as String?,
        destinationWalletId: json['destinationWalletId'] as String?,
        adjustmentWalletId: json['adjustmentWalletId'] as String?,
        destinationType: json['destinationType'] == null
            ? null
            : DestinationType.values.byName(json['destinationType']! as String),
        status: WalletAssignmentStatus.values.byName(json['status']! as String),
      );
}

final class AssignmentAudit {
  const AssignmentAudit({
    required this.id,
    required this.operationId,
    required this.movementId,
    required this.changedTargets,
    required this.before,
    required this.after,
    required this.assignedAt,
  });

  final String id;
  final String operationId;
  final String movementId;
  final Set<WalletAssignmentTarget> changedTargets;
  final AssignmentStateSnapshot before;
  final AssignmentStateSnapshot after;
  final DateTime assignedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'operationId': operationId,
    'movementId': movementId,
    'changedTargets': changedTargets.map((target) => target.name).toList()
      ..sort(),
    'before': before.toJson(),
    'after': after.toJson(),
    'assignedAt': assignedAt.toIso8601String(),
  };

  factory AssignmentAudit.fromJson(Map<String, Object?> json) =>
      AssignmentAudit(
        id: json['id']! as String,
        operationId: json['operationId']! as String,
        movementId: json['movementId']! as String,
        changedTargets: (json['changedTargets']! as List)
            .cast<String>()
            .map(WalletAssignmentTarget.values.byName)
            .toSet(),
        before: AssignmentStateSnapshot.fromJson(
          Map<String, Object?>.from(json['before']! as Map),
        ),
        after: AssignmentStateSnapshot.fromJson(
          Map<String, Object?>.from(json['after']! as Map),
        ),
        assignedAt: DateTime.parse(json['assignedAt']! as String),
      );
}
