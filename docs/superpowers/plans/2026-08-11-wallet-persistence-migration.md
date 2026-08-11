# Wallet Persistence and Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persistir el ledger v3, migrar datos legacy de forma idempotente, administrar imágenes privadas y conservar compatibilidad con respaldos locales, Drive y Firebase.

**Architecture:** `AccountingRepository` persiste un `AccountingDocument` canónico. Migración, asignación, ciclo de vida e imágenes son servicios separados. La nube transporta el mismo documento mediante codecs; nunca persiste proyecciones derivadas.

**Tech Stack:** Dart/Flutter, `shared_preferences`, `path_provider`, JSON, Firebase/Drive existentes y Android `BitmapFactory`/`MessageDigest`; sin cambios de dependencias.

## Global Constraints

- Requiere CORE-1 a CORE-6 y aprobación H1.
- Claves legacy siguen siendo legibles; escritura nueva usa esquema 3.
- `virtual:unassigned` es un agrupador de proyección, no una `Wallet` editable.
- IDs nuevos de cartera y movimiento son UUID-v4 sin prefijo; `WalletImageRef.id` usa el SHA-256 normalizado como identificador estable. IDs importados se conservan; sólo faltantes reciben UUID determinista de migración.
- Ninguna migración infiere cartera por plataforma.
- Imágenes se guardan en soporte privado de la app; no tocar activos de tienda/QA.
- Firebase divide imágenes para no depender de un documento grande; local/Drive usan Base64 dentro del backup v3.
- Cada tarea aplica la comparación estructural de analyzer y el límite de 30.

---

### Task PERSIST-1: Definir documento v3 y repositorio SharedPreferences

**Purpose:** Crear una frontera de persistencia comprobable con escritura v3 y lectura sin proyecciones almacenadas.

**Files:**
- Create: `lib/accounting/persistence/accounting_document.dart`
- Create: `lib/accounting/persistence/accounting_repository.dart`
- Create: `lib/accounting/persistence/shared_preferences_accounting_repository.dart`
- Create: `lib/accounting/support/entity_id_generator.dart`
- Create: `test/accounting/persistence/accounting_repository_test.dart`
- Existing symbols affected: `_movementsKey`, `_loadData` (2375) y `_saveData` (2990) sólo como consumidores futuros; no se modifican en esta tarea.

**Consumes:** CORE domain models, `SharedPreferences`, `Random.secure`.

**Produces:**

```dart
const int accountingSchemaVersion = 3;
const String accountingDocumentKey = 'accounting_document_v3';
final class AccountingDocument {
  const AccountingDocument({required this.schemaVersion, required this.wallets,
    required this.movements,
    required this.appliedMigrationIds, required this.updatedAt});
  final int schemaVersion;
  final List<Wallet> wallets;
  final List<AccountingMovement> movements;
  final Set<String> appliedMigrationIds;
  final DateTime updatedAt;
  Map<String, Object?> toJson();
  factory AccountingDocument.fromJson(Map<String, Object?> json);
}
abstract interface class AccountingRepository {
  Future<AccountingDocument?> read();
  Future<void> write(AccountingDocument document);
}
final class EntityIdGenerator {
  const EntityIdGenerator();
  String walletId();
  String movementId();
}
```

**First RED test code:**

```dart
test('repository round-trips only the canonical v3 document', () async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final repository = SharedPreferencesAccountingRepository();
  final document = documentFixture(schemaVersion: 3);
  await repository.write(document);
  expect((await repository.read())!.toJson(), document.toJson());
  final prefs = await SharedPreferences.getInstance();
  expect(prefs.containsKey('movements_json'), isFalse);
});
```

- [ ] **Step 1 — Write RED document test.** Round-trip one wallet with `WalletImageRef` and one internal transfer; assert document schema `3`, wallet schema `1`, exact decimal strings and that no projection/saldo key exists. Run `flutter test test/accounting/persistence/accounting_repository_test.dart`; expected RED: document/repository missing.

- [ ] **Step 2 — Implement `AccountingDocument`.** Validate schema equals 3, sort set output for deterministic JSON, preserve event order as supplied, and reject unknown future schema with `UnsupportedAccountingSchemaException(version)`. Re-run; expect document test GREEN.

- [ ] **Step 3 — Write RED repository test.** Use `SharedPreferences.setMockInitialValues`, write/read twice, assert second write replaces one canonical value and never writes legacy `movements_json`. Run same file; expected RED: repository missing.

