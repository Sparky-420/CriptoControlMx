import 'package:flutter/material.dart';

import '../../accounting/domain/wallet.dart';

class WalletsScreen extends StatelessWidget {
  const WalletsScreen({super.key, required this.wallets});

  final List<Wallet> wallets;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Carteras')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: <Widget>[
          FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.add),
            label: const Text('Nueva cartera'),
          ),
          const SizedBox(height: 16),
          if (wallets.isEmpty)
            const _EmptyWalletsState()
          else
            ...wallets.map(_WalletTile.new),
        ],
      ),
    );
  }
}

class _EmptyWalletsState extends StatelessWidget {
  const _EmptyWalletsState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 48,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Aún no tienes carteras configuradas.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'La creación estará disponible en una próxima etapa.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletTile extends StatelessWidget {
  const _WalletTile(this.wallet);

  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    final archived = wallet.status == WalletStatus.archived;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: archived
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Theme.of(context).colorScheme.primaryContainer,
          child: Text(_initials(wallet.name)),
        ),
        title: Text(wallet.name),
        subtitle: Text(wallet.provider),
        trailing: Chip(
          label: Text(archived ? 'Archivada' : 'Activa'),
          avatar: Icon(
            archived ? Icons.inventory_2_outlined : Icons.check_circle_outline,
            size: 18,
          ),
        ),
      ),
    );
  }
}

String _initials(String value) {
  final words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    return words.single.characters.take(2).toString().toUpperCase();
  }
  return words
      .take(2)
      .map((word) => word.characters.first)
      .join()
      .toUpperCase();
}
