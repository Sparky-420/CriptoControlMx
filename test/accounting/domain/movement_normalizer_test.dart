import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/ledger_validation.dart';
import 'package:cripto_control_mx/accounting/domain/movement_normalizer.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'H1-09 creation requires existing active wallets but replay allows archived',
    () {
      final at = DateTime.utc(2026, 7, 30, 20, 54);
      final active = Wallet(
        id: '11111111-1111-4111-8111-111111111111',
        name: 'Activa',
        provider: 'Bitso',
        status: WalletStatus.active,
        createdAt: at,
        updatedAt: at,
      );
      final archived = Wallet(
        id: '22222222-2222-4222-8222-222222222222',
        name: 'Archivada',
        provider: 'Bitso',
        status: WalletStatus.archived,
        createdAt: at,
        updatedAt: at,
      );
      final validator = const MovementCreationValidator();
      final activeBuy = movement(
        id: 'active-buy',
        occurredAt: at,
        destinationWalletId: active.id,
      );
      final archivedBuy = movement(
        id: 'archived-buy',
        occurredAt: at,
        destinationWalletId: archived.id,
      );
      final missingBuy = movement(
        id: 'missing-buy',
        occurredAt: at,
        destinationWalletId: '33333333-3333-4333-8333-333333333333',
      );

      expect(
        validator.validate(activeBuy, wallets: <Wallet>[active, archived]),
        isEmpty,
      );
      expect(
        validator
            .validate(archivedBuy, wallets: <Wallet>[active, archived])
            .map((issue) => issue.code),
        <ProjectionIssueCode>[ProjectionIssueCode.inactiveWallet],
      );
      expect(
        validator
            .validate(missingBuy, wallets: <Wallet>[active, archived])
            .map((issue) => issue.code),
        <ProjectionIssueCode>[ProjectionIssueCode.unknownWallet],
      );
      expect(
        validator.validateHistoricalReplay(
          archivedBuy,
          wallets: <Wallet>[active, archived],
        ),
        isEmpty,
      );
    },
  );

  test('sorts by instant and then id without mutating input', () {
    final input = <AccountingMovement>[
      movement(id: 'b', occurredAt: DateTime.utc(2026, 7, 30, 20, 54)),
      movement(id: 'z', occurredAt: DateTime.utc(2026, 7, 30, 20, 53)),
      movement(id: 'a', occurredAt: DateTime.utc(2026, 7, 30, 20, 54)),
    ];

    final result = const DefaultMovementNormalizer().normalize(input);

    expect(result.movements.map((value) => value.id), <String>['z', 'a', 'b']);
    expect(input.map((value) => value.id), <String>['b', 'z', 'a']);
  });

  test(
    'derives exactly one debit and one credit from one internal transfer',
    () {
      final input = <AccountingMovement>[
        movement(
          id: 'internal-transfer',
          occurredAt: DateTime.utc(2026, 7, 30, 20, 54),
          type: MovementType.transferOut,
          sourceWalletId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          destinationWalletId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          destinationType: DestinationType.ownWallet,
          quantity: AccountingAmount.fromInt(1),
          receivedAmount: AccountingAmount.fromInt(1),
          cryptoFeeAmount: AccountingAmount.parse('0.00167532'),
          cryptoFeeAsset: 'UNI',
          totalDebitedAmount: AccountingAmount.parse('1.00167532'),
        ),
      ];

      final result = const DefaultMovementNormalizer().normalize(input);

      expect(input, hasLength(1));
      expect(result.legs, hasLength(2));
      expect(result.legs.map((leg) => leg.kind), <LedgerLegKind>[
        LedgerLegKind.custodyDebit,
        LedgerLegKind.custodyCredit,
      ]);
      expect(result.legs.map((leg) => leg.movementId), <String>[
        'internal-transfer',
        'internal-transfer',
      ]);
    },
  );

  test(
    'normalizes valid wallet roles without inferring platform ownership',
    () {
      final at = DateTime.utc(2026, 7, 30, 20, 54);
      final result = const DefaultMovementNormalizer()
          .normalize(<AccountingMovement>[
            movement(
              id: 'buy',
              occurredAt: at,
              destinationWalletId: 'buy-wallet',
            ),
            movement(
              id: 'sell',
              occurredAt: at,
              type: MovementType.sell,
              sourceWalletId: 'sell-wallet',
            ),
            movement(
              id: 'incoming',
              occurredAt: at,
              type: MovementType.transferIn,
              destinationWalletId: 'incoming-wallet',
            ),
            movement(
              id: 'legacy-incoming',
              occurredAt: at,
              type: MovementType.transferIn,
              walletAssignmentStatus: WalletAssignmentStatus.legacyUnassigned,
            ),
            movement(
              id: 'external',
              occurredAt: at,
              type: MovementType.transferOut,
              sourceWalletId: 'external-wallet',
              destinationType: DestinationType.external,
              receivedAmount: AccountingAmount.fromInt(1),
              totalDebitedAmount: AccountingAmount.fromInt(1),
              externalRecipientName: 'Tercero',
              externalDestinationPlatform: 'Mercado Pago',
            ),
            movement(
              id: 'adjustment',
              occurredAt: at,
              type: MovementType.balanceAdjustment,
              adjustmentWalletId: 'adjustment-wallet',
              adjustmentQuantity: AccountingAmount.fromInt(2),
              observedBalance: AccountingAmount.fromInt(12),
              adjustmentReason: 'Corte de saldo',
            ),
          ]);

      expect(result.issues, isEmpty);
      expect(result.legs, hasLength(5));
      expect(
        result.legs.map((leg) => '${leg.kind.name}:${leg.walletId}'),
        <String>[
          'adjustment:adjustment-wallet',
          'custodyCredit:buy-wallet',
          'custodyDebit:external-wallet',
          'custodyCredit:incoming-wallet',
          'custodyDebit:sell-wallet',
        ],
      );
    },
  );

  test('reports invalid transfers and adjustments without ledger legs', () {
    final at = DateTime.utc(2026, 7, 30, 20, 54);
    final invalidMovements = <AccountingMovement>[
      movement(
        id: 'same-wallet',
        occurredAt: at,
        type: MovementType.transferOut,
        sourceWalletId: 'wallet-1',
        destinationWalletId: 'wallet-1',
        destinationType: DestinationType.ownWallet,
        receivedAmount: AccountingAmount.fromInt(1),
        totalDebitedAmount: AccountingAmount.fromInt(1),
      ),
      movement(
        id: 'external-owned-wallet',
        occurredAt: at,
        type: MovementType.transferOut,
        sourceWalletId: 'wallet-1',
        destinationWalletId: 'wallet-2',
        destinationType: DestinationType.external,
        receivedAmount: AccountingAmount.fromInt(1),
        totalDebitedAmount: AccountingAmount.fromInt(1),
        externalRecipientName: 'Tercero',
        externalDestinationPlatform: 'Bitso',
      ),
      movement(
        id: 'amount-mismatch',
        occurredAt: at,
        type: MovementType.transferOut,
        sourceWalletId: 'wallet-1',
        destinationWalletId: 'wallet-2',
        destinationType: DestinationType.ownWallet,
        quantity: AccountingAmount.fromInt(1),
        receivedAmount: AccountingAmount.fromInt(1),
        cryptoFeeAmount: AccountingAmount.parse('0.00167532'),
        cryptoFeeAsset: 'UNI',
        totalDebitedAmount: AccountingAmount.fromInt(1),
      ),
      movement(
        id: 'incomplete-adjustment',
        occurredAt: at,
        type: MovementType.balanceAdjustment,
      ),
    ];

    final result = const DefaultMovementNormalizer().normalize(
      invalidMovements,
    );

    expect(result.legs, isEmpty);
    expect(result.issues.map((issue) => issue.code), <ProjectionIssueCode>[
      ProjectionIssueCode.inconsistentTransferAmounts,
      ProjectionIssueCode.externalDestinationHasOwnedWallet,
      ProjectionIssueCode.incompleteAdjustment,
      ProjectionIssueCode.sameWalletTransfer,
    ]);
  });

  test('reports duplicate IDs without discarding their audit history', () {
    final at = DateTime.utc(2026, 7, 30, 20, 54);
    final result = const DefaultMovementNormalizer()
        .normalize(<AccountingMovement>[
          movement(id: 'duplicate', occurredAt: at),
          movement(
            id: 'duplicate',
            occurredAt: at.add(const Duration(minutes: 1)),
          ),
        ]);

    expect(result.movements.map((movement) => movement.id), <String>[
      'duplicate',
      'duplicate',
    ]);
    expect(result.issues.map((issue) => issue.code), <ProjectionIssueCode>[
      ProjectionIssueCode.duplicateMovementId,
    ]);
  });

  test('reports missing wallet roles and malformed role combinations', () {
    final at = DateTime.utc(2026, 7, 30, 20, 54);
    final result = const DefaultMovementNormalizer()
        .normalize(<AccountingMovement>[
          movement(
            id: 'buy-missing',
            occurredAt: at,
          ).copyWith(destinationWalletId: null),
          movement(id: 'sell-missing', occurredAt: at, type: MovementType.sell),
          movement(
            id: 'incoming-missing',
            occurredAt: at,
            type: MovementType.transferIn,
          ),
          movement(
            id: 'own-with-external-data',
            occurredAt: at,
            type: MovementType.transferOut,
            sourceWalletId: 'wallet-1',
            destinationWalletId: 'wallet-2',
            destinationType: DestinationType.ownWallet,
            receivedAmount: AccountingAmount.fromInt(1),
            totalDebitedAmount: AccountingAmount.fromInt(1),
            externalRecipientName: 'Tercero',
          ),
          movement(
            id: 'external-without-recipient',
            occurredAt: at,
            type: MovementType.transferOut,
            sourceWalletId: 'wallet-1',
            destinationType: DestinationType.external,
            receivedAmount: AccountingAmount.fromInt(1),
            totalDebitedAmount: AccountingAmount.fromInt(1),
          ),
          movement(
            id: 'zero-amount',
            occurredAt: at,
            quantity: AccountingAmount.zero,
          ),
        ]);

    expect(result.legs, isEmpty);
    expect(result.issues.map((issue) => issue.code), <ProjectionIssueCode>[
      ProjectionIssueCode.missingDestinationWallet,
      ProjectionIssueCode.malformedHistoricalMovement,
      ProjectionIssueCode.missingDestinationWallet,
      ProjectionIssueCode.malformedHistoricalMovement,
      ProjectionIssueCode.missingSourceWallet,
      ProjectionIssueCode.invalidAmount,
    ]);
  });

  test(
    'derives separate other-asset fee debits for external and internal transfers',
    () {
      final at = DateTime.utc(2026, 7, 30, 20, 54);
      final result = const DefaultMovementNormalizer()
          .normalize(<AccountingMovement>[
            movement(
              id: 'external-other-asset-fee',
              occurredAt: at,
              type: MovementType.transferOut,
              sourceWalletId: 'external-source',
              destinationType: DestinationType.external,
              quantity: AccountingAmount.fromInt(1),
              receivedAmount: AccountingAmount.fromInt(1),
              cryptoFeeAmount: AccountingAmount.parse('0.5'),
              cryptoFeeAsset: 'BTC',
              totalDebitedAmount: AccountingAmount.fromInt(1),
              externalRecipientName: 'Tercero',
              externalDestinationPlatform: 'Bitso',
            ),
            movement(
              id: 'internal-other-asset-fee',
              occurredAt: at.add(const Duration(minutes: 1)),
              type: MovementType.transferOut,
              sourceWalletId: 'internal-source',
              destinationWalletId: 'internal-destination',
              destinationType: DestinationType.ownWallet,
              quantity: AccountingAmount.fromInt(1),
              receivedAmount: AccountingAmount.fromInt(1),
              cryptoFeeAmount: AccountingAmount.parse('0.5'),
              cryptoFeeAsset: 'BTC',
              totalDebitedAmount: AccountingAmount.fromInt(1),
            ),
          ]);

      expect(result.issues, isEmpty);
      expect(result.legs, hasLength(5));
      expect(
        result.legs.map(
          (leg) =>
              '${leg.movementId}:${leg.kind.name}:${leg.walletId}:${leg.asset}:${leg.quantity.toJson()}',
        ),
        <String>[
          'external-other-asset-fee:custodyDebit:external-source:UNI:1',
          'external-other-asset-fee:custodyDebit:external-source:BTC:0.5',
          'internal-other-asset-fee:custodyDebit:internal-source:UNI:1',
          'internal-other-asset-fee:custodyCredit:internal-destination:UNI:1',
          'internal-other-asset-fee:custodyDebit:internal-source:BTC:0.5',
        ],
      );
    },
  );

  test(
    'rejects external and transfer role fields on incoming transfers and adjustments',
    () {
      final at = DateTime.utc(2026, 7, 30, 20, 54);
      final result = const DefaultMovementNormalizer()
          .normalize(<AccountingMovement>[
            movement(
              id: 'adjustment-with-transfer-fields',
              occurredAt: at,
              type: MovementType.balanceAdjustment,
              quantity: AccountingAmount.fromInt(1),
              unitPriceFiat: AccountingAmount.fromInt(100),
              sourceWalletId: 'source-wallet',
              destinationWalletId: 'destination-wallet',
              destinationType: DestinationType.external,
              receivedAmount: AccountingAmount.fromInt(1),
              totalDebitedAmount: AccountingAmount.fromInt(1),
              externalRecipientName: 'Tercero',
              externalDestinationPlatform: 'Bitso',
              adjustmentWalletId: 'adjustment-wallet',
              adjustmentQuantity: AccountingAmount.fromInt(1),
              observedBalance: AccountingAmount.fromInt(10),
              adjustmentReason: 'Corte de saldo',
            ),
            movement(
              id: 'incoming-with-external-fields',
              occurredAt: at,
              type: MovementType.transferIn,
              destinationWalletId: 'incoming-wallet',
              externalRecipientName: 'Tercero',
              externalDestinationPlatform: 'Bitso',
            ),
          ]);

      expect(result.legs, isEmpty);
      expect(result.issues.map((issue) => issue.code), <ProjectionIssueCode>[
        ProjectionIssueCode.malformedHistoricalMovement,
        ProjectionIssueCode.malformedHistoricalMovement,
      ]);
    },
  );
}

