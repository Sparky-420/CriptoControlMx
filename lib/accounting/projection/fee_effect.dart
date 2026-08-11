import '../domain/accounting_amount.dart';
import '../domain/accounting_movement.dart';
import '../domain/wallet.dart';

final class FeeEffect {
  const FeeEffect({
    required this.assetCustodyDebit,
    required this.otherAssetCustodyDebit,
    required this.fiatCostEffect,
  });

  final AccountingAmount assetCustodyDebit;
  final Map<String, AccountingAmount> otherAssetCustodyDebit;
  final AccountingAmount fiatCostEffect;
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
        : <String, AccountingAmount>{feeAsset: cryptoFee},
    fiatCostEffect: isPaidSeparately
        ? movement.fiatFeeAmount
        : AccountingAmount.zero,
  );
}
