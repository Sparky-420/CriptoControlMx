import 'accounting_amount.dart';
import 'movement_type.dart';
import 'wallet.dart';

final class ReconciliationLink {
  const ReconciliationLink({
    required this.adjustmentMovementId,
    required this.quantityResolved,
  });
  final String adjustmentMovementId;
  final AccountingAmount quantityResolved;
  Map<String, Object?> toJson() => {
    'adjustmentMovementId': adjustmentMovementId,
    'quantityResolved': quantityResolved.toJson(),
  };
  factory ReconciliationLink.fromJson(Map<String, Object?> j) =>
      ReconciliationLink(
        adjustmentMovementId: j['adjustmentMovementId']! as String,
        quantityResolved: AccountingAmount.parse(
          j['quantityResolved']! as String,
        ),
      );
}

final class _Unset {
  const _Unset();
}

const Object unset = _Unset();

final class AccountingMovement {
  const AccountingMovement({
    required this.id,
    required this.type,
    required this.asset,
    required this.occurredAt,
    required this.fiatFeeAmount,
    required this.walletAssignmentStatus,
    required this.cryptoFeeAmount,
    required this.fiatFeeTreatment,
    required this.reconciliationLinks,
    required this.createdAt,
    required this.updatedAt,
    this.schemaVersion = 3,
    this.quantity,
    this.unitPriceFiat,
    this.sourceWalletId,
    this.destinationWalletId,
    this.destinationType,
    this.externalRecipientName,
    this.externalDestinationPlatform,
    this.receivedAmount,
    this.cryptoFeeAsset,
    this.totalDebitedAmount,
    this.feeFiatValue,
    this.network,
    this.note,
    this.adjustmentWalletId,
    this.adjustmentQuantity,
    this.observedBalance,
    this.adjustmentReason,
  });
  final String id;
  final MovementType type;
  final String asset;
  final DateTime occurredAt;
  final AccountingAmount? quantity;
  final AccountingAmount? unitPriceFiat;
  final AccountingAmount fiatFeeAmount;
  final String? sourceWalletId;
  final String? destinationWalletId;
  final DestinationType? destinationType;
  final String? externalRecipientName;
  final String? externalDestinationPlatform;
  final WalletAssignmentStatus walletAssignmentStatus;
  final AccountingAmount? receivedAmount;
  final AccountingAmount cryptoFeeAmount;
  final String? cryptoFeeAsset;
  final AccountingAmount? totalDebitedAmount;
  final AccountingAmount? feeFiatValue;
  final FiatFeeTreatment fiatFeeTreatment;
  final String? network;
  final String? note;
  final String? adjustmentWalletId;
  final AccountingAmount? adjustmentQuantity;
  final AccountingAmount? observedBalance;
  final String? adjustmentReason;
  final List<ReconciliationLink> reconciliationLinks;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int schemaVersion;
  AccountingMovement copyWith({Object? sourceWalletId = unset}) =>
      AccountingMovement(
        id: id,
        type: type,
        asset: asset,
        occurredAt: occurredAt,
        fiatFeeAmount: fiatFeeAmount,
        walletAssignmentStatus: walletAssignmentStatus,
        cryptoFeeAmount: cryptoFeeAmount,
        fiatFeeTreatment: fiatFeeTreatment,
        reconciliationLinks: reconciliationLinks,
        createdAt: createdAt,
        updatedAt: updatedAt,
        schemaVersion: schemaVersion,
        quantity: quantity,
        unitPriceFiat: unitPriceFiat,
        sourceWalletId: identical(sourceWalletId, unset)
            ? this.sourceWalletId
            : sourceWalletId as String?,
        destinationWalletId: destinationWalletId,
        destinationType: destinationType,
        externalRecipientName: externalRecipientName,
        externalDestinationPlatform: externalDestinationPlatform,
        receivedAmount: receivedAmount,
        cryptoFeeAsset: cryptoFeeAsset,
        totalDebitedAmount: totalDebitedAmount,
        feeFiatValue: feeFiatValue,
        network: network,
        note: note,
        adjustmentWalletId: adjustmentWalletId,
        adjustmentQuantity: adjustmentQuantity,
        observedBalance: observedBalance,
        adjustmentReason: adjustmentReason,
      );
  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'asset': asset,
    'occurredAt': occurredAt.toIso8601String(),
    'quantity': quantity?.toJson(),
    'unitPriceFiat': unitPriceFiat?.toJson(),
    'fiatFeeAmount': fiatFeeAmount.toJson(),
    'sourceWalletId': sourceWalletId,
    'destinationWalletId': destinationWalletId,
    'destinationType': destinationType?.name,
    'externalRecipientName': externalRecipientName,
    'externalDestinationPlatform': externalDestinationPlatform,
    'walletAssignmentStatus': walletAssignmentStatus.name,
    'receivedAmount': receivedAmount?.toJson(),
    'cryptoFeeAmount': cryptoFeeAmount.toJson(),
    'cryptoFeeAsset': cryptoFeeAsset,
    'totalDebitedAmount': totalDebitedAmount?.toJson(),
    'feeFiatValue': feeFiatValue?.toJson(),
    'fiatFeeTreatment': fiatFeeTreatment.name,
    'network': network,
    'note': note,
    'adjustmentWalletId': adjustmentWalletId,
    'adjustmentQuantity': adjustmentQuantity?.toJson(),
    'observedBalance': observedBalance?.toJson(),
    'adjustmentReason': adjustmentReason,
    'reconciliationLinks': reconciliationLinks.map((e) => e.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'schemaVersion': schemaVersion,
  };
  factory AccountingMovement.fromJson(Map<String, Object?> j) {
    AccountingAmount? a(String k) =>
        j[k] == null ? null : AccountingAmount.parse(j[k]! as String);
    return AccountingMovement(
      id: j['id']! as String,
      type: MovementType.values.byName(j['type']! as String),
      asset: j['asset']! as String,
      occurredAt: DateTime.parse(j['occurredAt']! as String),
      quantity: a('quantity'),
      unitPriceFiat: a('unitPriceFiat'),
      fiatFeeAmount: a('fiatFeeAmount')!,
      sourceWalletId: j['sourceWalletId'] as String?,
      destinationWalletId: j['destinationWalletId'] as String?,
      destinationType: j['destinationType'] == null
          ? null
          : DestinationType.values.byName(j['destinationType']! as String),
      externalRecipientName: j['externalRecipientName'] as String?,
      externalDestinationPlatform: j['externalDestinationPlatform'] as String?,
      walletAssignmentStatus: WalletAssignmentStatus.values.byName(
        j['walletAssignmentStatus']! as String,
      ),
      receivedAmount: a('receivedAmount'),
      cryptoFeeAmount: a('cryptoFeeAmount')!,
      cryptoFeeAsset: j['cryptoFeeAsset'] as String?,
      totalDebitedAmount: a('totalDebitedAmount'),
      feeFiatValue: a('feeFiatValue'),
      fiatFeeTreatment: FiatFeeTreatment.values.byName(
        j['fiatFeeTreatment']! as String,
      ),
      network: j['network'] as String?,
      note: j['note'] as String?,
      adjustmentWalletId: j['adjustmentWalletId'] as String?,
      adjustmentQuantity: a('adjustmentQuantity'),
      observedBalance: a('observedBalance'),
      adjustmentReason: j['adjustmentReason'] as String?,
      reconciliationLinks: (j['reconciliationLinks']! as List)
          .map(
            (e) => ReconciliationLink.fromJson(
              Map<String, Object?>.from(e as Map),
            ),
          )
          .toList(),
      createdAt: DateTime.parse(j['createdAt']! as String),
      updatedAt: DateTime.parse(j['updatedAt']! as String),
      schemaVersion: j['schemaVersion']! as int,
    );
  }
}
