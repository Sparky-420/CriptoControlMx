import 'package:flutter/material.dart';

import '../../accounting/domain/wallet.dart';

typedef CreateWalletCallback =
    Future<Wallet> Function({required String name, required String provider});
typedef UpdateWalletCallback =
    Future<Wallet> Function(
      Wallet wallet, {
      required String name,
      required String provider,
    });

class WalletsScreen extends StatefulWidget {
  const WalletsScreen({
    super.key,
    required this.wallets,
    required this.onCreateWallet,
    required this.onUpdateWallet,
  });

  final List<Wallet> wallets;
  final CreateWalletCallback onCreateWallet;
  final UpdateWalletCallback onUpdateWallet;

  @override
  State<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends State<WalletsScreen> {
  late List<Wallet> _wallets = <Wallet>[...widget.wallets];

  @override
  void didUpdateWidget(WalletsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wallets != widget.wallets) {
      _wallets = <Wallet>[...widget.wallets];
    }
  }

  Future<void> _createWallet() async {
    final wallet = await _showWalletForm(context);
    if (wallet == null || !mounted) return;
    setState(() => _wallets = <Wallet>[..._wallets, wallet]);
  }

  Future<void> _editWallet(Wallet wallet) async {
    final updated = await _showWalletForm(context, wallet: wallet);
    if (updated == null || !mounted) return;
    setState(() {
      _wallets = <Wallet>[
        for (final current in _wallets)
          if (current.id == updated.id) updated else current,
      ];
    });
  }

  Future<Wallet?> _showWalletForm(BuildContext context, {Wallet? wallet}) {
    return showDialog<Wallet>(
      context: context,
      builder: (dialogContext) => _WalletFormDialog(
        wallet: wallet,
        onSubmit: ({required name, required provider}) {
          if (wallet == null) {
            return widget.onCreateWallet(name: name, provider: provider);
          }
          return widget.onUpdateWallet(wallet, name: name, provider: provider);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Carteras')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: <Widget>[
          FilledButton.icon(
            onPressed: _createWallet,
            icon: const Icon(Icons.add),
            label: const Text('Nueva cartera'),
          ),
          const SizedBox(height: 16),
          if (_wallets.isEmpty)
            const _EmptyWalletsState()
          else
            ..._wallets.map(
              (wallet) =>
                  _WalletTile(wallet, onEdit: () => _editWallet(wallet)),
            ),
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
  const _WalletTile(this.wallet, {required this.onEdit});

  final Wallet wallet;
  final VoidCallback onEdit;

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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Chip(
              label: Text(archived ? 'Archivada' : 'Activa'),
              avatar: Icon(
                archived
                    ? Icons.inventory_2_outlined
                    : Icons.check_circle_outline,
                size: 18,
              ),
            ),
            IconButton(
              tooltip: 'Editar ${wallet.name}',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletFormDialog extends StatefulWidget {
  const _WalletFormDialog({required this.wallet, required this.onSubmit});

  final Wallet? wallet;
  final CreateWalletCallback onSubmit;

  @override
  State<_WalletFormDialog> createState() => _WalletFormDialogState();
}

class _WalletFormDialogState extends State<_WalletFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController = TextEditingController(
    text: widget.wallet?.name ?? '',
  );
  late final TextEditingController _providerController = TextEditingController(
    text: widget.wallet?.provider ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _providerController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final wallet = await widget.onSubmit(
      name: _nameController.text.trim(),
      provider: _providerController.text.trim(),
    );
    if (!mounted) return;
    Navigator.of(context).pop(wallet);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.wallet != null;
    return AlertDialog(
      title: Text(isEditing ? 'Editar cartera' : 'Crear cartera'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nombre'),
              textInputAction: TextInputAction.next,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Ingresa un nombre.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _providerController,
              decoration: const InputDecoration(labelText: 'Plataforma'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Ingresa una plataforma.'
                  : null,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(isEditing ? 'Guardar' : 'Crear'),
        ),
      ],
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
