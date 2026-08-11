import 'accounting_amount.dart';
import 'accounting_movement.dart';
import 'ledger_validation.dart';
import 'movement_type.dart';
import 'wallet.dart';

abstract interface class MovementNormalizer {
  NormalizedLedger normalize(List<AccountingMovement> movements);
}

final class MovementCreationValidator {
  const MovementCreationValidator({
    this.normalizer = const DefaultMovementNormalizer(),
  });

  final MovementNormalizer normalizer;

  List<ProjectionIssue> validate(
    AccountingMovement movement, {
    required Iterable<Wallet> wallets,
  }) => _validate(
    movement,
    wallets: wallets,
    requireActiveWallet: true,
    requireAssignment: true,
  );

  List<ProjectionIssue> validateHistoricalReplay(
    AccountingMovement movement, {
    required Iterable<Wallet> wallets,
  }) => _validate(
    movement,
    wallets: wallets,
    requireActiveWallet: false,
    requireAssignment: false,
  );

  List<ProjectionIssue> _validate(
    AccountingMovement movement, {
    required Iterable<Wallet> wallets,
    required bool requireActiveWallet,
    required bool requireAssignment,
  }) {
    final issues = <ProjectionIssue>[
      ...normalizer.normalize(<AccountingMovement>[movement]).issues,
    ];
    if (requireAssignment &&
        movement.walletAssignmentStatus != WalletAssignmentStatus.assigned) {
      issues.add(
        ProjectionIssue(
          ProjectionIssueCode.missingWalletAssignment,
          movement.id,
          'Un movimiento nuevo requiere asignación completa de carteras.',
        ),
      );
    }

    final walletsById = <String, Wallet>{
      for (final wallet in wallets) wallet.id: wallet,
    };
    for (final walletId in _referencedWalletIds(movement)) {
      final wallet = walletsById[walletId];
      if (wallet == null) {
        issues.add(
          ProjectionIssue(
            ProjectionIssueCode.unknownWallet,
            movement.id,
            'La cartera $walletId no existe.',
          ),
        );
      } else if (requireActiveWallet && wallet.status != WalletStatus.active) {
        issues.add(
          ProjectionIssue(
            ProjectionIssueCode.inactiveWallet,
            movement.id,
            'La cartera $walletId está archivada.',
          ),
        );
      }
    }
    return List<ProjectionIssue>.unmodifiable(issues);
  }

  Set<String> _referencedWalletIds(AccountingMovement movement) =>
      switch (movement.type) {
        MovementType.buy || MovementType.transferIn => {
          if (movement.destinationWalletId != null)
            movement.destinationWalletId!,
        },
        MovementType.sell => {
          if (movement.sourceWalletId != null) movement.sourceWalletId!,
        },
        MovementType.transferOut => {
          if (movement.sourceWalletId != null) movement.sourceWalletId!,
          if (movement.destinationType == DestinationType.ownWallet &&
              movement.destinationWalletId != null)
            movement.destinationWalletId!,
        },
        MovementType.balanceAdjustment => {
          if (movement.adjustmentWalletId != null) movement.adjustmentWalletId!,
        },
      };
}

final class DefaultMovementNormalizer implements MovementNormalizer {
  const DefaultMovementNormalizer();

  @override
  NormalizedLedger normalize(List<AccountingMovement> movements) {
    final ordered = List<AccountingMovement>.of(movements)
      ..sort((left, right) {
        final byInstant = left.occurredAt.toUtc().compareTo(
          right.occurredAt.toUtc(),
        );
        return byInstant != 0 ? byInstant : left.id.compareTo(right.id);
      });
    final legs = <LedgerLeg>[];
    final issues = <ProjectionIssue>[];
    final seenIds = <String>{};
    final acceptedMovementIds = <String>{};

    for (final movement in ordered) {
      if (!seenIds.add(movement.id)) {
        issues.add(
          _issue(
            ProjectionIssueCode.duplicateMovementId,
            movement,
            'El ID del movimiento está duplicado.',
          ),
        );
        continue;
      }
      final issue = _validate(movement);
      if (issue != null) {
        issues.add(issue);
        continue;
      }
      acceptedMovementIds.add(movement.id);
      legs.addAll(_legsFor(movement));
    }

    return NormalizedLedger(
      movements: List<AccountingMovement>.unmodifiable(ordered),
      legs: List<LedgerLeg>.unmodifiable(legs),
      issues: List<ProjectionIssue>.unmodifiable(issues),
      acceptedMovementIds: Set<String>.unmodifiable(acceptedMovementIds),
    );
  }

