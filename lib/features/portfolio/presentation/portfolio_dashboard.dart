import 'package:flutter/material.dart';
import '../domain/models/portfolio_dashboard_data.dart';

/// Modular portfolio summary presentation. Accounting remains outside this UI.
class PortfolioDashboard extends StatelessWidget {
  const PortfolioDashboard({
    super.key,
    required this.data,
    this.onRefresh,
    this.onAssetSelected,
  });

  final PortfolioDashboardData data;
  final Future<void> Function()? onRefresh;
  final ValueChanged<PortfolioDashboardAsset>? onAssetSelected;

  String _money(double value) {
    final sign = value < 0 ? '- ' : '';
    final digits = value.abs().toStringAsFixed(2).split('.');
    final intPart = digits[0];
    final decPart = digits[1];
    final buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(intPart[i]);
    }
    return '$sign\$${buffer.toString()}.$decPart MXN';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pnlColor = data.unrealizedPnlMxn >= 0
        ? Colors.green.shade600
        : colors.error;

    return RefreshIndicator(
      onRefresh: onRefresh ?? () async {},
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VALOR TOTAL ESTIMADO',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _money(data.totalValueMxn),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${data.unrealizedPnlMxn >= 0 ? '+' : ''}${_money(data.unrealizedPnlMxn)} · '
                      '${data.unrealizedPnlPercent >= 0 ? '+' : ''}${data.unrealizedPnlPercent.toStringAsFixed(2)}% no realizado',
                      style: TextStyle(color: pnlColor, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Text('Costo invertido  ${_money(data.investedMxn)}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tus criptoactivos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('${data.assets.length} activos'),
              ],
            ),
            const SizedBox(height: 8),
            if (data.assets.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('No hay posiciones para mostrar.'),
                  ),
                ),
              )
            else
              ...data.assets.map((asset) {
                final assetPnlColor = asset.pnlMxn >= 0
                    ? Colors.green.shade600
                    : colors.error;
                return Card(
                  child: InkWell(
                    onTap: onAssetSelected == null
                        ? null
                        : () => onAssetSelected!(asset),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(child: Text(asset.symbol)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  asset.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${asset.quantity} ${asset.symbol}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 100),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _money(asset.valueMxn),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${asset.pnlPercent >= 0 ? '+' : ''}${asset.pnlPercent.toStringAsFixed(2)}%',
                                  style: TextStyle(color: assetPnlColor),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
