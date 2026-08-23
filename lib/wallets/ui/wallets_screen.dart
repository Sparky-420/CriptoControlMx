import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../accounting/domain/wallet.dart';

typedef CreateWalletCallback =
    Future<Wallet> Function({
      required String name,
      required String provider,
      Uint8List? imageBytes,
    });
typedef UpdateWalletCallback =
    Future<Wallet> Function(
      Wallet wallet, {
      required String name,
      required String provider,
      Uint8List? imageBytes,
    });
typedef WalletImageResolver =
    Future<Uint8List> Function(WalletImageRef imageRef);
typedef WalletImagePicker = Future<Uint8List?> Function();

class WalletsScreen extends StatefulWidget {
  const WalletsScreen({
    super.key,
    required this.wallets,
    required this.onCreateWallet,
    required this.onUpdateWallet,
    this.imageResolver,
    this.imagePicker,
  });

  final List<Wallet> wallets;
  final CreateWalletCallback onCreateWallet;
  final UpdateWalletCallback onUpdateWallet;
  final WalletImageResolver? imageResolver;
  final WalletImagePicker? imagePicker;

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
        onSubmit: ({required name, required provider, imageBytes}) {
          if (wallet == null) {
            return widget.onCreateWallet(
              name: name,
              provider: provider,
              imageBytes: imageBytes,
            );
          }
          return widget.onUpdateWallet(
            wallet,
            name: name,
            provider: provider,
            imageBytes: imageBytes,
          );
        },
        imagePicker: widget.imagePicker,
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
              (wallet) => _WalletTile(
                wallet,
                imageResolver: widget.imageResolver,
                onEdit: () => _editWallet(wallet),
              ),
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
  const _WalletTile(
    this.wallet, {
    required this.onEdit,
    required this.imageResolver,
  });

  final Wallet wallet;
  final VoidCallback onEdit;
  final WalletImageResolver? imageResolver;

  @override
  Widget build(BuildContext context) {
    final archived = wallet.status == WalletStatus.archived;
    return Card(
      child: ListTile(
        leading: _WalletAvatar(wallet: wallet, imageResolver: imageResolver),
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
  const _WalletFormDialog({
    required this.wallet,
    required this.onSubmit,
    required this.imagePicker,
  });

  final Wallet? wallet;
  final CreateWalletCallback onSubmit;
  final WalletImagePicker? imagePicker;

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
  bool _pickingImage = false;
  Uint8List? _selectedImageBytes;
  String? _imageError;

  @override
  void dispose() {
    _nameController.dispose();
    _providerController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    Wallet wallet;
    try {
      wallet = await widget.onSubmit(
        name: _nameController.text.trim(),
        provider: _providerController.text.trim(),
        imageBytes: _selectedImageBytes,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _imageError = 'No se pudo procesar la imagen.';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(wallet);
  }

  Future<void> _pickImage() async {
    final picker = widget.imagePicker;
    if (picker == null) return;
    setState(() {
      _pickingImage = true;
      _imageError = null;
    });
    try {
      final bytes = await picker();
      if (!mounted) return;
      setState(() {
        _selectedImageBytes = bytes;
        _pickingImage = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pickingImage = false;
        _imageError = 'No se pudo procesar la imagen.';
      });
    }
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
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed:
                    _saving || _pickingImage || widget.imagePicker == null
                    ? null
                    : _pickImage,
                icon: _pickingImage
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_outlined),
                label: Text(
                  _selectedImageBytes == null
                      ? 'Cambiar imagen'
                      : 'Imagen seleccionada',
                ),
              ),
            ),
            if (_imageError != null) ...<Widget>[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _imageError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 12),
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

class _WalletAvatar extends StatelessWidget {
  const _WalletAvatar({required this.wallet, required this.imageResolver});

  final Wallet wallet;
  final WalletImageResolver? imageResolver;

  @override
  Widget build(BuildContext context) {
    final imageRef = wallet.imageRef;
    final resolver = imageResolver;
    if (imageRef == null || resolver == null) {
      return _InitialsAvatar(wallet: wallet);
    }
    return FutureBuilder<Uint8List>(
      future: resolver(imageRef),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done || bytes == null) {
          return _InitialsAvatar(wallet: wallet);
        }
        return CircleAvatar(backgroundImage: MemoryImage(bytes));
      },
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    final archived = wallet.status == WalletStatus.archived;
    return CircleAvatar(
      backgroundColor: archived
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : Theme.of(context).colorScheme.primaryContainer,
      child: Text(_initials(wallet.name)),
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