  ProjectionIssue? _validate(AccountingMovement movement) {
    if (movement.asset.trim().isEmpty ||
        movement.cryptoFeeAmount.compareTo(AccountingAmount.zero) < 0) {
      return _issue(
        ProjectionIssueCode.invalidAmount,
        movement,
        'El activo y los importes deben ser válidos.',
      );
    }
    switch (movement.type) {
      case MovementType.buy:
        return _validateBuy(movement);
      case MovementType.sell:
        return _validateSell(movement);
      case MovementType.transferIn:
        return _validateTransferIn(movement);
      case MovementType.transferOut:
        return _validateTransferOut(movement);
      case MovementType.balanceAdjustment:
        return _validateAdjustment(movement);
    }
  }

  ProjectionIssue? _validateBuy(AccountingMovement movement) {
    if (_missing(movement.destinationWalletId)) {
      return _issue(
        ProjectionIssueCode.missingDestinationWallet,
        movement,
        'Una compra requiere cartera destino.',
      );
    }
    if (!_missing(movement.sourceWalletId) ||
        movement.destinationType != null ||
        !_missing(movement.externalRecipientName) ||
        !_missing(movement.externalDestinationPlatform)) {
      return _malformed(
        movement,
        'Una compra sólo puede tener cartera destino.',
      );
    }
    return _positive(
      movement,
      movement.quantity,
      'Una compra requiere cantidad positiva.',
    );
  }

  ProjectionIssue? _validateSell(AccountingMovement movement) {
    if (_missing(movement.sourceWalletId)) {
      return _issue(
        ProjectionIssueCode.missingSourceWallet,
        movement,
        'Una venta requiere cartera origen.',
      );
    }
    if (!_missing(movement.destinationWalletId) ||
        movement.destinationType != null ||
        !_missing(movement.externalRecipientName) ||
        !_missing(movement.externalDestinationPlatform)) {
      return _malformed(movement, 'Una venta sólo puede tener cartera origen.');
    }
    return _positive(
      movement,
      movement.quantity,
      'Una venta requiere cantidad positiva.',
    );
  }

  ProjectionIssue? _validateTransferIn(AccountingMovement movement) {
    if (!movement.isLegacyUnassigned &&
        _missing(movement.destinationWalletId)) {
      return _issue(
        ProjectionIssueCode.missingDestinationWallet,
        movement,
        'Una entrada externa asignada requiere cartera destino.',
      );
    }
    if (!_missing(movement.sourceWalletId) ||
        movement.destinationType != null ||
        !_missing(movement.externalRecipientName) ||
        !_missing(movement.externalDestinationPlatform)) {
      return _malformed(
        movement,
        'Una entrada externa no puede tener origen ni tipo de destino.',
      );
    }
    return _positive(
      movement,
      movement.quantity,
      'Una entrada externa requiere cantidad positiva.',
    );
  }

  ProjectionIssue? _validateTransferOut(AccountingMovement movement) {
    if (_missing(movement.sourceWalletId)) {
      return _issue(
        ProjectionIssueCode.missingSourceWallet,
        movement,
        'Una transferencia requiere cartera origen.',
      );
    }
    final receivedIssue = _positive(
      movement,
      movement.receivedAmount,
      'Una transferencia requiere cantidad recibida positiva.',
    );
    if (receivedIssue != null) {
      return receivedIssue;
    }
    if (movement.quantity != null &&
        movement.quantity != movement.receivedAmount) {
      return _issue(
        ProjectionIssueCode.inconsistentTransferAmounts,
        movement,
        'La cantidad histórica y la recibida no coinciden.',
      );
    }
    switch (movement.destinationType) {
      case DestinationType.ownWallet:
        return _validateOwnWalletTransfer(movement);
      case DestinationType.external:
        return _validateExternalTransfer(movement);
      case null:
        return _malformed(
          movement,
          'Una transferencia requiere tipo de destino.',
        );
    }
  }