- [ ] **Step 4 — Implement repository and UUID-v4 IDs.** JSON-encode under `accounting_document_v3`; use `Random.secure` bytes with RFC-4122 version/variant bits, without prefixes. Add tests for uniqueness over 100 values and canonical UUID shape. Re-run; expect GREEN.

- [ ] **Step 5 — Test malformed input.** Assert typed `AccountingPersistenceException` includes key and cause, while original preference string remains untouched. Implement read-only failure behavior. Run repository tests; expect GREEN.

- [ ] **Step 6 — Verify regressions/analyze.** Format, run persistence/domain tests and full suite, analyzer tuple comparison, diff check.

- [ ] **Step 7 — Commit.** `git add lib/accounting/persistence/accounting_document.dart lib/accounting/persistence/accounting_repository.dart lib/accounting/persistence/shared_preferences_accounting_repository.dart lib/accounting/support/entity_id_generator.dart test/accounting/persistence/accounting_repository_test.dart && git commit -m "feat(accounting): persist canonical schema v3 document"`.

---

### Task PERSIST-2: Migrar legacy idempotentemente sin atribución automática

**Purpose:** Convertir movimientos históricos al documento v3, conservar identidad/historial y representar lo no asignado explícitamente.

**Files:**
- Create: `lib/accounting/migration/accounting_migrator.dart`
- Create: `lib/accounting/migration/migration_report.dart`
- Create: `test/accounting/migration/accounting_migrator_test.dart`
- Modify: `lib/accounting/adapters/legacy_movement_adapter.dart`
- Existing symbols affected: `Movement.fromJson` (25093), `_movementsKey` and legacy JSON shape.

**Consumes:** `LegacyMovementAdapter`, raw legacy list, optional existing `AccountingDocument`.

**Produces:**

```dart
const String legacyUnassignedWalletId = 'virtual:unassigned';
const String legacyV1ToV3MigrationId = 'legacy-movements-v1-to-accounting-v3';
final class MigrationReport {
  const MigrationReport({required this.document, required this.imported,
    required this.skippedDuplicates, required this.unassignedMovementIds});
  final AccountingDocument document;
  final int imported;
  final int skippedDuplicates;
  final List<String> unassignedMovementIds;
}
final class AccountingMigrator {
  const AccountingMigrator(this.adapter);
  MigrationReport migrateLegacy({required List<Map<String, Object?>> legacy,
    AccountingDocument? existing});
}
```

**First RED test code:**

```dart
test('migration keeps legacy movements explicitly unassigned', () {
  final result = migrator.migrateLegacy(legacy: <Map<String, Object?>>[
    legacyBuy(id: 'old-1', platform: 'Mercado Pago'),
  ]);
  expect(result.document.wallets, isEmpty);
  expect(result.document.movements.single.walletAssignmentStatus,
      WalletAssignmentStatus.legacyUnassigned);
  expect(result.unassignedMovementIds, <String>['old-1']);
});
```

- [ ] **Step 1 — Write RED legacy-unassigned test.** Feed buy, sell and old transfer JSON containing platform/wallet text; assert all converted events have `legacyUnassigned`, no real wallet is created, platform text is preserved only as legacy/external metadata, and projection key is `virtual:unassigned`. Run `flutter test test/accounting/migration/accounting_migrator_test.dart`; expected RED: migrator missing.

- [ ] **Step 2 — Implement field-preserving conversion.** Use original ID where present; otherwise derive a deterministic RFC-4122-shaped UUID from SHA-256 of canonical legacy JSON, setting version/variant bits, through `lib/accounting/support/sha256.dart` because no dependency may be added. Extend `AccountingDocument` with `Map<String, Map<String, Object?>> legacyMovementMetadata`, keyed by movement ID, and JSON key `legacyMovementMetadata`; store all `LegacyMovementConversion.preservedFields` there. Preserve timestamps, fees, network, note, deleted/device/platform fields. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED idempotency test.** Migrate the same list twice over the first result; assert byte-identical canonical JSON, imported second pass `0`, duplicates count equals input, and migration ID appears once. Run test; expected RED before guard/dedupe.

- [ ] **Step 4 — Implement dedupe and report.** Dedupe by movement ID; if same ID has different canonical payload, throw `MigrationConflictException(id)` and retain both source inputs externally for audit. Never silently overwrite. Re-run; expect GREEN.

