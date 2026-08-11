enum WalletStatus { active, archived }

enum DestinationType { ownWallet, external }

enum WalletAssignmentStatus {
  assigned,
  partiallyAssigned,
  pending,
  legacyUnassigned,
}

enum AccountingCompleteness {
  complete,
  partiallyKnown,
  pendingAssignment,
  unassignedLegacy,
}

enum FiatFeeTreatment { none, valuationOfCryptoFee, paidSeparately, combined }

enum SaleCostConsumptionPolicy { knownFirst }

enum TransferCostAllocationPolicy { proportional }

enum LegacyAccountingPolicy { preservePreviousGlobal }

final class WalletImageRef {
  const WalletImageRef({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.sha256,
    required this.width,
    required this.height,
    required this.byteLength,
  });
  final String id;
  final String fileName;
  final String mimeType;
  final String sha256;
  final int width;
  final int height;
  final int byteLength;
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'fileName': fileName,
    'mimeType': mimeType,
    'sha256': sha256,
    'width': width,
    'height': height,
    'byteLength': byteLength,
  };
  factory WalletImageRef.fromJson(Map<String, Object?> json) => WalletImageRef(
    id: json['id']! as String,
    fileName: json['fileName']! as String,
    mimeType: json['mimeType']! as String,
    sha256: json['sha256']! as String,
    width: json['width']! as int,
    height: json['height']! as int,
    byteLength: json['byteLength']! as int,
  );
}

final class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    required this.provider,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.imageRef,
    this.colorArgb,
    this.note,
    this.schemaVersion = 1,
  });
  final String id;
  final String name;
  final String provider;
  final WalletImageRef? imageRef;
  final int? colorArgb;
  final String? note;
  final WalletStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int schemaVersion;
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'provider': provider,
    'imageRef': imageRef?.toJson(),
    'colorArgb': colorArgb,
    'note': note,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'schemaVersion': schemaVersion,
  };
  factory Wallet.fromJson(Map<String, Object?> json) => Wallet(
    id: json['id']! as String,
    name: json['name']! as String,
    provider: json['provider']! as String,
    imageRef: json['imageRef'] == null
        ? null
        : WalletImageRef.fromJson(
            Map<String, Object?>.from(json['imageRef']! as Map),
          ),
    colorArgb: json['colorArgb'] as int?,
    note: json['note'] as String?,
    status: WalletStatus.values.byName(json['status']! as String),
    createdAt: DateTime.parse(json['createdAt']! as String),
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    schemaVersion: json['schemaVersion']! as int,
  );
}
