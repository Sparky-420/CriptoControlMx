import 'accounting_document.dart';

const String accountingDocumentKey = 'accounting_document_v3';

abstract interface class AccountingRepository {
  Future<AccountingDocument?> read();
  Future<void> write(AccountingDocument document);
  Future<void> clear();
}

final class AccountingPersistenceException implements Exception {
  const AccountingPersistenceException({
    required this.key,
    required this.cause,
  });

  final String key;
  final Object cause;

  @override
  String toString() => 'Accounting persistence failed for $key: $cause';
}