- [ ] **Step 5 — Cover legacy global policy.** Assert `LegacyAccountingPolicy.preservePreviousGlobal` is recorded in migrated metadata and legacy aggregate output matches the adapter before assignment. Add the policy field to `AccountingDocument` with exact JSON key `legacyAccountingPolicy`. Run migration and repository tests; expect GREEN.

- [ ] **Step 6 — Verify regression/analyze.** Format, migration/persistence/adapter tests, full suite, analyzer tuple comparison and diff check.

- [ ] **Step 7 — Commit.** Include `lib/accounting/support/sha256.dart` and its direct tests in the add list: `git add lib/accounting/migration lib/accounting/support/sha256.dart lib/accounting/persistence/accounting_document.dart lib/accounting/adapters/legacy_movement_adapter.dart test/accounting/migration test/accounting/support/sha256_test.dart && git commit -m "feat(accounting): migrate legacy movements idempotently"`.

---

### Task PERSIST-2B: Mantener una vista legacy coherente durante el rollout

**Purpose:** Mantener la vista en memoria `List<Movement>` sincronizada con el documento v3 sin volver a escribir la clave legacy.

**Files:**
- Create: `lib/accounting/adapters/legacy_persistence_bridge.dart`
- Create: `test/accounting/adapters/legacy_persistence_bridge_test.dart`
- Modify: `lib/cripto_control_app.dart`
- Existing symbols affected: `_loadData` (2375), `_saveData` (2990), `_movementsKey` y `_movements`; no se reestructura el resto del estado.

**Consumes:** `AccountingRepository`, `AccountingMigrator`, `LegacyMovementAdapter`, current legacy JSON list.

**Produces:**

```dart
final class AccountingLoadResult {
  const AccountingLoadResult({required this.document,
    required this.legacyView, required this.migrationReport});
  final AccountingDocument document;
  final List<Map<String, Object?>> legacyView;
  final MigrationReport? migrationReport;
}
final class LegacyPersistenceBridge {
  const LegacyPersistenceBridge(this.repository, this.migrator, this.adapter);
  Future<AccountingLoadResult> load(List<Map<String, Object?>> legacySource);
  Future<AccountingDocument> saveLegacyView(AccountingDocument current,
    List<Map<String, Object?>> legacyView,
    {Set<String> deletedIds = const <String>{}});
}
```

**First RED test code:**

```dart
test('legacy-view save preserves v3 wallet fields without dual persistence', () async {
  final current = assignedDocumentFixture();
  final legacy = adapter.toLegacyJson(current.movements.single,
      preservedFields: current.legacyMovementMetadata['old-1']!)
    ..['note'] = 'nota editada';
  final saved = await bridge.saveLegacyView(
      current, <Map<String, Object?>>[legacy]);
  expect(saved.movements.single.note, 'nota editada');
  expect(saved.movements.single.destinationWalletId,
      '11111111-1111-4111-8111-111111111111');
  expect(saved.wallets, current.wallets);
});
```

- [ ] **Step 1 — Write RED bootstrap test.** With no v3 key and one legacy JSON event, call `load`; assert migration runs once, repository receives v3 and legacy view retains current UI fields. Run `flutter test test/accounting/adapters/legacy_persistence_bridge_test.dart`; expected RED: bridge missing.

- [ ] **Step 2 — Implement load precedence.** If v3 exists, it is authoritative and legacy source is ignored except for compatibility diagnostics; otherwise migrate then write v3 before returning. Never infer wallets.

- [ ] **Step 3 — Write RED legacy-view preservation test shown above.** Also change date/quantity/fee in legacy view; assert merge by ID updates common fields while preserving assignment, destination type, adjustment/link, wallet `imageRef` and `legacyMovementMetadata`. Assert only `accounting_document_v3` is written. Run test; expected RED before merge.

- [ ] **Step 4 — Implement merge with conflict checks.** Existing canonical ID is updated field-by-field through adapter; new legacy ID is converted unassigned; missing legacy IDs are retained unless caller supplies explicit `deletedIds`. Re-run; expect GREEN.