AccountingMovement movement({
  required String id,
  required DateTime occurredAt,
  MovementType type = MovementType.buy,
  AccountingAmount? quantity,
  AccountingAmount? unitPriceFiat,
  String? sourceWalletId,
  String? destinationWalletId,
  DestinationType? destinationType,
  AccountingAmount? receivedAmount,
  AccountingAmount? cryptoFeeAmount,
  String? cryptoFeeAsset,
  AccountingAmount? totalDebitedAmount,
  String? externalRecipientName,
  String? externalDestinationPlatform,
  WalletAssignmentStatus walletAssignmentStatus =
      WalletAssignmentStatus.assigned,
  String? adjustmentWalletId,
  AccountingAmount? adjustmentQuantity,
  AccountingAmount? observedBalance,
  String? adjustmentReason,
}) => AccountingMovement(
  id: id,
  type: type,
  asset: 'UNI',
  occurredAt: occurredAt,
  fiatFeeAmount: AccountingAmount.zero,
  quantity:
      quantity ??
      (type == MovementType.balanceAdjustment
          ? null
          : AccountingAmount.fromInt(1)),
  unitPriceFiat: unitPriceFiat,
  sourceWalletId: sourceWalletId,
  destinationWalletId:
      destinationWalletId ?? (type == MovementType.buy ? 'wallet-1' : null),
  destinationType: destinationType,
  externalRecipientName: externalRecipientName,
  externalDestinationPlatform: externalDestinationPlatform,
  walletAssignmentStatus: walletAssignmentStatus,
  receivedAmount: receivedAmount,
  cryptoFeeAmount: cryptoFeeAmount ?? AccountingAmount.zero,
  cryptoFeeAsset: cryptoFeeAsset,
  totalDebitedAmount: totalDebitedAmount,
  fiatFeeTreatment: FiatFeeTreatment.none,
  reconciliationLinks: const <ReconciliationLink>[],
  createdAt: occurredAt,
  updatedAt: occurredAt,
  adjustmentWalletId: adjustmentWalletId,
  adjustmentQuantity: adjustmentQuantity,
  observedBalance: observedBalance,
  adjustmentReason: adjustmentReason,
);
