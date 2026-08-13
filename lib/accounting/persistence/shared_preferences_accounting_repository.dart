import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'accounting_document.dart';
import 'accounting_repository.dart';

typedef PreferenceStringWriter =
    Future<bool> Function(
      SharedPreferences preferences,
      String key,
      String value,
    );

typedef PreferenceRemover =
    Future<bool> Function(SharedPreferences preferences, String key);

final class SharedPreferencesAccountingRepository
    implements AccountingRepository {
  SharedPreferencesAccountingRepository({
    Future<SharedPreferences>? preferences,
    PreferenceStringWriter? writeString,
    PreferenceRemover? remove,
  }) : _preferences = preferences ?? SharedPreferences.getInstance(),
       _writeString = writeString ?? _defaultWriteString,
       _remove = remove ?? _defaultRemove;

  final Future<SharedPreferences> _preferences;
  final PreferenceStringWriter _writeString;
  final PreferenceRemover _remove;

  @override
  Future<AccountingDocument?> read() async {
    final preferences = await _preferences;
    try {
      final encoded = preferences.getString(accountingDocumentKey);
      if (encoded == null) {
        return null;
      }
      return AccountingDocument.fromJson(
        Map<String, Object?>.from(jsonDecode(encoded) as Map),
      );
    } catch (error) {
      throw AccountingPersistenceException(
        key: accountingDocumentKey,
        cause: error,
      );
    }
  }

  @override
  Future<void> write(AccountingDocument document) async {
    final preferences = await _preferences;
    try {
      final wrote = await _writeString(
        preferences,
        accountingDocumentKey,
        jsonEncode(document.toJson()),
      );
      if (!wrote) {
        throw StateError('SharedPreferences rejected the canonical write.');
      }
    } catch (error) {
      throw AccountingPersistenceException(
        key: accountingDocumentKey,
        cause: error,
      );
    }
  }

  @override
  Future<void> clear() async {
    final preferences = await _preferences;
    try {
      final removed = await _remove(preferences, accountingDocumentKey);
      if (!removed) {
        throw StateError('SharedPreferences rejected canonical removal.');
      }
    } catch (error) {
      throw AccountingPersistenceException(
        key: accountingDocumentKey,
        cause: error,
      );
    }
  }

  static Future<bool> _defaultWriteString(
    SharedPreferences preferences,
    String key,
    String value,
  ) => preferences.setString(key, value);

  static Future<bool> _defaultRemove(
    SharedPreferences preferences,
    String key,
  ) => preferences.remove(key);
}