- [ ] **Step 5 — Integrate narrowly.** `_loadData` supplies decoded legacy maps to bridge only when v3 is absent and sets `_movements` with `legacyView.map(Movement.fromJson)`; `_saveData` supplies `_movements.map((value) => value.toJson())` to the bridge and writes only `accounting_document_v3`. Store the in-memory `AccountingDocument` field; do not alter unrelated settings/timers/cloud code. The bridge and accounting libraries never import the monolith.

- [ ] **Step 6 — Verify regression/analyze.** Run bridge, migration, current persistence/widget tests, full suite, analyzer tuple comparison and diff check. Inspect only `_loadData`/`_saveData` monolith hunks.

- [ ] **Step 7 — Commit.** `git add lib/accounting/adapters/legacy_persistence_bridge.dart lib/cripto_control_app.dart test/accounting/adapters/legacy_persistence_bridge_test.dart && git commit -m "feat(accounting): bridge legacy view to v3 persistence"`.

---

### Task PERSIST-3: Asignar movimientos individual y masivamente

**Purpose:** Justificar movimientos legacy mediante cambios explícitos, auditables e idempotentes sin duplicar tenencia.

**Files:**
- Create: `lib/accounting/application/movement_assignment_service.dart`
- Create: `lib/accounting/domain/assignment_audit.dart`
- Create: `test/accounting/application/movement_assignment_service_test.dart`
- Modify: `lib/accounting/persistence/accounting_document.dart`
- Existing symbols affected: none in monolith.

**Consumes:** `AccountingDocument`, wallet ID real, movement IDs, `AccountingLedgerEngine`.

**Produces:**

```dart
final class AssignmentAudit {
  const AssignmentAudit({required this.id, required this.movementId,
    required this.walletId, required this.assignedAt,
    required this.previousStatus});
  final String id;
  final String movementId;
  final String walletId;
  final DateTime assignedAt;
  final WalletAssignmentStatus previousStatus;
}
final class AssignmentResult {
  const AssignmentResult({required this.document, required this.changedIds,
    required this.unchangedIds});
  final AccountingDocument document;
  final List<String> changedIds;
  final List<String> unchangedIds;
}
final class MovementAssignmentService {
  AssignmentResult assignOne(AccountingDocument document,
    {required String movementId, required String walletId,
    required DateTime assignedAt});
  AssignmentResult assignMany(AccountingDocument document,
    {required Set<String> movementIds, required String walletId,
    required DateTime assignedAt});
}
```

**First RED test code:**

```dart
test('assignOne replaces the event without duplicating custody', () {
  final before = legacyDocumentFixture();
  final result = service.assignOne(before, movementId: 'old-1',
      walletId: '11111111-1111-4111-8111-111111111111',
      assignedAt: DateTime.utc(2026, 8, 11));
  expect(result.document.movements, hasLength(before.movements.length));
  expect(result.document.movements.single.destinationWalletId,
      '11111111-1111-4111-8111-111111111111');
  expect(project(result.document).totalCustody, project(before).totalCustody);
});
```

- [ ] **Step 1 — Write RED single-assignment test.** Assign one legacy buy; assert same movement ID/quantity, `sourceWalletId` set, status `assigned`, one audit record, no duplicate and unchanged aggregate custody. Run `flutter test test/accounting/application/movement_assignment_service_test.dart`; expected RED: service missing.

- [ ] **Step 2 — Implement event replacement, not event insertion.** Replace the matching event in place, update timestamp/status and append an audit entry. Type mapping is exact: `buy` and external `transferIn` assign `destinationWalletId`; `sell` and `transferOut` assign `sourceWalletId`; `balanceAdjustment` assigns `adjustmentWalletId`; an internal transfer must already have both owned IDs and is rejected by this legacy assignment command. Validate target is an active real wallet. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED mass-assignment test.** Select two of three IDs; assert exactly two changed, third stays pending, progress is `2/3`, ordering remains deterministic. Run test; expected RED: batch behavior absent.

- [ ] **Step 4 — Implement `assignMany` as one validated transaction.** Validate all IDs/wallet before changing any; fold through the same private `assign` primitive; return sorted changed/unchanged IDs. Re-run; expect GREEN.

- [ ] **Step 5 — Test reattempt/conflicts.** Same assignment twice is unchanged and creates no second audit; different-wallet reassignment requires explicit `allowReassignment: true` and records previous wallet in audit. Add exact optional parameter to both methods. Run tests; expect GREEN.