  ProjectionIssue? _validateOwnWalletTransfer(AccountingMovement movement) {
    if (_missing(movement.destinationWalletId)) {
      return _issue(
        ProjectionIssueCode.missingDestinationWallet,
        movement,
        'Una transferencia interna requiere cartera destino.',
      );
    }
    if (movement.sourceWalletId == movement.destinationWalletId) {
      return _issue(
        ProjectionIssueCode.sameWalletTransfer,
        movement,
        'Origen y destino de una transferencia interna deben ser distintos.',
      );
    }
    if (!_missing(movement.externalRecipientName) ||
        !_missing(movement.externalDestinationPlatform)) {
      return _malformed(
        movement,
        'Una transferencia interna no admite datos de destino externo.',
      );
    }
    return _validateTransferAmounts(movement);
  }

  ProjectionIssue? _validateExternalTransfer(AccountingMovement movement) {
    if (!_missing(movement.destinationWalletId)) {
      return _issue(
        ProjectionIssueCode.externalDestinationHasOwnedWallet,
        movement,
        'Una transferencia externa no puede acreditar una cartera propia.',
      );
    }
    if (_missing(movement.externalRecipientName) ||
        _missing(movement.externalDestinationPlatform)) {
      return _malformed(
        movement,
        'Una transferencia externa requiere destinatario y plataforma.',
      );
    }
    return _validateTransferAmounts(movement);
  }

  ProjectionIssue? _validateTransferAmounts(AccountingMovement movement) {
    final totalDebited = movement.totalDebitedAmount;
    if (totalDebited == null ||
        totalDebited.compareTo(AccountingAmount.zero) <= 0) {
      return _issue(
        ProjectionIssueCode.inconsistentTransferAmounts,
        movement,
        'Una transferencia requiere total debitado positivo.',
      );
    }
    if (movement.cryptoFeeAmount.compareTo(AccountingAmount.zero) > 0 &&
        _missing(movement.cryptoFeeAsset)) {
      return _malformed(
        movement,
        'Una comisión cripto positiva requiere activo de comisión.',
      );
    }
    final expectedDebit =
        movement.cryptoFeeAsset == null ||
            movement.cryptoFeeAsset == movement.asset
        ? movement.receivedAmount! + movement.cryptoFeeAmount
        : movement.receivedAmount!;
    if (totalDebited != expectedDebit) {
      return _issue(
        ProjectionIssueCode.inconsistentTransferAmounts,
        movement,
        'El total debitado no cuadra con cantidad recibida y comisión.',
      );
    }
    return _validateFiatFeeTreatment(movement);
  }

  ProjectionIssue? _validateFiatFeeTreatment(AccountingMovement movement) {
    final hasCryptoFee =
        movement.cryptoFeeAmount.compareTo(AccountingAmount.zero) > 0;
    final hasFiatFee =
        movement.fiatFeeAmount.compareTo(AccountingAmount.zero) > 0;
    final hasFiatValue = movement.feeFiatValue != null;
    final hasNegativeFiat =
        movement.fiatFeeAmount.compareTo(AccountingAmount.zero) < 0 ||
        (movement.feeFiatValue?.compareTo(AccountingAmount.zero) ?? 0) < 0;
    final isValid = switch (movement.fiatFeeTreatment) {
      FiatFeeTreatment.none => !hasFiatFee && !hasFiatValue,
      FiatFeeTreatment.valuationOfCryptoFee => hasCryptoFee && !hasFiatFee,
      FiatFeeTreatment.paidSeparately =>
        !hasCryptoFee && hasFiatFee && !hasFiatValue,
      FiatFeeTreatment.combined => hasCryptoFee && hasFiatFee,
    };
    return hasNegativeFiat || !isValid
        ? _issue(
            ProjectionIssueCode.invalidAmount,
            movement,
            'El tratamiento de comisión fiat no coincide con sus importes.',
          )
        : null;
  }

