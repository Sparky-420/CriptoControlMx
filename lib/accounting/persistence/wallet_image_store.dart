import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../domain/wallet.dart';
import '../support/sha256.dart';
import 'wallet_image_processor.dart';

abstract interface class WalletImageStore {
  Future<void> write(ProcessedWalletImage image);
  Future<WalletImageWriteBatch> stageAll(List<ProcessedWalletImage> images);
  Future<Uint8List> read(WalletImageRef imageRef);
  Future<void> deleteIfUnreferenced(
    WalletImageRef imageRef,
    Set<String> referencedImageIds,
  );
}

abstract interface class WalletImageWriteBatch {
  Future<void> commit();
  Future<void> rollback({Set<String> referencedImageIds = const <String>{}});
}

final class PrivateWalletImageStore implements WalletImageStore {
  PrivateWalletImageStore({
    Future<Directory> Function()? applicationSupportDirectory,
  }) : _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _applicationSupportDirectory;

  @override
  Future<void> write(ProcessedWalletImage image) async {
    final batch = await stageAll(<ProcessedWalletImage>[image]);
    await batch.commit();
  }

  @override
  Future<WalletImageWriteBatch> stageAll(
    List<ProcessedWalletImage> images,
  ) async {
    for (final image in images) {
      _validateImage(image);
    }
    final directory = await _imageDirectory();
    final staged = <_StagedImage>[];
    final stagedTargets = <String>{};
    try {
      for (final image in images) {
        final target = File(_pathFor(directory, image.imageRef));
        if (!stagedTargets.add(target.path)) {
          continue;
        }
        if (await target.exists()) {
          final existingBytes = await target.readAsBytes();
          if (existingBytes.length != image.imageRef.byteLength ||
              sha256BytesHex(existingBytes) != image.imageRef.sha256) {
            throw StateError(
              'La imagen privada preexistente no coincide con su referencia.',
            );
          }
          continue;
        }
        final temporary = File(
          '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
        );
        await temporary.writeAsBytes(image.bytes, flush: true);
        staged.add(_StagedImage(temporary, target, image.imageRef));
      }
    } catch (_) {
      for (final item in staged) {
        if (await item.temporary.exists()) await item.temporary.delete();
      }
      rethrow;
    }
    return _PrivateWalletImageWriteBatch(staged);
  }

  @override
  Future<Uint8List> read(WalletImageRef imageRef) async {
    _validateReference(imageRef);
    final file = File(_pathFor(await _imageDirectory(), imageRef));
    final bytes = await file.readAsBytes();
    if (bytes.length != imageRef.byteLength ||
        sha256BytesHex(bytes) != imageRef.sha256) {
      throw StateError('La imagen privada no coincide con su referencia.');
    }
    return bytes;
  }

  @override
  Future<void> deleteIfUnreferenced(
    WalletImageRef imageRef,
    Set<String> referencedImageIds,
  ) async {
    _validateReference(imageRef);
    if (referencedImageIds.contains(imageRef.id)) return;
    final file = File(_pathFor(await _imageDirectory(), imageRef));
    if (await file.exists()) await file.delete();
  }

  Future<Directory> _imageDirectory() async {
    final root = await _applicationSupportDirectory();
    final canonicalRoot = Directory(await root.resolveSymbolicLinks());
    final directory = Directory(
      '${canonicalRoot.path}${Platform.pathSeparator}wallet_images',
    );
    await directory.create(recursive: true);
    final canonicalDirectory = Directory(
      await directory.resolveSymbolicLinks(),
    );
    if (canonicalDirectory.parent.path != canonicalRoot.path) {
      throw StateError('El directorio privado de imágenes no es seguro.');
    }
    return canonicalDirectory;
  }

  String _pathFor(Directory directory, WalletImageRef imageRef) {
    final path =
        '${directory.path}${Platform.pathSeparator}${imageRef.fileName}';
    final normalizedDirectory =
        '${directory.absolute.path}${Platform.pathSeparator}';
    if (!File(path).absolute.path.startsWith(normalizedDirectory)) {
      throw ArgumentError.value(
        imageRef.fileName,
        'fileName',
        'Debe permanecer en el directorio privado.',
      );
    }
    return path;
  }

  void _validateImage(ProcessedWalletImage image) {
    _validateReference(image.imageRef);
    if (image.bytes.length != image.imageRef.byteLength ||
        sha256BytesHex(image.bytes) != image.imageRef.sha256) {
      throw ArgumentError(
        'Los bytes no coinciden con la referencia de imagen.',
      );
    }
  }

  void _validateReference(WalletImageRef imageRef) {
    final extension = switch (imageRef.mimeType) {
      'image/png' => 'png',
      'image/jpeg' => 'jpg',
      _ => null,
    };
    if (extension == null ||
        imageRef.id != imageRef.sha256 ||
        imageRef.fileName != '${imageRef.sha256}.$extension' ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(imageRef.sha256)) {
      throw ArgumentError.value(
        imageRef,
        'imageRef',
        'La referencia de imagen no está normalizada.',
      );
    }
  }
}

final class _StagedImage {
  const _StagedImage(this.temporary, this.target, this.imageRef);
  final File temporary;
  final File target;
  final WalletImageRef imageRef;
}

final class _PrivateWalletImageWriteBatch implements WalletImageWriteBatch {
  _PrivateWalletImageWriteBatch(this._staged);
  final List<_StagedImage> _staged;
  final List<_StagedImage> _promoted = <_StagedImage>[];
  var _committed = false;
  var _rolledBack = false;

  @override
  Future<void> commit() async {
    if (_committed || _rolledBack) return;
    try {
      for (final item in _staged) {
        if (!await item.temporary.exists()) {
          if (await item.target.exists()) await _verifyTarget(item);
          continue;
        }
        if (await item.target.exists()) {
          await _verifyTarget(item);
          await item.temporary.delete();
          continue;
        }
        await item.temporary.rename(item.target.path);
        _promoted.add(item);
      }
      _committed = true;
    } catch (_) {
      for (final item in _staged) {
        if (await item.temporary.exists()) await item.temporary.delete();
      }
      rethrow;
    }
  }

  @override
  Future<void> rollback({
    Set<String> referencedImageIds = const <String>{},
  }) async {
    if (_rolledBack) return;
    for (final item in _staged) {
      if (await item.temporary.exists()) await item.temporary.delete();
    }
    for (final item in _promoted) {
      if (!referencedImageIds.contains(item.imageRef.id) &&
          await item.target.exists()) {
        await item.target.delete();
      }
    }
    _rolledBack = true;
  }

  Future<void> _verifyTarget(_StagedImage item) async {
    final bytes = await item.target.readAsBytes();
    if (bytes.length != item.imageRef.byteLength ||
        sha256BytesHex(bytes) != item.imageRef.sha256) {
      throw StateError(
        'La imagen privada preexistente no coincide con su referencia.',
      );
    }
  }
}
