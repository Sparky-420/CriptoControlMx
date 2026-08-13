import 'dart:typed_data';

import '../support/sha256.dart';

final class CloudImageManifest {
  const CloudImageManifest({
    required this.imageId,
    required this.sha256,
    required this.chunkCount,
    required this.byteLength,
  });

  final String imageId;
  final String sha256;
  final int chunkCount;
  final int byteLength;

  Map<String, Object?> toJson() => <String, Object?>{
    'imageId': imageId,
    'sha256': sha256,
    'chunkCount': chunkCount,
    'byteLength': byteLength,
  };

  factory CloudImageManifest.fromJson(Map<String, Object?> json) =>
      CloudImageManifest(
        imageId: json['imageId']! as String,
        sha256: json['sha256']! as String,
        chunkCount: json['chunkCount']! as int,
        byteLength: json['byteLength']! as int,
      );
}

final class CloudImageChunk {
  const CloudImageChunk({
    required this.imageId,
    required this.index,
    required this.bytes,
  });

  final String imageId;
  final int index;
  final Uint8List bytes;
}

List<CloudImageChunk> splitCloudImage(
  String imageId,
  Uint8List bytes, {
  int chunkBytes = 600000,
}) {
  if (imageId.trim().isEmpty) {
    throw ArgumentError.value(imageId, 'imageId', 'No puede estar vacío.');
  }
  if (chunkBytes <= 0) {
    throw ArgumentError.value(chunkBytes, 'chunkBytes', 'Debe ser positivo.');
  }
  final chunks = <CloudImageChunk>[];
  for (var offset = 0; offset < bytes.length; offset += chunkBytes) {
    final end = offset + chunkBytes < bytes.length
        ? offset + chunkBytes
        : bytes.length;
    chunks.add(
      CloudImageChunk(
        imageId: imageId,
        index: chunks.length,
        bytes: Uint8List.fromList(bytes.sublist(offset, end)),
      ),
    );
  }
  return chunks;
}

Uint8List joinCloudImage(
  CloudImageManifest manifest,
  List<CloudImageChunk> chunks,
) {
  if (manifest.imageId.trim().isEmpty ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(manifest.sha256) ||
      manifest.chunkCount < 0 ||
      manifest.byteLength < 0 ||
      chunks.length != manifest.chunkCount) {
    throw const FormatException('Manifest de imagen cloud inválido.');
  }
  final ordered = List<CloudImageChunk>.of(chunks)
    ..sort((left, right) => left.index.compareTo(right.index));
  for (var index = 0; index < ordered.length; index++) {
    final chunk = ordered[index];
    if (chunk.imageId != manifest.imageId || chunk.index != index) {
      throw const FormatException('Chunks de imagen cloud inválidos.');
    }
  }
  final builder = BytesBuilder(copy: false);
  for (final chunk in ordered) {
    builder.add(chunk.bytes);
  }
  final result = builder.takeBytes();
  if (result.length != manifest.byteLength ||
      sha256BytesHex(result) != manifest.sha256) {
    throw const FormatException('La imagen cloud no coincide con el manifest.');
  }
  return result;
}
