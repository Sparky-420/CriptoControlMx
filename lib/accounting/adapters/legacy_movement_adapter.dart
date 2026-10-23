import 'dart:convert';

import '../domain/accounting_amount.dart';
import '../domain/accounting_movement.dart';
import '../domain/movement_type.dart';
import '../domain/wallet.dart';

enum LegacyConversionIssueCode {
  missingMovementType,
  unknownMovementType,
  missingAsset,
  missingOccurredAt,
  invalidOccurredAt,
}

final class LegacyConversionIssue {
  const LegacyConversionIssue({
    required this.code,
    required this.message,
    this.rawValue,
  });

  final LegacyConversionIssueCode code;
  final String message;
  final Object? rawValue;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code.name,
    'message': message,
    'rawValue': rawValue,
  };

  factory LegacyConversionIssue.fromJson(Map<String, Object?> json) =>
      LegacyConversionIssue(
        code: LegacyConversionIssueCode.values.byName(json['code']! as String),
        message: json['message']! as String,
        rawValue: json['rawValue'],
      );
}

final class LegacyMovementConversion {
  const LegacyMovementConversion({
    required this.movementOrNull,
    required this.preservedFields,
    required this.issues,
  });

  final AccountingMovement? movementOrNull;
  final Map<String, Object?> preservedFields;
  final List<LegacyConversionIssue> issues;

  AccountingMovement get movement =>
      movementOrNull ??
      (throw StateError(
        'La conversión legada contiene incidencias y no produjo movimiento.',
      ));

  Map<String, Object?> toLegacyJson() =>
      Map<String, Object?>.from(preservedFields);
}

final class LegacyMovementAdapter {
  const LegacyMovementAdapter();

