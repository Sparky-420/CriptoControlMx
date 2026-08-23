import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../accounting/domain/accounting_movement.dart';
import '../../accounting/domain/movement_type.dart';
import '../../accounting/domain/wallet.dart';
import '../../accounting/persistence/accounting_document.dart';
import '../application/wallet_movement_assignment_service.dart';

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
typedef AssignMovementToWalletCallback =
    Future<AccountingDocument> Function({
      required AccountingMovement movement,
      required Wallet wallet,
      required WalletMovementAssignmentRole role,
    });

class WalletsScreen extends StatefulWidget {
  const WalletsScreen({
    super.key,
    required this.wallets,
    required this.onCreateWallet,
    required this.onUpdateWallet,
    required this.movements,
    required this.onAssignMovement,
    this.imageResolver,
    this.imagePicker,
  });

  final List<Wallet> wallets;
  final CreateWalletCallback onCreateWallet;
  final UpdateWalletCallback onUpdateWallet;
  final List<AccountingMovement> movements;
  final AssignMovementToWalletCallback onAssignMovement;
  final WalletImageResolver? imageResolver;
  final WalletImagePicker? imagePicker;

  @override
  State<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends State<WalletsScreen> {
  late List<Wallet> _wallets = <Wallet>[...widget.wallets];
  late List<AccountingMovement> _movements = <AccountingMovement>[
    ...widget.movements,
  ];
  String? _assignmentError;

  @override
  void didUpdateWidget(WalletsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wallets != widget.wallets) {
      _wallets = <Wallet>[...widget.wallets];
    }
    if (oldWidget.movements != widget.movements) {
      _movements = <AccountingMovement>[...widget.movements];
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

  Future<void> _assignMovement(AccountingMovement movement) async {
    final assigned = await showDialog<AccountingDocument>(
      context: context,
      builder: (dialogContext) => _MovementAssignmentDialog(
        movement: movement,
        activeWallets: _wallets
            .where((wallet) => wallet.status == WalletStatus.active)
            .toList(growable: false),
        onAssign: widget.onAssignMovement,
      ),
    );
    if (assigned == null || !mounted) return;
    setState(() {
      _assignmentError = null;
      _wallets = <Wallet>[...assigned.wallets];
      _movements = <AccountingMovement>[...assigned.movements];
    });
  }

  void _showAssignmentError() {
    if (!mounted) return;
    setState(() => _assignmentError = 'No se pudo asignar la cartera.');
  }

  @override
  Widget build(BuildContext context) {
    final pendingMovements = _movements
        .where((movement) => walletPendingAssignmentRoles(movement).isNotEmpty)
        .toList(growable: false);
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
          const SizedBox(height: 24),
          _PendingMovementsSection(
            movements: pendingMovements,
            assignmentError: _assignmentError,
            onAssign: (movement) async {
              try {
                await _assignMovement(movement);
              } catch (_) {
                _showAssignmentError();
              }
            },
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

class _PendingMovementsSection extends StatelessWidget {
  const _PendingMovementsSection({
    required this.movements,
    required this.assignmentError,
    required this.onAssign,
  });

  final List<AccountingMovement> movements;
  final String? assignmentError;
  final ValueChanged<AccountingMovement> onAssign;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Movimientos por asignar',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (assignmentError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              assignmentError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (movements.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No hay movimientos pendientes por asignar'),
            ),
          )
        else
          ...movements.map(
            (movement) => _PendingMovementTile(
              movement: movement,
              onAssign: () => onAssign(movement),
            ),
          ),
      ],
    );
  }
}

class _PendingMovementTile extends StatelessWidget {
  const _PendingMovementTile({required this.movement, required this.onAssign});

  final AccountingMovement movement;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text('${movement.asset} · ${_movementTypeLabel(movement.type)}'),
        subtitle: Text(
          'Cantidad: ${movement.quantity?.toJson() ?? '-'} · '
          '${_statusLabel(movement.walletAssignmentStatus)} · '
          '${_pendingRolesLabel(walletPendingAssignmentRoles(movement))}',
        ),
        trailing: TextButton(
          onPressed: onAssign,
          child: const Text('Asignar cartera'),
        ),
      ),
    );
  }
}