- [ ] **Step 6 — Verify projection/analyze.** Compare projections before/after assignment to ensure attribution changes but global totals do not; run accounting suite, full suite, analyzer comparison and diff check.

- [ ] **Step 7 — Commit.** `git add lib/accounting/application/movement_assignment_service.dart lib/accounting/domain/assignment_audit.dart lib/accounting/persistence/accounting_document.dart test/accounting/application/movement_assignment_service_test.dart && git commit -m "feat(accounting): assign legacy movements explicitly"`.

---

### Task PERSIST-4: Procesar y almacenar imágenes privadas sin dependencia nueva

**Purpose:** Normalizar imágenes de cartera con límite de 1024 px, formato/compresión definidos y hash verificable en almacenamiento privado.

**Files:**
- Create: `lib/accounting/persistence/wallet_image_processor.dart`
- Create: `lib/accounting/persistence/wallet_image_store.dart`
- Create: `lib/accounting/persistence/method_channel_wallet_image_processor.dart`
- Create: `android/app/src/main/kotlin/mx/criptocontrolmx/app/WalletImageChannel.kt`
- Modify: `android/app/src/main/kotlin/mx/criptocontrolmx/app/MainActivity.kt`
- Create: `test/accounting/persistence/wallet_image_service_test.dart`
- Existing symbols affected: `MainActivity.configureFlutterEngine` only; existing price-alert channel remains intact.

**Consumes:** input bytes, `getApplicationSupportDirectory()`, Android channel `mx.criptocontrolmx.app/wallet_images`.

**Produces:**

```dart
final class ProcessedWalletImage {
  const ProcessedWalletImage(this.bytes, this.imageRef);
  final Uint8List bytes;
  final WalletImageRef imageRef;
}
abstract interface class WalletImageProcessor {
  Future<ProcessedWalletImage> process(Uint8List source,
    {required bool preserveAlpha, int maxLongEdge = 1024,
    int jpegQuality = 82});
}
abstract interface class WalletImageStore {
  Future<void> write(ProcessedWalletImage image);
  Future<Uint8List> read(String imageId);
  Future<void> deleteIfUnreferenced(String imageId, Set<String> referencedIds);
}
```

**First RED test code:**

```dart
test('private store verifies hash and never persists an absolute path', () async {
  final image = processedPngFixture(bytes: <int>[137, 80, 78, 71]);
  await store.write(image);
  expect(await store.read(image.metadata.id), image.bytes);
  expect(image.imageRef.fileName, startsWith('wallet_images/'));
  expect(image.imageRef.fileName.contains(':'), isFalse);
  expect(image.imageRef.fileName.startsWith('/'), isFalse);
});
```

- [ ] **Step 1 — Write RED service contract test.** Use a fake processor returning known PNG bytes/metadata; write/read in a temporary directory and assert relative path stays below `wallet_images/`, SHA matches and no absolute path enters JSON. Run `flutter test test/accounting/persistence/wallet_image_service_test.dart`; expected RED: contracts/store missing.

- [ ] **Step 2 — Implement metadata and private store.** Resolve and validate canonical paths under application-support root; atomic write via temporary sibling then rename; delete only when the supplied reference set excludes the ID. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED channel contract test.** Mock `MethodChannel` and assert method `process`, arguments `bytes`, `preserveAlpha`, `maxLongEdge: 1024`, `jpegQuality: 82`; decode returned bytes, width, height, MIME and SHA. Run test; expected RED: adapter missing.

- [ ] **Step 4 — Implement Dart channel and Kotlin processor.** Kotlin uses `BitmapFactory.decodeByteArray`, scales preserving aspect ratio only when long edge exceeds 1024, encodes alpha images as PNG and opaque as JPEG quality 82, computes SHA-256 with `MessageDigest`, and returns a map. Register a second channel in `configureFlutterEngine` without changing alert handling.

- [ ] **Step 5 — Add native boundary tests.** In Dart, assert corrupt bytes surface `WalletImageProcessingException`; alpha/opaque response fixtures choose `.png`/`.jpg`; hash mismatch is rejected before storage. Run test; expect RED then GREEN.

- [ ] **Step 6 — Verify compilation/analyze.** Run image tests, full suite, analyzer tuple comparison, `flutter build apk --debug` solely as native compile check, and diff check. Confirm generated APK remains untracked/ignored and do not copy it.

