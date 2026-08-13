import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/wallet.dart';
import 'wallet_lifecycle_service.dart';

const String walletImageCleanupJournalKey = 'wallet_image_cleanup_journal_v1';

abstract interface class WalletImageCleanupJournal {
  Future<List<WalletImageCleanupIntent>> readAll();

  Future<void> replaceAll(List<WalletImageCleanupIntent> intents);
}

final class SharedPreferencesWalletImageCleanupJournal
    implements WalletImageCleanupJournal {
  const SharedPreferencesWalletImageCleanupJournal(this.preferences);

  final SharedPreferences preferences;

  @override
  Future<List<WalletImageCleanupIntent>> readAll() async {
    final encoded = preferences.getString(walletImageCleanupJournalKey);
    if (encoded == null) return const <WalletImageCleanupIntent>[];
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const FormatException('Invalid wallet image cleanup journal.');
    }
    return decoded
        .map(
          (value) => _intentFromJson(Map<String, Object?>.from(value as Map)),
        )
        .toList(growable: false);
  }

  @override
  Future<void> replaceAll(List<WalletImageCleanupIntent> intents) async {
    final byId = <String, WalletImageCleanupIntent>{};
    for (final intent in intents) {
      byId[intent.id] = intent;
    }
    final ids = byId.keys.toList()..sort();
    final encoded = jsonEncode(<Map<String, Object?>>[
      for (final id in ids) _intentToJson(byId[id]!),
    ]);
    if (!await preferences.setString(walletImageCleanupJournalKey, encoded)) {
      throw StateError('Wallet image cleanup journal could not be persisted.');
    }
  }
}

Map<String, Object?> _intentToJson(WalletImageCleanupIntent intent) =>
    <String, Object?>{
      'id': intent.id,
      'sourceWalletId': intent.sourceWalletId,
      'imageRef': intent.imageRef.toJson(),
      'createdAt': intent.createdAt.toIso8601String(),
    };

WalletImageCleanupIntent _intentFromJson(Map<String, Object?> json) =>
    WalletImageCleanupIntent(
      id: json['id']! as String,
      sourceWalletId: json['sourceWalletId']! as String,
      imageRef: WalletImageRef.fromJson(
        Map<String, Object?>.from(json['imageRef']! as Map),
      ),
      createdAt: DateTime.parse(json['createdAt']! as String),
    );