  LegacyMovementConversion fromLegacyJson(Map<String, Object?> value) {
    final preservedFields = Map<String, Object?>.unmodifiable(
      Map<String, Object?>.from(value),
    );
    final issues = <LegacyConversionIssue>[];
    final rawType = _read(value, const <String>['type', 'tipo']);
    final typeText = _nullableText(rawType);
    final parsedType = _movementType(rawType);
    if (typeText == null) {
      issues.add(
        LegacyConversionIssue(
          code: LegacyConversionIssueCode.missingMovementType,
          message: 'El tipo del movimiento legado es obligatorio.',
          rawValue: rawType,
        ),
      );
    } else if (parsedType == null) {
      issues.add(
        LegacyConversionIssue(
          code: LegacyConversionIssueCode.unknownMovementType,
          message: 'El tipo del movimiento legado no es reconocido.',
          rawValue: rawType,
        ),
      );
    }
    final rawAsset = _read(value, const <String>['asset', 'coin', 'crypto']);
    final parsedAsset = _nullableText(rawAsset)?.toUpperCase();
    if (parsedAsset == null) {
      issues.add(
        LegacyConversionIssue(
          code: LegacyConversionIssueCode.missingAsset,
          message: 'El activo del movimiento legado es obligatorio.',
          rawValue: rawAsset,
        ),
      );
    }
    final rawOccurredAt = _read(value, const <String>[
      'occurredAt',
      'occurred_at',
      'date',
    ]);
    final occurredAtText = _nullableText(rawOccurredAt);
    final parsedOccurredAt = occurredAtText == null
        ? null
        : DateTime.tryParse(occurredAtText);
    if (occurredAtText == null) {
      issues.add(
        LegacyConversionIssue(
          code: LegacyConversionIssueCode.missingOccurredAt,
          message: 'La fecha del movimiento legado es obligatoria.',
          rawValue: rawOccurredAt,
        ),
      );
    } else if (parsedOccurredAt == null) {
      issues.add(
        LegacyConversionIssue(
          code: LegacyConversionIssueCode.invalidOccurredAt,
          message: 'La fecha del movimiento legado no es válida.',
          rawValue: rawOccurredAt,
        ),
      );
    }
    if (issues.isNotEmpty) {
      return LegacyMovementConversion(
        movementOrNull: null,
        preservedFields: preservedFields,
        issues: List<LegacyConversionIssue>.unmodifiable(issues),
      );
    }

    final type = parsedType!;
    final asset = parsedAsset!;
    final occurredAt = parsedOccurredAt!;
    final createdAt = _date(
      _read(value, const <String>['createdAt', 'created_at']),
      fallback: occurredAt,
    );
    final updatedAt = _date(
      _read(value, const <String>['updatedAt', 'updated_at']),
      fallback: createdAt,
    );
    final receivedAmount = _amount(
      _read(value, const <String>['receivedAmount', 'received_amount']),
    );
    final quantity = type == MovementType.balanceAdjustment
        ? null
        : _amount(_read(value, const <String>['quantity', 'cryptoAmount'])) ??
              receivedAmount;
    final fiatFeeAmount =
        _amount(
          _read(value, const <String>[
            'fiatFeeAmount',
            'fiat_fee_amount',
            'fee',
            'commission',
          ]),
        ) ??
        AccountingAmount.zero;
    final cryptoFeeAmount =
        _amount(
          _read(value, const <String>['cryptoFeeAmount', 'crypto_fee_amount']),
        ) ??
        AccountingAmount.zero;
    final feeFiatValue = _amount(
      _read(value, const <String>['feeFiatValue', 'fee_fiat_value']),
    );
    final sourceWalletId = _nullableText(
      _read(value, const <String>['sourceWalletId', 'source_wallet_id']),
    );
    final destinationWalletId = _nullableText(
      _read(value, const <String>[
        'destinationWalletId',
        'destination_wallet_id',
      ]),
    );
    final explicitDestinationType = _enumByName<DestinationType>(
      _read(value, const <String>['destinationType', 'destination_type']),
      DestinationType.values,
    );
    final destinationType =
        explicitDestinationType ??
        (_wasHistoricallyOwnedTransfer(value, type)
            ? DestinationType.ownWallet
            : null);
    final adjustmentWalletId = _nullableText(
      _read(value, const <String>[
        'adjustmentWalletId',
        'adjustment_wallet_id',
      ]),
    );
    final explicitAssignment = _enumByName<WalletAssignmentStatus>(
      _read(value, const <String>[
        'walletAssignmentStatus',
        'wallet_assignment_status',
      ]),
      WalletAssignmentStatus.values,
    );
    final assignment =
        explicitAssignment ??
        (_hasConfirmedRoles(
              type,
              sourceWalletId,
              destinationWalletId,
              destinationType,
              adjustmentWalletId,
            )
            ? WalletAssignmentStatus.assigned
            : WalletAssignmentStatus.legacyUnassigned);
    final fiatTreatment =
        _enumByName<FiatFeeTreatment>(
          _read(value, const <String>[
            'fiatFeeTreatment',
            'fiat_fee_treatment',
          ]),
          FiatFeeTreatment.values,
        ) ??
        _legacyFiatTreatment(fiatFeeAmount, cryptoFeeAmount, feeFiatValue);
    final id =
        _nullableText(value['id']) ??
        _synthesizedLegacyId(value, occurredAt, type, asset);
    final movement = AccountingMovement(
      id: id,
      type: type,
      asset: asset,
      occurredAt: occurredAt,
      quantity: quantity,
      unitPriceFiat: _amount(
        _read(value, <String>[
          'unitPriceFiat',
          'unit_price_fiat',
          'unitPrice',
          'unit_price',
        ]),
      ),
      fiatFeeAmount: fiatFeeAmount,
      sourceWalletId: sourceWalletId,
      destinationWalletId: destinationWalletId,
      destinationType: destinationType,
      externalRecipientName: _nullableText(
        _read(value, const <String>[
          'externalRecipientName',
          'external_recipient_name',
        ]),
      ),
      externalDestinationPlatform: _nullableText(
        _read(value, const <String>[
          'externalDestinationPlatform',
          'external_destination_platform',
        ]),
      ),
      walletAssignmentStatus: assignment,
      receivedAmount: receivedAmount,
      cryptoFeeAmount: cryptoFeeAmount,
      cryptoFeeAsset: _nullableText(
        _read(value, const <String>['cryptoFeeAsset', 'crypto_fee_asset']),
      )?.toUpperCase(),
      totalDebitedAmount: _amount(
        _read(value, const <String>[
          'totalDebitedAmount',
          'total_debited_amount',
        ]),
      ),
      feeFiatValue: feeFiatValue,
      fiatFeeTreatment: fiatTreatment,
      network: _nullableText(_read(value, const <String>['network', 'red'])),
      note: _nullableText(value['note']),
      adjustmentWalletId: adjustmentWalletId,
      adjustmentQuantity: _amount(
        _read(value, <String>[
          'adjustmentQuantity',
          'adjustment_quantity',
          if (type == MovementType.balanceAdjustment) 'quantity',
        ]),
      ),
      observedBalance: _amount(
        _read(value, const <String>['observedBalance', 'observed_balance']),
      ),
      adjustmentReason: _nullableText(
        _read(value, const <String>['adjustmentReason', 'adjustment_reason']),
      ),
      reconciliationLinks: _reconciliationLinks(
        _read(value, const <String>[
          'reconciliationLinks',
          'reconciliation_links',
        ]),
      ),
      createdAt: createdAt,
      updatedAt: updatedAt,
      schemaVersion: _integer(value['schemaVersion']) ?? 1,
    );
    return LegacyMovementConversion(
      movementOrNull: movement,
      preservedFields: preservedFields,
      issues: const <LegacyConversionIssue>[],
    );
  }