  ProjectionIssue? _validateAdjustment(AccountingMovement movement) {
    if (_missing(movement.adjustmentWalletId) ||
        movement.adjustmentQuantity == null ||
        movement.adjustmentQuantity == AccountingAmount.zero ||
        movement.observedBalance == null ||
        _missing(movement.adjustmentReason)) {
      return _issue(
        ProjectionIssueCode.incompleteAdjustment,
        movement,
        'Un ajuste requiere cartera, cantidad firmada, saldo observado y motivo.',
      );
    }
    if (movement.observedBalance!.compareTo(AccountingAmount.zero) < 0) {
      return _issue(
        ProjectionIssueCode.invalidAmount,
        movement,
        'El saldo observado no puede ser negativo.',
      );
    }
    if (_hasForbiddenAdjustmentFields(movement)) {
      return _malformed(
        movement,
        'Un ajuste no admite roles ni cantidades de compra, venta o transferencia.',
      );
    }
    return null;
  }

  bool _hasForbiddenAdjustmentFields(AccountingMovement movement) =>
      movement.quantity != null ||
      movement.unitPriceFiat != null ||
      !_missing(movement.sourceWalletId) ||
      !_missing(movement.destinationWalletId) ||
      movement.destinationType != null ||
      !_missing(movement.externalRecipientName) ||
      !_missing(movement.externalDestinationPlatform) ||
      movement.receivedAmount != null ||
      movement.totalDebitedAmount != null;

  List<LedgerLeg> _legsFor(AccountingMovement movement) {
    final occurredAt = movement.occurredAt.toUtc();
    switch (movement.type) {
      case MovementType.buy:
      case MovementType.transferIn:
        if (movement.destinationWalletId == null) {
          return const <LedgerLeg>[];
        }
        return <LedgerLeg>[
          _leg(
            movement,
            movement.destinationWalletId!,
            LedgerLegKind.custodyCredit,
            movement.quantity!,
            occurredAt,
          ),
        ];
      case MovementType.sell:
        return <LedgerLeg>[
          _leg(
            movement,
            movement.sourceWalletId!,
            LedgerLegKind.custodyDebit,
            movement.quantity!,
            occurredAt,
          ),
        ];
      case MovementType.transferOut:
        return <LedgerLeg>[
          _leg(
            movement,
            movement.sourceWalletId!,
            LedgerLegKind.custodyDebit,
            movement.totalDebitedAmount!,
            occurredAt,
          ),
          if (movement.destinationType == DestinationType.ownWallet)
            _leg(
              movement,
              movement.destinationWalletId!,
              LedgerLegKind.custodyCredit,
              movement.receivedAmount!,
              occurredAt,
            ),
          if (movement.cryptoFeeAmount.compareTo(AccountingAmount.zero) > 0 &&
              movement.cryptoFeeAsset != movement.asset)
            LedgerLeg(
              movementId: movement.id,
              walletId: movement.sourceWalletId!,
              asset: movement.cryptoFeeAsset!,
              kind: LedgerLegKind.custodyDebit,
              quantity: movement.cryptoFeeAmount,
              occurredAt: occurredAt,
            ),
        ];
      case MovementType.balanceAdjustment:
        return <LedgerLeg>[
          _leg(
            movement,
            movement.adjustmentWalletId!,
            LedgerLegKind.adjustment,
            movement.adjustmentQuantity!,
            occurredAt,
          ),
        ];
    }
  }

  LedgerLeg _leg(
    AccountingMovement movement,
    String walletId,
    LedgerLegKind kind,
    AccountingAmount quantity,
    DateTime occurredAt,
  ) => LedgerLeg(
    movementId: movement.id,
    walletId: walletId,
    asset: movement.asset,
    kind: kind,
    quantity: quantity,
    occurredAt: occurredAt,
  );

  ProjectionIssue? _positive(
    AccountingMovement movement,
    AccountingAmount? amount,
    String message,
  ) => amount == null || amount.compareTo(AccountingAmount.zero) <= 0
      ? _issue(ProjectionIssueCode.invalidAmount, movement, message)
      : null;

  bool _missing(String? value) => value == null || value.trim().isEmpty;

  ProjectionIssue _malformed(AccountingMovement movement, String message) =>
      _issue(
        ProjectionIssueCode.malformedHistoricalMovement,
        movement,
        message,
      );

  ProjectionIssue _issue(
    ProjectionIssueCode code,
    AccountingMovement movement,
    String message,
  ) => ProjectionIssue(code, movement.id, message);
}
