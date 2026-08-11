import '../domain/accounting_amount.dart';
import '../domain/accounting_movement.dart';
import '../domain/movement_type.dart';
import '../domain/wallet.dart';

final class LegacyMovementConversion {
  const LegacyMovementConversion(this.movement, this.preservedFields);

  final AccountingMovement movement;
  final Map<String, Object?> preservedFields;
}

final class LegacyMovementAdapter {
  const LegacyMovementAdapter();

  LegacyMovementConversion fromLegacyJson(Map<String, Object?> value) {
    final type = _movementType(_read(value, const <String>['type', 'tipo']));
    final asset = _text(
      _read(value, const <String>['asset', 'coin', 'crypto']),
      fallback: 'BTC',
    ).toUpperCase();
    final occurredAt = _date(
      _read(value, const <String>['occurredAt', 'occurred_at', 'date']),
      fallback: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
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
    final destinationType = _enumByName<DestinationType>(
      _read(value, const <String>['destinationType', 'destination_type']),
      DestinationType.values,
    );
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
        'legacy-${occurredAt.microsecondsSinceEpoch}-${type.name}-$asset';
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
      movement,
      Map<String, Object?>.unmodifiable(Map<String, Object?>.from(value)),
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

String _text(Object? value, {required String fallback}) {
  final result = value?.toString().trim() ?? '';
  return result.isEmpty ? fallback : result;
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

MovementType _movementType(Object? value) {
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
  return MovementType.buy;
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
  return <ReconciliationLink>[
    for (final item in value)
      if (item is Map)
        ReconciliationLink.fromJson(Map<String, Object?>.from(item)),
  ];
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
  T Function(Object?) parser, {
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
    target[key] = encoded;
  }
}
