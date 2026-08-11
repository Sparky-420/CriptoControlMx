import '../domain/accounting_amount.dart';
import '../domain/accounting_movement.dart';
import '../domain/wallet.dart';

final class FeeEffect {
  factory FeeEffect({
    required AccountingAmount assetCustodyDebit,
    required Map<String, AccountingAmount> otherAssetCustodyDebit,
    required AccountingAmount fiatCostEffect,
  }) => FeeEffect._(
    assetCustodyDebit: assetCustodyDebit,
    otherAssetCustodyDebit: Map<String, AccountingAmount>.unmodifiable(
      Map<String, AccountingAmount>.of(otherAssetCustodyDebit),
    ),
    fiatCostEffect: fiatCostEffect,
  );

  const FeeEffect._({
    required this.assetCustodyDebit,
    required this.otherAssetCustodyDebit,
    required this.fiatCostEffect,
  });

  final AccountingAmount assetCustodyDebit;
  final Map<String, AccountingAmount> otherAssetCustodyDebit;
  final AccountingAmount fiatCostEffect;

  static final FeeEffect zero = FeeEffect._(
    assetCustodyDebit: AccountingAmount.zero,
    otherAssetCustodyDebit: const <String, AccountingAmount>{},
    fiatCostEffect: AccountingAmount.zero,
  );
}

FeeEffect resolveFeeEffect(AccountingMovement movement) {
  final cryptoFee = movement.cryptoFeeAmount;
  final feeAsset = movement.cryptoFeeAsset;
  final isSameAsset = feeAsset == movement.asset;
  final isPaidSeparately =
      movement.fiatFeeTreatment == FiatFeeTreatment.paidSeparately ||
      movement.fiatFeeTreatment == FiatFeeTreatment.combined;
  return FeeEffect(
    assetCustodyDebit: cryptoFee == AccountingAmount.zero || !isSameAsset
        ? AccountingAmount.zero
        : cryptoFee,
    otherAssetCustodyDebit:
        cryptoFee == AccountingAmount.zero || feeAsset == null || isSameAsset
        ? const <String, AccountingAmount>{}
        : Map<String, AccountingAmount>.unmodifiable(<String, AccountingAmount>{
            feeAsset: cryptoFee,
          }),
    fiatCostEffect: isPaidSeparately
        ? movement.fiatFeeAmount
        : AccountingAmount.zero,
  );
}
