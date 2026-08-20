import '../persistence/accounting_document.dart';
import '../persistence/accounting_repository.dart';
import '../persistence/wallet_image_store.dart';
import '../support/sha256.dart';
import 'accounting_backup_bundle.dart';

abstract interface class AccountingBackupStateStore {
  Future<AccountingBackupApplicationState> read();
  Future<void> write(AccountingBackupApplicationState state);
}

final class AccountingBackupApplicationState {
  const AccountingBackupApplicationState({
    required this.snapshots,
    required this.currentPrices,
    required this.settings,
  });

  final List<BackupPortfolioSnapshot> snapshots;
  final Map<String, double> currentPrices;
  final AccountingBackupSettings settings;
}

final class AccountingBackupRestoreResult {
  const AccountingBackupRestoreResult({
    required this.document,
    required this.origin,
    required this.warnings,
  });

  final AccountingDocument document;
  final AccountingBackupOrigin origin;
  final List<String> warnings;
}

final class AccountingRestoreRollbackException implements Exception {
  const AccountingRestoreRollbackException({
    required this.writeCause,
    required this.rollbackCause,
  });

  final Object writeCause;
  final Object rollbackCause;
}

abstract interface class AccountingBackupRestoreService {
  Future<AccountingBackupRestoreResult> restore(
    DecodedAccountingBackup decoded,
  );
}

final class DefaultAccountingBackupRestoreService
    implements AccountingBackupRestoreService {
  const DefaultAccountingBackupRestoreService(
    this._repository,
    this._imageStore,
    this._stateStore,
  );

  final AccountingRepository _repository;
  final WalletImageStore _imageStore;
  final AccountingBackupStateStore _stateStore;

  @override
  Future<AccountingBackupRestoreResult> restore(
    DecodedAccountingBackup decoded,
  ) async {
    final previousDocument = await _repository.read();
    final previousState = await _stateStore.read();
    final bundle = decoded.bundle;
    _validateBundle(bundle);
    final batch = await _imageStore.stageAll(
      bundle.walletImages.map((image) => image.toProcessed()).toList(),
    );
    try {
      await batch.commit();
      await _repository.write(bundle.document);
      await _stateStore.write(
        AccountingBackupApplicationState(
          snapshots: bundle.snapshots,
          currentPrices: bundle.currentPrices,
          settings: bundle.settings,
        ),
      );
    } catch (writeCause) {
      Object? rollbackCause;
      var documentRollbackSucceeded = false;
      try {
        if (previousDocument == null) {
          await _repository.clear();
        } else {
          await _repository.write(previousDocument);
        }
        documentRollbackSucceeded = true;
      } catch (error) {
        rollbackCause = error;
      }
      try {
        await _stateStore.write(previousState);
      } catch (error) {
        rollbackCause ??= error;
      }
      try {
        await batch.rollback(
          referencedImageIds: <String>{
            for (final wallet in previousDocument?.wallets ?? const [])
              if (wallet.imageRef != null) wallet.imageRef!.id,
            if (!documentRollbackSucceeded)
              for (final wallet in bundle.document.wallets)
                if (wallet.imageRef != null) wallet.imageRef!.id,
          },
        );
      } catch (error) {
        rollbackCause ??= error;
      }
      if (rollbackCause != null) {
        throw AccountingRestoreRollbackException(
          writeCause: writeCause,
          rollbackCause: rollbackCause,
        );
      }
      rethrow;
    }
    return AccountingBackupRestoreResult(
      document: bundle.document,
      origin: decoded.origin,
      warnings: decoded.warnings,
    );
  }
}

void _validateBundle(AccountingBackupBundle bundle) {
  final walletIds = <String>{};
  final imageRefs = <String, Map<String, Object?>>{};
  for (final wallet in bundle.document.wallets) {
    if (wallet.id.trim().isEmpty || !walletIds.add(wallet.id)) {
      throw const FormatException('ID de cartera inválido o duplicado.');
    }
    final imageRef = wallet.imageRef;
    if (imageRef == null) continue;
    final extension = switch (imageRef.mimeType) {
      'image/png' => 'png',
      'image/jpeg' => 'jpg',
      _ => null,
    };
    final imageRefJson = imageRef.toJson();
    final existingImageRefJson = imageRefs[imageRef.id];
    if (extension == null ||
        imageRef.id != imageRef.sha256 ||
        imageRef.fileName != '${imageRef.sha256}.$extension' ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(imageRef.sha256)) {
      throw const FormatException('Referencia de imagen inválida o duplicada.');
    }
    if (existingImageRefJson != null) {
      if (canonicalJson(existingImageRefJson) != canonicalJson(imageRefJson)) {
        throw const FormatException(
          'Referencia de imagen inválida o duplicada.',
        );
      }
      continue;
    }
    imageRefs[imageRef.id] = imageRefJson;
  }
  final movementIds = <String>{};
  for (final movement in bundle.document.movements) {
    if (movement.id.trim().isEmpty || !movementIds.add(movement.id)) {
      throw const FormatException('ID de movimiento inválido o duplicado.');
    }
    for (final walletId in <String?>[
      movement.sourceWalletId,
      movement.destinationWalletId,
      movement.adjustmentWalletId,
    ]) {
      if (walletId != null && !walletIds.contains(walletId)) {
        throw const FormatException('Referencia de cartera inexistente.');
      }
    }
  }
  if (bundle.walletImages.length != imageRefs.length) {
    throw const FormatException('Faltan imágenes portables del documento.');
  }
  final portableIds = <String>{};
  for (final image in bundle.walletImages) {
    final imageRef = image.imageRef;
    if (!portableIds.add(imageRef.id) ||
        canonicalJson(imageRefs[imageRef.id]) !=
            canonicalJson(imageRef.toJson()) ||
        image.bytes.length != imageRef.byteLength ||
        sha256BytesHex(image.bytes) != imageRef.sha256) {
      throw const FormatException('Imagen portable inválida.');
    }
  }
  final snapshotIds = <String>{};
  for (final snapshot in bundle.snapshots) {
    if (snapshot.id.trim().isEmpty ||
        !snapshotIds.add(snapshot.id) ||
        snapshot.movementCount < 0) {
      throw const FormatException('Instantánea inválida o duplicada.');
    }
    _requireFinite(<double>[
      snapshot.totalCostBase,
      snapshot.totalCurrentValue,
      snapshot.totalUnrealizedPL,
      snapshot.totalRealizedPL,
    ]);
    for (final coin in snapshot.coins) {
      if (coin.coin.trim().isEmpty) {
        throw const FormatException('Activo de instantánea inválido.');
      }
      _requireFinite(<double>[
        coin.quantity,
        coin.costBase,
        coin.avgPrice,
        coin.currentValue,
        coin.unrealizedPL,
        coin.realizedPL,
      ]);
    }
  }
  for (final entry in bundle.currentPrices.entries) {
    if (entry.key.trim().isEmpty || !entry.value.isFinite) {
      throw const FormatException('Precio actual inválido.');
    }
  }
  if (!bundle.settings.sellFeePercent.isFinite ||
      bundle.settings.priceModes.entries.any(
        (entry) => entry.key.trim().isEmpty || entry.value.trim().isEmpty,
      ) ||
      bundle.settings.manualPricesUpdatedAtMs.keys.any(
        (key) => key.trim().isEmpty,
      )) {
    throw const FormatException('Settings contables inválidos.');
  }
}

void _requireFinite(Iterable<double> values) {
  if (values.any((value) => !value.isFinite)) {
    throw const FormatException('El respaldo contiene un número no finito.');
  }
}
