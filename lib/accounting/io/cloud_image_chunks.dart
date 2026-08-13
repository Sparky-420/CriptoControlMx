import 'dart:typed_data';

import '../support/sha256.dart';

const int maxCloudImageChunkWritesPerBatch = 10;
const int maxCloudImageChunkDeletesPerBatch = 400;

enum CloudImageUploadPhase { writeChunks, publishCurrent, deleteStaleChunks }

final class CloudImageUploadPlan {
  const CloudImageUploadPlan({
    required this.chunkWriteBatches,
    required this.staleChunkDeleteBatches,
  });

  final List<List<CloudImageChunk>> chunkWriteBatches;
  final List<List<String>> staleChunkDeleteBatches;

  List<CloudImageUploadPhase> get phases => const <CloudImageUploadPhase>[
    CloudImageUploadPhase.writeChunks,
    CloudImageUploadPhase.publishCurrent,
    CloudImageUploadPhase.deleteStaleChunks,
  ];
}

typedef CloudImageChunkBatchWriter =
    Future<void> Function(List<CloudImageChunk> chunks);
typedef CloudImageCurrentPublisher = Future<void> Function();
typedef CloudImageStaleChunkBatchDeleter =
    Future<void> Function(List<String> chunkIds);

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

CloudImageUploadPlan planCloudImageUpload(
  List<CloudImageChunk> chunks,
  Iterable<String> priorChunkIds,
) {
  final newChunkIds = <String>{
    for (final chunk in chunks) '${chunk.imageId}:${chunk.index}',
  };
  final staleIds = priorChunkIds
      .where((id) => !newChunkIds.contains(id))
      .toList(growable: false);
  return CloudImageUploadPlan(
    chunkWriteBatches: _partition(chunks, maxCloudImageChunkWritesPerBatch),
    staleChunkDeleteBatches: _partition(
      staleIds,
      maxCloudImageChunkDeletesPerBatch,
    ),
  );
}

Future<void> executeCloudImageUploadPlan(
  CloudImageUploadPlan plan, {
  required CloudImageChunkBatchWriter writeChunkBatch,
  required CloudImageCurrentPublisher publishCurrent,
  required CloudImageStaleChunkBatchDeleter deleteStaleChunkBatch,
}) async {
  for (final batch in plan.chunkWriteBatches) {
    await writeChunkBatch(batch);
  }
  await publishCurrent();
  for (final batch in plan.staleChunkDeleteBatches) {
    await deleteStaleChunkBatch(batch);
  }
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

List<List<T>> _partition<T>(List<T> values, int maximumLength) {
  final result = <List<T>>[];
  for (var start = 0; start < values.length; start += maximumLength) {
    final end = start + maximumLength < values.length
        ? start + maximumLength
        : values.length;
    result.add(List<T>.unmodifiable(values.sublist(start, end)));
  }
  return List<List<T>>.unmodifiable(result);
}