  Map<String, Object?> toLegacyJson(
    AccountingMovement value, {
    Map<String, Object?> preservedFields = const <String, Object?>{},
  }) {
    final result = Map<String, Object?>.from(preservedFields);
    final addDefaults = preservedFields.isEmpty;
    _syncText(result, const <String>['id'], value.id, writeWhenAbsent: true);
    _syncEnum(
      result,
      const <String>['type', 'tipo'],
      value.type,
      _movementType,
      writeWhenAbsent: addDefaults,
    );
    _syncAsset(
      result,
      const <String>['coin', 'crypto', 'asset'],
      value.asset,
      writeWhenAbsent: addDefaults,
    );
    _syncDate(
      result,
      const <String>['date', 'occurredAt', 'occurred_at'],
      value.occurredAt,
      writeWhenAbsent: addDefaults,
    );
    _syncAmount(
      result,
      const <String>['quantity', 'cryptoAmount'],
      value.type == MovementType.balanceAdjustment ? null : value.quantity,
      writeWhenAbsent: addDefaults,
      defaultWhenNull: addDefaults ? AccountingAmount.zero : null,
    );
    _syncAmount(
      result,
      const <String>[
        'unitPrice',
        'unit_price',
        'unitPriceFiat',
        'unit_price_fiat',
      ],
      value.unitPriceFiat,
      writeWhenAbsent: addDefaults,
      defaultWhenNull: addDefaults ? AccountingAmount.zero : null,
    );
    _syncAmount(
      result,
      const <String>['fee', 'commission', 'fiatFeeAmount', 'fiat_fee_amount'],
      value.fiatFeeAmount,
      writeWhenAbsent: addDefaults,
    );
    _syncAmount(result, const <String>[
      'receivedAmount',
      'received_amount',
    ], value.receivedAmount);
    _syncAmount(
      result,
      const <String>['cryptoFeeAmount', 'crypto_fee_amount'],
      value.cryptoFeeAmount,
      writeWhenAbsent: value.cryptoFeeAmount != AccountingAmount.zero,
    );
    _syncText(result, const <String>[
      'cryptoFeeAsset',
      'crypto_fee_asset',
    ], value.cryptoFeeAsset);
    _syncAmount(result, const <String>[
      'totalDebitedAmount',
      'total_debited_amount',
    ], value.totalDebitedAmount);
    _syncAmount(result, const <String>[
      'feeFiatValue',
      'fee_fiat_value',
    ], value.feeFiatValue);
    _syncText(
      result,
      const <String>['network', 'red'],
      value.network,
      writeWhenAbsent: addDefaults && value.network != null,
    );
    _syncText(
      result,
      const <String>['note'],
      value.note,
      writeWhenAbsent: addDefaults && value.note != null,
    );
    _syncDate(
      result,
      const <String>['createdAt', 'created_at'],
      value.createdAt,
      writeWhenAbsent: addDefaults,
    );
    _syncDate(
      result,
      const <String>['updatedAt', 'updated_at'],
      value.updatedAt,
      writeWhenAbsent: addDefaults,
    );
    _syncInteger(
      result,
      const <String>['schemaVersion'],
      value.schemaVersion,
      writeWhenAbsent: addDefaults,
    );

    _syncText(
      result,
      const <String>['sourceWalletId', 'source_wallet_id'],
      value.sourceWalletId,
      writeWhenAbsent: addDefaults && value.sourceWalletId != null,
    );
    _syncText(
      result,
      const <String>['destinationWalletId', 'destination_wallet_id'],
      value.destinationWalletId,
      writeWhenAbsent: addDefaults && value.destinationWalletId != null,
    );
    _syncNamedEnum(
      result,
      const <String>['destinationType', 'destination_type'],
      value.destinationType,
      writeWhenAbsent: addDefaults && value.destinationType != null,
    );
    _syncText(
      result,
      const <String>['externalRecipientName', 'external_recipient_name'],
      value.externalRecipientName,
      writeWhenAbsent: addDefaults && value.externalRecipientName != null,
    );
    _syncText(
      result,
      const <String>[
        'externalDestinationPlatform',
        'external_destination_platform',
      ],
      value.externalDestinationPlatform,
      writeWhenAbsent: addDefaults && value.externalDestinationPlatform != null,
    );
    _syncNamedEnum(
      result,
      const <String>['walletAssignmentStatus', 'wallet_assignment_status'],
      value.walletAssignmentStatus,
      writeWhenAbsent:
          addDefaults &&
          value.walletAssignmentStatus !=
              WalletAssignmentStatus.legacyUnassigned,
    );
    _syncNamedEnum(
      result,
      const <String>['fiatFeeTreatment', 'fiat_fee_treatment'],
      value.fiatFeeTreatment,
      writeWhenAbsent:
          addDefaults && value.fiatFeeTreatment != FiatFeeTreatment.none,
    );
    _syncText(
      result,
      const <String>['adjustmentWalletId', 'adjustment_wallet_id'],
      value.adjustmentWalletId,
      writeWhenAbsent: addDefaults && value.adjustmentWalletId != null,
    );
    _syncAmount(
      result,
      const <String>['adjustmentQuantity', 'adjustment_quantity'],
      value.adjustmentQuantity,
      writeWhenAbsent: addDefaults && value.adjustmentQuantity != null,
    );
    _syncAmount(
      result,
      const <String>['observedBalance', 'observed_balance'],
      value.observedBalance,
      writeWhenAbsent: addDefaults && value.observedBalance != null,
    );
    _syncText(
      result,
      const <String>['adjustmentReason', 'adjustment_reason'],
      value.adjustmentReason,
      writeWhenAbsent: addDefaults && value.adjustmentReason != null,
    );
    _syncLinks(
      result,
      const <String>['reconciliationLinks', 'reconciliation_links'],
      value.reconciliationLinks,
      writeWhenAbsent: addDefaults && value.reconciliationLinks.isNotEmpty,
    );

    if (addDefaults) {
      result.putIfAbsent('source', () => '');
      result.putIfAbsent('wallet', () => '');
    }
    return result;
  }
}