- [ ] **Step 7 — Commit.** `git add lib/accounting/persistence/wallet_image_processor.dart lib/accounting/persistence/wallet_image_store.dart lib/accounting/persistence/method_channel_wallet_image_processor.dart android/app/src/main/kotlin/mx/criptocontrolmx/app/WalletImageChannel.kt android/app/src/main/kotlin/mx/criptocontrolmx/app/MainActivity.kt test/accounting/persistence/wallet_image_service_test.dart && git commit -m "feat(wallets): store normalized private images"`.

---

### Task PERSIST-5: Respaldar y restaurar documento e imágenes local/Drive/Firebase

**Purpose:** Transportar el documento v3 completo sin romper rutas de respaldo existentes ni exceder límites de documento de nube.

**Files:**
- Create: `lib/accounting/io/accounting_backup_codec.dart`
- Create: `lib/accounting/io/cloud_image_chunks.dart`
- Create: `test/accounting/io/accounting_backup_codec_test.dart`
- Modify: `lib/cripto_control_app.dart`
- Existing symbols affected: `_buildBackupJson` (4291), `_applyBackupJson` (5064), subida/restauración Firebase (1410, 1611), Drive/local (2085, 2249, 4919).

**Consumes:** `AccountingDocument`, `WalletImageStore`, existing backup map (`settings`, `currentPrices`, `movements`, `snapshots`).

**Produces:**

```dart
final class AccountingBackupCodec {
  Future<Map<String, Object?>> encodeV3(AccountingDocument document,
    WalletImageStore images);
  Future<AccountingDocument> decodeAny(Map<String, Object?> json,
    WalletImageStore images);
}
final class CloudImageManifest {
  const CloudImageManifest({required this.imageId, required this.sha256,
    required this.chunkCount, required this.byteLength});
}
List<Uint8List> splitCloudImage(Uint8List bytes, {int chunkBytes = 600000});
Uint8List joinCloudImage(CloudImageManifest manifest, List<Uint8List> chunks);
```

**First RED test code:**

```dart
test('backup restores image bytes only after SHA-256 validation', () async {
  final source = documentWithImageFixture();
  final encoded = await codec.encodeV3(source, sourceImages);
  final restored = await codec.decodeAny(encoded, targetImages);
  expect(restored.toJson(), source.toJson());
  final imageId = source.wallets.single.imageRef!.id;
  expect(await targetImages.read(imageId), await sourceImages.read(imageId));
});
```

- [ ] **Step 1 — Write RED v3 backup round-trip.** Encode a document with one image; assert top-level `schemaVersion` is 3 and keys `wallets`, `walletImages`, `movements`, `snapshots`, `currentPrices`, `settings` exist; image Base64 decodes to the same SHA; adjustment reason/date/wallet/asset/quantity/observed balance/note survive. Run `flutter test test/accounting/io/accounting_backup_codec_test.dart`; expected RED: codec missing.

- [ ] **Step 2 — Implement local/Drive codec.** Emit the approved top-level v3 shape; each `movements` row merges preserved historical fields from `legacyMovementMetadata` with canonical v3 fields through `LegacyMovementAdapter`, and `walletImages` contains `WalletImageRef` metadata plus Base64 bytes. Decode `schemaVersion: 3` preferentially, separating preserved metadata from canonical fields, and route v1/v2 shapes through `AccountingMigrator`. Validate hashes before private-store writes. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED Firebase chunk test.** Split bytes larger than 1,200,000; assert deterministic indices, manifest counts/size/hash; shuffled chunks rejoin by index; missing/duplicate chunks fail without changing store. Run codec test; expected RED before chunk functions.

- [ ] **Step 4 — Implement chunk transport adapters.** Main document stores manifests; Firestore subcollection path is `cloudState/current/walletImageChunks/{imageId}:{index}`. Restore all chunks to memory, validate then commit document/images; rollback temp files on error. Re-run; expect GREEN.

- [ ] **Step 5 — Integrate narrowly with existing methods.** `_buildBackupJson` delegates top-level v3 construction; `_applyBackupJson` stages decode before state replacement; Firebase/Drive continue using existing authentication and payload flow. Do not restructure the surrounding methods. Add regression tests for v2 backup import and v3 image-free backup.

- [ ] **Step 6 — Verify compatibility/analyze.** Run codec, migration, current backup-related tests, full suite, analyzer tuple comparison and diff check. Manually inspect `git diff -- lib/cripto_control_app.dart` for scoped edits only.

