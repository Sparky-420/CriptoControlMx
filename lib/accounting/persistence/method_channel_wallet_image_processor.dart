import 'package:flutter/services.dart';

import '../domain/wallet.dart';
import '../support/sha256.dart';
import 'wallet_image_processor.dart';

final class WalletImageProcessingException implements Exception {
  const WalletImageProcessingException(this.message);
  final String message;

  @override
  String toString() => 'WalletImageProcessingException: $message';
}

final class MethodChannelWalletImageProcessor implements WalletImageProcessor {
  MethodChannelWalletImageProcessor({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'mx.criptocontrolmx.app/wallet_images';
  final MethodChannel _channel;

  @override
  Future<ProcessedWalletImage> process(
    Uint8List source, {
    required bool preserveAlpha,
    int maxLongEdge = 1024,
    int jpegQuality = 82,
  }) async {
    try {
      final result = Map<Object?, Object?>.from(
        await _channel.invokeMethod<Object?>('process', <String, Object?>{
              'bytes': source,
              'preserveAlpha': preserveAlpha,
              'maxLongEdge': maxLongEdge,
              'jpegQuality': jpegQuality,
            })
            as Map,
      );
      final bytes = result['bytes'];
      final width = result['width'];
      final height = result['height'];
      final mimeType = result['mimeType'];
      final sha256 = result['sha256'];
      if (bytes is! Uint8List ||
          width is! int ||
          height is! int ||
          mimeType is! String ||
          sha256 is! String ||
          sha256BytesHex(bytes) != sha256.toLowerCase()) {
        throw const WalletImageProcessingException(
          'La respuesta nativa de imagen no es verificable.',
        );
      }
      final normalizedMimeType = mimeType.toLowerCase();
      final extension = switch (normalizedMimeType) {
        'image/png' => 'png',
        'image/jpeg' => 'jpg',
        _ => throw const WalletImageProcessingException(
          'La respuesta nativa tiene un formato no admitido.',
        ),
      };
      final normalizedHash = sha256.toLowerCase();
      return ProcessedWalletImage(
        bytes,
        WalletImageRef.create(
          id: normalizedHash,
          fileName: '$normalizedHash.$extension',
          mimeType: normalizedMimeType,
          sha256: normalizedHash,
          width: width,
          height: height,
          byteLength: bytes.length,
        ),
      );
    } on WalletImageProcessingException {
      rethrow;
    } on PlatformException catch (error) {
      throw WalletImageProcessingException(error.message ?? error.code);
    } on TypeError {
      throw const WalletImageProcessingException(
        'La respuesta nativa de imagen no es válida.',
      );
    }
  }
}