Object? _read(Map<String, Object?> value, List<String> keys) {
  for (final key in keys) {
    if (value.containsKey(key)) return value[key];
  }
  return null;
}

String? _nullableText(Object? value) {
  final result = value?.toString().trim() ?? '';
  return result.isEmpty ? null : result;
}

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

AccountingAmount? _amount(Object? value) {
  if (value == null) return null;
  if (value is int) return AccountingAmount.fromInt(value);
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  try {
    return AccountingAmount.parse(text);
  } on FormatException {
    final parsed = double.tryParse(text);
    if (parsed == null || !parsed.isFinite) return null;
    var expanded = parsed.toStringAsFixed(18);
    expanded = expanded.replaceFirst(RegExp(r'0+$'), '');
    expanded = expanded.replaceFirst(RegExp(r'\.$'), '');
    return AccountingAmount.parse(expanded);
  }
}

DateTime _date(Object? value, {required DateTime fallback}) =>
    DateTime.tryParse(value?.toString() ?? '') ?? fallback;

T? _enumByName<T extends Enum>(Object? value, List<T> values) {
  final raw = value?.toString().trim().toLowerCase();
  if (raw == null || raw.isEmpty) return null;
  for (final item in values) {
    if (item.name.toLowerCase() == raw) return item;
  }
  return null;
}

MovementType? _movementType(Object? value) {
  final raw = value?.toString().trim().toLowerCase() ?? '';
  if (const <String>{'buy', 'compra', 'comprar'}.contains(raw)) {
    return MovementType.buy;
  }
  if (const <String>{'sell', 'venta', 'vender'}.contains(raw)) {
    return MovementType.sell;
  }
  if (const <String>{
    'transferin',
    'transfer_in',
    'transferenciaentrada',
    'transferencia_entrada',
    'transferencia recibida',
    'recibida',
    'entrada',
  }.contains(raw)) {
    return MovementType.transferIn;
  }
  if (const <String>{
    'transferout',
    'transfer_out',
    'transferenciasalida',
    'transferencia_salida',
    'transferencia enviada',
    'enviada',
    'salida',
  }.contains(raw)) {
    return MovementType.transferOut;
  }
  if (const <String>{
    'balanceadjustment',
    'balance_adjustment',
    'ajuste',
    'ajuste de saldo',
  }.contains(raw)) {
    return MovementType.balanceAdjustment;
  }
  return null;
}