class _MovementAssignmentDialog extends StatefulWidget {
  const _MovementAssignmentDialog({
    required this.movement,
    required this.activeWallets,
    required this.onAssign,
  });

  final AccountingMovement movement;
  final List<Wallet> activeWallets;
  final AssignMovementToWalletCallback onAssign;

  @override
  State<_MovementAssignmentDialog> createState() =>
      _MovementAssignmentDialogState();
}

class _MovementAssignmentDialogState extends State<_MovementAssignmentDialog> {
  late final List<WalletMovementAssignmentRole> _roles =
      walletPendingAssignmentRoles(widget.movement);
  Wallet? _selectedWallet;
  late WalletMovementAssignmentRole _selectedRole = _roles.first;
  bool _saving = false;
  String? _error;

  Future<void> _assign() async {
    final wallet =
        _selectedWallet ??
        (widget.activeWallets.isEmpty ? null : widget.activeWallets.first);
    if (wallet == null) return;
    setState(() => _saving = true);
    try {
      final document = await widget.onAssign(
        movement: widget.movement,
        wallet: wallet,
        role: _selectedRole,
      );
      if (!mounted) return;
      Navigator.of(context).pop(document);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No se pudo asignar la cartera.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeWallets = widget.activeWallets;
    return AlertDialog(
      title: const Text('Asignar movimiento'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_roles.length > 1) ...<Widget>[
            DropdownButtonFormField<WalletMovementAssignmentRole>(
              initialValue: _selectedRole,
              decoration: const InputDecoration(labelText: 'Campo pendiente'),
              items: _roles
                  .map(
                    (role) => DropdownMenuItem<WalletMovementAssignmentRole>(
                      value: role,
                      child: Text(_roleLabel(role)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _saving
                  ? null
                  : (role) {
                      if (role == null) return;
                      setState(() => _selectedRole = role);
                    },
            ),
            const SizedBox(height: 12),
          ],
          if (activeWallets.isEmpty)
            const Text('No hay carteras activas disponibles.')
          else
            DropdownButtonFormField<Wallet>(
              initialValue: _selectedWallet ?? activeWallets.first,
              decoration: const InputDecoration(labelText: 'Cartera'),
              items: activeWallets
                  .map(
                    (wallet) => DropdownMenuItem<Wallet>(
                      value: wallet,
                      child: Text(wallet.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _saving
                  ? null
                  : (wallet) => setState(() => _selectedWallet = wallet),
            ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving || activeWallets.isEmpty ? null : _assign,
          child: const Text('Asignar'),
        ),
      ],
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

String _movementTypeLabel(MovementType type) => switch (type) {
  MovementType.buy => 'Compra',
  MovementType.sell => 'Venta',
  MovementType.transferIn => 'Transferencia entrante',
  MovementType.transferOut => 'Transferencia saliente',
  MovementType.balanceAdjustment => 'Ajuste de saldo',
};

String _statusLabel(WalletAssignmentStatus status) => switch (status) {
  WalletAssignmentStatus.assigned => 'Asignado',
  WalletAssignmentStatus.partiallyAssigned => 'Parcialmente asignado',
  WalletAssignmentStatus.pending => 'Asignación pendiente',
  WalletAssignmentStatus.legacyUnassigned => 'Legacy sin asignar',
};

String _pendingRolesLabel(List<WalletMovementAssignmentRole> roles) =>
    roles.map(_roleLabel).join(', ');

String _roleLabel(WalletMovementAssignmentRole role) => switch (role) {
  WalletMovementAssignmentRole.source => 'Origen pendiente',
  WalletMovementAssignmentRole.destination => 'Destino pendiente',
  WalletMovementAssignmentRole.adjustment => 'Cartera de ajuste pendiente',
};
