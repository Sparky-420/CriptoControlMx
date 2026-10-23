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

  factory WalletImageRef.create({
    required String id,
    required String fileName,
    required String mimeType,
    required String sha256,
    required int width,
    required int height,
    required int byteLength,
  }) {
    final normalizedId = id.trim();
    final normalizedFileName = fileName.trim();
    final normalizedMimeType = mimeType.trim().toLowerCase();
    final normalizedSha256 = sha256.trim().toLowerCase();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Debe ser obligatorio y estable.');
    }
    if (!_isSafeFileName(normalizedFileName)) {
      throw ArgumentError.value(
        fileName,
        'fileName',
        'Debe ser un nombre relativo seguro, no una ruta.',
      );
    }
    if (normalizedMimeType != 'image/jpeg' &&
        normalizedMimeType != 'image/png') {
      throw ArgumentError.value(
        mimeType,
        'mimeType',
        'Sólo se admite image/jpeg o image/png.',
      );
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedSha256)) {
      throw ArgumentError.value(
        sha256,
        'sha256',
        'Debe ser un hash SHA-256 hexadecimal.',
      );
    }
    if (width <= 0 || height <= 0 || byteLength <= 0) {
      throw ArgumentError(
        'width, height y byteLength deben ser mayores que cero.',
      );
    }
    return WalletImageRef(
      id: normalizedId,
      fileName: normalizedFileName,
      mimeType: normalizedMimeType,
      sha256: normalizedSha256,
      width: width,
      height: height,
      byteLength: byteLength,
    );
  }

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
  factory WalletImageRef.fromJson(Map<String, Object?> json) =>
      WalletImageRef.create(
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

  factory Wallet.create({
    required String id,
    required String name,
    required String provider,
    required DateTime createdAt,
    WalletImageRef? imageRef,
    int? colorArgb,
    String? note,
  }) {
    final normalizedId = id.trim();
    final normalizedName = name.trim();
    final normalizedProvider = provider.trim();
    final normalizedNote = _nonEmptyOrNull(note);
    if (!_isUuid(normalizedId)) {
      throw ArgumentError.value(id, 'id', 'Debe ser un UUID válido.');
    }
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'No puede estar vacío.');
    }
    if (normalizedProvider.isEmpty) {
      throw ArgumentError.value(provider, 'provider', 'No puede estar vacío.');
    }
    return Wallet(
      id: normalizedId,
      name: normalizedName,
      provider: normalizedProvider,
      imageRef: imageRef,
      colorArgb: colorArgb,
      note: normalizedNote,
      status: WalletStatus.active,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

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

bool _isUuid(String value) => RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
).hasMatch(value);

bool _isSafeFileName(String value) =>
    value.isNotEmpty &&
    value != '.' &&
    value != '..' &&
    !value.contains('/') &&
    !value.contains(r'\') &&
    !value.contains(':');

String? _nonEmptyOrNull(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