bool _hasConfirmedRoles(
  MovementType type,
  String? sourceWalletId,
  String? destinationWalletId,
  DestinationType? destinationType,
  String? adjustmentWalletId,
) => switch (type) {
  MovementType.buy || MovementType.transferIn => destinationWalletId != null,
  MovementType.sell => sourceWalletId != null,
  MovementType.transferOut =>
    sourceWalletId != null &&
        ((destinationType == DestinationType.external &&
                destinationWalletId == null) ||
            (destinationType == DestinationType.ownWallet &&
                destinationWalletId != null)),
  MovementType.balanceAdjustment => adjustmentWalletId != null,
};

FiatFeeTreatment _legacyFiatTreatment(
  AccountingAmount fiatFee,
  AccountingAmount cryptoFee,
  AccountingAmount? fiatValue,
) {
  final hasFiat = fiatFee.compareTo(AccountingAmount.zero) > 0;
  final hasCrypto = cryptoFee.compareTo(AccountingAmount.zero) > 0;
  if (hasFiat && hasCrypto) return FiatFeeTreatment.combined;
  if (hasFiat) return FiatFeeTreatment.paidSeparately;
  if (hasCrypto && fiatValue != null) {
    return FiatFeeTreatment.valuationOfCryptoFee;
  }
  return FiatFeeTreatment.none;
}

List<ReconciliationLink> _reconciliationLinks(Object? value) {
  if (value is! List) return const <ReconciliationLink>[];
  final result = <ReconciliationLink>[];
  for (final item in value) {
    if (item is! Map) continue;
    final map = Map<String, Object?>.from(item);
    final adjustmentMovementId = _nullableText(
      _read(map, const <String>[
        'adjustmentMovementId',
        'adjustment_movement_id',
      ]),
    );
    final quantityResolved = _amount(
      _read(map, const <String>['quantityResolved', 'quantity_resolved']),
    );
    if (adjustmentMovementId == null || quantityResolved == null) continue;
    result.add(
      ReconciliationLink(
        adjustmentMovementId: adjustmentMovementId,
        quantityResolved: quantityResolved,
      ),
    );
  }
  return List<ReconciliationLink>.unmodifiable(result);
}

bool _wasHistoricallyOwnedTransfer(
  Map<String, Object?> value,
  MovementType type,
) {
  final hasStructuredValue =
      _amount(
            _read(value, const <String>['receivedAmount', 'received_amount']),
          ) !=
          null ||
      _amount(
            _read(value, const <String>[
              'cryptoFeeAmount',
              'crypto_fee_amount',
            ]),
          ) !=
          null ||
      _amount(
            _read(value, const <String>[
              'totalDebitedAmount',
              'total_debited_amount',
            ]),
          ) !=
          null;
  if (type != MovementType.transferOut || !hasStructuredValue) {
    return false;
  }
  final source = _firstNonEmptyText(value, const <String>[
    'sourcePlatform',
    'source_platform',
    'source',
    'origin',
    'origen',
  ]);
  final destination = _firstNonEmptyText(value, const <String>[
    'destinationPlatform',
    'destination_platform',
    'wallet',
    'cartera',
  ]);
  return source != null && destination != null;
}

String? _firstNonEmptyText(Map<String, Object?> value, List<String> keys) {
  for (final key in keys) {
    final candidate = _nullableText(value[key]);
    if (candidate != null) return candidate;
  }
  return null;
}

String _synthesizedLegacyId(
  Map<String, Object?> value,
  DateTime occurredAt,
  MovementType type,
  String asset,
) {
  final canonical = jsonEncode(_canonicalJson(value));
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final byte in utf8.encode(canonical)) {
    hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
  }
  return 'legacy-${occurredAt.microsecondsSinceEpoch}-${type.name}-$asset-${hash.toRadixString(16).padLeft(16, '0')}';
}

Object? _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJson(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalJson).toList();
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  return value.toString();
}

