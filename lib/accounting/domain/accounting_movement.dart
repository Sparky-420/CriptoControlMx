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

  bool get isLegacyUnassigned =>
      walletAssignmentStatus == WalletAssignmentStatus.legacyUnassigned;

  AccountingMovement copyWith({
    String? id,
    MovementType? type,
    String? asset,
    DateTime? occurredAt,
    Object? quantity = unset,
    Object? unitPriceFiat = unset,
    AccountingAmount? fiatFeeAmount,
    Object? sourceWalletId = unset,
    Object? destinationWalletId = unset,
    Object? destinationType = unset,
    Object? externalRecipientName = unset,
    Object? externalDestinationPlatform = unset,
    WalletAssignmentStatus? walletAssignmentStatus,
    Object? receivedAmount = unset,
    AccountingAmount? cryptoFeeAmount,
    Object? cryptoFeeAsset = unset,
    Object? totalDebitedAmount = unset,
    Object? feeFiatValue = unset,
    FiatFeeTreatment? fiatFeeTreatment,
    Object? network = unset,
    Object? note = unset,
    Object? adjustmentWalletId = unset,
    Object? adjustmentQuantity = unset,
    Object? observedBalance = unset,
    Object? adjustmentReason = unset,
    List<ReconciliationLink>? reconciliationLinks,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? schemaVersion,
  }) => AccountingMovement(
    id: id ?? this.id,
    type: type ?? this.type,
    asset: asset ?? this.asset,
    occurredAt: occurredAt ?? this.occurredAt,
    fiatFeeAmount: fiatFeeAmount ?? this.fiatFeeAmount,
    walletAssignmentStatus:
        walletAssignmentStatus ?? this.walletAssignmentStatus,
    cryptoFeeAmount: cryptoFeeAmount ?? this.cryptoFeeAmount,
    fiatFeeTreatment: fiatFeeTreatment ?? this.fiatFeeTreatment,
    reconciliationLinks: reconciliationLinks ?? this.reconciliationLinks,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    quantity: identical(quantity, unset)
        ? this.quantity
        : quantity as AccountingAmount?,
    unitPriceFiat: identical(unitPriceFiat, unset)
        ? this.unitPriceFiat
        : unitPriceFiat as AccountingAmount?,
    sourceWalletId: identical(sourceWalletId, unset)
        ? this.sourceWalletId
        : sourceWalletId as String?,
    destinationWalletId: identical(destinationWalletId, unset)
        ? this.destinationWalletId
        : destinationWalletId as String?,
    destinationType: identical(destinationType, unset)
        ? this.destinationType
        : destinationType as DestinationType?,
    externalRecipientName: identical(externalRecipientName, unset)
        ? this.externalRecipientName
        : externalRecipientName as String?,
    externalDestinationPlatform: identical(externalDestinationPlatform, unset)
        ? this.externalDestinationPlatform
        : externalDestinationPlatform as String?,
    receivedAmount: identical(receivedAmount, unset)
        ? this.receivedAmount
        : receivedAmount as AccountingAmount?,
    cryptoFeeAsset: identical(cryptoFeeAsset, unset)
        ? this.cryptoFeeAsset
        : cryptoFeeAsset as String?,
    totalDebitedAmount: identical(totalDebitedAmount, unset)
        ? this.totalDebitedAmount
        : totalDebitedAmount as AccountingAmount?,
    feeFiatValue: identical(feeFiatValue, unset)
        ? this.feeFiatValue
        : feeFiatValue as AccountingAmount?,
    network: identical(network, unset) ? this.network : network as String?,
    note: identical(note, unset) ? this.note : note as String?,
    adjustmentWalletId: identical(adjustmentWalletId, unset)
        ? this.adjustmentWalletId
        : adjustmentWalletId as String?,
    adjustmentQuantity: identical(adjustmentQuantity, unset)
        ? this.adjustmentQuantity
        : adjustmentQuantity as AccountingAmount?,
    observedBalance: identical(observedBalance, unset)
        ? this.observedBalance
        : observedBalance as AccountingAmount?,
    adjustmentReason: identical(adjustmentReason, unset)
        ? this.adjustmentReason
        : adjustmentReason as String?,
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
