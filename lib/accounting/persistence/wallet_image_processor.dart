import 'dart:typed_data';

import '../domain/wallet.dart';

final class ProcessedWalletImage {
  const ProcessedWalletImage(this.bytes, this.imageRef);

  final Uint8List bytes;
  final WalletImageRef imageRef;
}

abstract interface class WalletImageProcessor {
  Future<ProcessedWalletImage> process(
    Uint8List source, {
    required bool preserveAlpha,
    int maxLongEdge = 1024,
    int jpegQuality = 82,
  });
}