void _syncText(
  Map<String, Object?> target,
  List<String> keys,
  String? value, {
  bool writeWhenAbsent = false,
}) {
  final present = keys.where(target.containsKey).toList();
  if (value == null) {
    for (final key in keys) {
      target.remove(key);
    }
    return;
  }
  if (present.isEmpty) {
    if (writeWhenAbsent) target[keys.first] = value;
    return;
  }
  for (final key in present) {
    if (target[key]?.toString() != value) target[key] = value;
  }
}

void _syncAsset(
  Map<String, Object?> target,
  List<String> keys,
  String value, {
  required bool writeWhenAbsent,
}) {
  final present = keys.where(target.containsKey).toList();
  if (present.isEmpty) {
    if (writeWhenAbsent) target[keys.first] = value;
    return;
  }
  for (final key in present) {
    if (target[key]?.toString().toUpperCase() != value.toUpperCase()) {
      target[key] = value;
    }
  }
}

void _syncEnum<T extends Enum>(
  Map<String, Object?> target,
  List<String> keys,
  T value,
  T? Function(Object?) parser, {
  required bool writeWhenAbsent,
}) {
  final present = keys.where(target.containsKey).toList();
  if (present.isEmpty) {
    if (writeWhenAbsent) target[keys.first] = value.name;
    return;
  }
  for (final key in present) {
    if (parser(target[key]) != value) target[key] = value.name;
  }
}

void _syncNamedEnum<T extends Enum>(
  Map<String, Object?> target,
  List<String> keys,
  T? value, {
  required bool writeWhenAbsent,
}) {
  if (value == null) {
    for (final key in keys) {
      target.remove(key);
    }
    return;
  }
  final present = keys.where(target.containsKey).toList();
  if (present.isEmpty) {
    if (writeWhenAbsent) target[keys.first] = value.name;
    return;
  }
  for (final key in present) {
    if (target[key]?.toString() != value.name) target[key] = value.name;
  }
}

void _syncDate(
  Map<String, Object?> target,
  List<String> keys,
  DateTime value, {
  required bool writeWhenAbsent,
}) {
  final present = keys.where(target.containsKey).toList();
  if (present.isEmpty) {
    if (writeWhenAbsent) target[keys.first] = value.toIso8601String();
    return;
  }
  for (final key in present) {
    if (DateTime.tryParse(target[key]?.toString() ?? '') != value) {
      target[key] = value.toIso8601String();
    }
  }
}

void _syncAmount(
  Map<String, Object?> target,
  List<String> keys,
  AccountingAmount? value, {
  bool writeWhenAbsent = false,
  AccountingAmount? defaultWhenNull,
}) {
  final effective = value ?? defaultWhenNull;
  if (effective == null) {
    for (final key in keys) {
      target.remove(key);
    }
    return;
  }
  final present = keys.where(target.containsKey).toList();
  if (present.isEmpty) {
    if (writeWhenAbsent) target[keys.first] = double.parse(effective.toJson());
    return;
  }
  for (final key in present) {
    final original = target[key];
    if (_amount(original) == effective) continue;
    target[key] = original is String
        ? effective.toJson()
        : double.parse(effective.toJson());
  }
}

void _syncInteger(
  Map<String, Object?> target,
  List<String> keys,
  int value, {
  required bool writeWhenAbsent,
}) {
  final present = keys.where(target.containsKey).toList();
  if (present.isEmpty) {
    if (writeWhenAbsent) target[keys.first] = value;
    return;
  }
  for (final key in present) {
    if (_integer(target[key]) != value) target[key] = value;
  }
}

void _syncLinks(
  Map<String, Object?> target,
  List<String> keys,
  List<ReconciliationLink> links, {
  required bool writeWhenAbsent,
}) {
  final present = keys.where(target.containsKey).toList();
  if (links.isEmpty && present.isEmpty) return;
  final encoded = links.map((link) => link.toJson()).toList();
  if (present.isEmpty) {
    if (writeWhenAbsent) target[keys.first] = encoded;
    return;
  }
  for (final key in present) {
    if (_sameLinks(_reconciliationLinks(target[key]), links)) continue;
    target[key] = encoded;
  }
}

bool _sameLinks(List<ReconciliationLink> left, List<ReconciliationLink> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index].adjustmentMovementId != right[index].adjustmentMovementId ||
        left[index].quantityResolved != right[index].quantityResolved) {
      return false;
    }
  }
  return true;
}