- [ ] **Step 7 — Commit.** `git add lib/accounting/io/accounting_backup_codec.dart lib/accounting/io/cloud_image_chunks.dart lib/cripto_control_app.dart test/accounting/io/accounting_backup_codec_test.dart && git commit -m "feat(accounting): back up schema v3 with wallet images"`.

---

### Task PERSIST-6: Aplicar ciclo de vida seguro de carteras

**Purpose:** Permitir archivar/restaurar y bloquear eliminación destructiva cuando existe historial o referencias.

**Files:**
- Create: `lib/accounting/application/wallet_lifecycle_service.dart`
- Create: `test/accounting/application/wallet_lifecycle_service_test.dart`
- Modify: `lib/accounting/persistence/accounting_document.dart`
- Existing symbols affected: none in monolith.

**Consumes:** `AccountingDocument`, wallet ID, current time.

**Produces:**

```dart
enum WalletDeleteBlockReason { movementHistory, reconciliationLink }
final class WalletDeleteResult {
  const WalletDeleteResult({required this.document, required this.deleted,
    required this.blockReasons});
  final AccountingDocument document;
  final bool deleted;
  final Set<WalletDeleteBlockReason> blockReasons;
}
final class WalletLifecycleService {
  AccountingDocument archive(AccountingDocument document, String walletId,
    DateTime updatedAt);
  AccountingDocument restore(AccountingDocument document, String walletId,
    DateTime updatedAt);
  WalletDeleteResult deleteEmpty(AccountingDocument document, String walletId);
  AccountingDocument reassignAndDelete(AccountingDocument document,
    {required String sourceWalletId, required String targetWalletId,
    required DateTime updatedAt});
}
```

**First RED test code:**

```dart
test('wallet with movement history is archived, never deleted', () {
  final document = documentWithWalletHistory();
  const walletId = '11111111-1111-4111-8111-111111111111';
  final deletion = service.deleteEmpty(document, walletId);
  expect(deletion.deleted, isFalse);
  expect(deletion.blockReasons, contains(WalletDeleteBlockReason.movementHistory));
  final archived = service.archive(document, walletId, clock);
  expect(archived.wallets.single.status, WalletStatus.archived);
  expect(archived.movements, document.movements);
});
```

- [ ] **Step 1 — Write RED archive/restore test.** Archive wallet with movements; assert history/projections remain, status/updatedAt change, it is excluded only from active selection; restore reverses status without changing IDs/events. Run `flutter test test/accounting/application/wallet_lifecycle_service_test.dart`; expected RED: service missing.

- [ ] **Step 2 — Implement immutable lifecycle transitions.** Replace only the wallet record and document `updatedAt`; reject virtual/unknown IDs. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED destructive-delete tests.** Cover blockers: source/destination/adjustment wallet reference and reconciliation link. Assert document byte-equivalent and all block reasons returned. Also prove an empty wallet with an image can be deleted and its now-unreferenced image is scheduled for cleanup. Run test; expected RED: delete guard absent.

- [ ] **Step 4 — Implement reference scan.** Inspect canonical movement fields and links; do not rely on projections or platform names. Permit deletion only for an empty wallet, schedule its unreferenced image file for deletion, and delegate physical deletion after repository commit succeeds. Re-run; expect GREEN.

- [ ] **Step 5 — Test atomic reassignment and repository failure ordering.** `reassignAndDelete` replaces every source/destination/adjustment reference in one document, rejects a rewrite that would create a same-wallet internal transfer, rebuilds projections before commit and then removes the source wallet. Fake repository throws during commit; assert original document/image remain and caller receives error. Add application coordinator `Future<WalletDeleteResult> commitDelete(...)` with repository/store dependencies. Run tests; expect GREEN.

- [ ] **Step 6 — Verify and prepare H2.** Run all persistence/migration/I/O accounting tests, full suite, analyzer tuple comparison and diff check. Present document v3, migration report, image privacy/hash and lifecycle evidence at H2.

- [ ] **Step 7 — Commit.** `git add lib/accounting/application/wallet_lifecycle_service.dart lib/accounting/persistence/accounting_document.dart test/accounting/application/wallet_lifecycle_service_test.dart && git commit -m "feat(wallets): protect wallet lifecycle history"`.
