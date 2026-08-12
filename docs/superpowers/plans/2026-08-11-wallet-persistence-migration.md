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
- `WalletImageRef.fileName` conserva únicamente un nombre base seguro. El
  directorio privado `wallet_images/` y cualquier ruta interna del respaldo son
  responsabilidades de sus adaptadores y nunca se copian a la referencia durable.
- Las asignaciones se expresan mediante comandos tipados por lado; la ausencia
  de un comando significa “no modificar” y ningún `null` representa a la vez
  asignación, borrado y clasificación externa.
- La limpieza de imágenes posterior a una eliminación usa un journal operativo
  local durable y se ejecuta sólo después del commit del documento v3.
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
  Future<void> clear();
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

- [ ] **Step 3 — Write RED repository test.** Use `SharedPreferences.setMockInitialValues`, write/read twice, assert second write replaces one canonical value and never writes legacy `movements_json`. Call `clear` and assert only `accounting_document_v3` is removed; legacy keys and unrelated preferences remain untouched. Run same file; expected RED: repository missing.

- [ ] **Step 4 — Implement repository and UUID-v4 IDs.** JSON-encode under `accounting_document_v3`; `clear` calls `remove(accountingDocumentKey)` exclusively and exists only for transactional compensation/recovery. Use `Random.secure` bytes with RFC-4122 version/variant bits, without prefixes. Add tests for uniqueness over 100 values and canonical UUID shape. Re-run; expect GREEN.

- [ ] **Step 5 — Test malformed input.** Assert typed `AccountingPersistenceException` includes key and cause, while original preference string remains untouched. Implement read-only failure behavior. Run repository tests; expect GREEN.

- [ ] **Step 6 — Verify regressions/analyze.** Format, run persistence/domain tests and full suite, analyzer tuple comparison, diff check.

- [ ] **Step 7 — Commit.** `git add lib/accounting/persistence/accounting_document.dart lib/accounting/persistence/accounting_repository.dart lib/accounting/persistence/shared_preferences_accounting_repository.dart lib/accounting/support/entity_id_generator.dart test/accounting/persistence/accounting_repository_test.dart && git commit -m "feat(accounting): persist canonical schema v3 document"`.

---

### Task PERSIST-2: Migrar legacy idempotentemente sin atribución automática

**Purpose:** Convertir movimientos históricos al documento v3, conservar identidad/historial y representar lo no asignado explícitamente.

**Files:**
- Create: `lib/accounting/migration/accounting_migrator.dart`
- Create: `lib/accounting/migration/migration_report.dart`
- Create: `lib/accounting/migration/legacy_migration_problem.dart`
- Create: `lib/accounting/support/sha256.dart`
- Create: `test/accounting/migration/accounting_migrator_test.dart`
- Create: `test/accounting/support/sha256_test.dart`
- Modify: `test/accounting/persistence/accounting_repository_test.dart`
- Modify: `lib/accounting/adapters/legacy_movement_adapter.dart`
- Existing symbols affected: `Movement.fromJson` (25093), `_movementsKey` and legacy JSON shape.

**Consumes:** `LegacyMovementAdapter`, raw legacy list, optional existing `AccountingDocument`.

**Produces:**

```dart
const String legacyV1ToV3MigrationId = 'legacy-movements-v1-to-accounting-v3';
enum LegacyMigrationProblemKind { unconvertible, conflictingId }
final class LegacyMigrationProblem {
  const LegacyMigrationProblem({required this.id,
    required this.kind, required this.sourceIndex,
    required this.primaryPayload, required this.conflictingPayload,
    required this.conversionIssues});
  final String id;
  final LegacyMigrationProblemKind kind;
  final int sourceIndex;
  final Map<String, Object?> primaryPayload;
  final Map<String, Object?>? conflictingPayload;
  final List<LegacyConversionIssue> conversionIssues;
  Map<String, Object?> toJson();
  factory LegacyMigrationProblem.fromJson(Map<String, Object?> json);
}
final class MigrationReport {
  const MigrationReport({required this.document, required this.imported,
    required this.skippedDuplicates, required this.unassignedMovementIds,
    required this.problems});
  final AccountingDocument document;
  final int imported;
  final int skippedDuplicates;
  final List<String> unassignedMovementIds;
  final List<LegacyMigrationProblem> problems;
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

- [ ] **Step 1 — Write RED legacy-unassigned and quarantine tests.** Feed valid buy/sell/old-transfer rows plus a row missing type/date and another with an unknown type. Assert valid conversions have `legacyUnassigned`, no real wallet is created, platform text remains metadata, and the projection key reuses H1 `virtualUnassignedWalletId`. Assert invalid rows are not fabricated as movements and each becomes one `LegacyMigrationProblem.unconvertible` preserving source index, byte-equivalent canonical input map and exact `LegacyConversionIssue` list. Run `flutter test test/accounting/migration/accounting_migrator_test.dart`; expected RED: migrator/problem types missing.

- [ ] **Step 2 — Implement field-preserving conversion and durable quarantine.** Import and reuse H1 `virtualUnassignedWalletId`; do not define a second constant. Use original ID where present; otherwise derive a deterministic RFC-4122-shaped UUID from SHA-256 of canonical legacy JSON, setting version/variant bits through `lib/accounting/support/sha256.dart` because no dependency may be added. Derive problem ID as `sha256(canonicalJson(kind, sourceIndex, primaryPayload, conflictingPayload))`. Extend `AccountingDocument` with `Map<String, Map<String, Object?>> legacyMovementMetadata`, keyed by movement ID, and `List<LegacyMigrationProblem> legacyMigrationProblems`, under exact JSON keys `legacyMovementMetadata` and `legacyMigrationProblems`; its constructor and `fromJson` default missing `legacyMigrationProblems` to `const <LegacyMigrationProblem>[]` so a PERSIST-1 document remains readable. Store all `LegacyMovementConversion.preservedFields` or unconvertible payloads/issues there. Serialize every conversion issue by exact enum code, message and raw value; read it losslessly. Preserve timestamps, fees, network, note, deleted/device/platform fields. Add a repository test that reads a PERSIST-1 JSON document without `legacyMigrationProblems` and round-trips it with an empty list. Quarantined rows remain durable/auditable but never enter projections. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED idempotency test.** Migrate the same list twice over the first result; assert byte-identical canonical JSON, imported second pass `0`, duplicates count equals input, and migration ID appears once. Run test; expected RED before guard/dedupe.

- [ ] **Step 4 — Implement dedupe and conflict quarantine.** Dedupe equal canonical payloads by movement ID. If the same ID has different canonical payload, do not overwrite or partially migrate either candidate: append one `LegacyMigrationProblem.conflictingId` containing both full maps and source index, leave any pre-existing canonical movement unchanged, and include it in `MigrationReport.problems`. Replaying the same input deduplicates problems by deterministic problem ID and is byte-identical. Never silently discard a source row. Re-run; expect GREEN.

- [ ] **Step 5 — Cover legacy global policy.** Assert `LegacyAccountingPolicy.preservePreviousGlobal` is recorded in migrated metadata and legacy aggregate output matches the adapter before assignment. Add the policy field to `AccountingDocument` with exact JSON key `legacyAccountingPolicy`. Run migration and repository tests; expect GREEN.

- [ ] **Step 6 — Verify regression/analyze.** Format, migration/persistence/adapter tests, full suite, analyzer tuple comparison and diff check.

- [ ] **Step 7 — Commit.** `git add lib/accounting/migration/accounting_migrator.dart lib/accounting/migration/migration_report.dart lib/accounting/migration/legacy_migration_problem.dart lib/accounting/support/sha256.dart lib/accounting/persistence/accounting_document.dart lib/accounting/adapters/legacy_movement_adapter.dart test/accounting/migration/accounting_migrator_test.dart test/accounting/support/sha256_test.dart test/accounting/persistence/accounting_repository_test.dart && git commit -m "feat(accounting): migrate legacy movements idempotently"`.

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

PERSIST-6 reemplaza este constructor de tres argumentos, sin cambiar
`load`/`saveLegacyView`, por
`LegacyPersistenceBridge(AccountingRepository repository,
AccountingMigrator migrator, LegacyMovementAdapter adapter,
WalletLifecycleCoordinator lifecycleCoordinator)` para recuperación de limpieza
al inicio. `WalletLifecycleCoordinator` y el cuarto argumento no existen ni se
referencian antes de PERSIST-6.

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

- [ ] **Step 3 — Write RED legacy-view preservation test shown above.** Also change date/quantity/fee in legacy view; assert merge by ID updates common fields while preserving assignment, destination type, adjustment/link, wallet `imageRef`, `legacyMovementMetadata` and `legacyMigrationProblems`. Assert only `accounting_document_v3` is written. Run test; expected RED before merge.

- [ ] **Step 4 — Implement merge with conflict checks.** Existing canonical ID is updated field-by-field through adapter; new legacy ID is converted unassigned; missing legacy IDs are retained unless caller supplies explicit `deletedIds`. Re-run; expect GREEN.

- [ ] **Step 5 — Integrate narrowly.** `_loadData` supplies decoded legacy maps to bridge only when v3 is absent and sets `_movements` with `legacyView.map(Movement.fromJson)`; `_saveData` supplies `_movements.map((value) => value.toJson())` to the bridge and writes only `accounting_document_v3`. Store the in-memory `AccountingDocument` field; do not alter unrelated settings/timers/cloud code. The bridge and accounting libraries never import the monolith.

- [ ] **Step 6 — Verify regression/analyze.** Run bridge, migration, current persistence/widget tests, full suite, analyzer tuple comparison and diff check. Inspect only `_loadData`/`_saveData` monolith hunks.

- [ ] **Step 7 — Commit.** `git add lib/accounting/adapters/legacy_persistence_bridge.dart lib/cripto_control_app.dart test/accounting/adapters/legacy_persistence_bridge_test.dart && git commit -m "feat(accounting): bridge legacy view to v3 persistence"`.

---

### Task PERSIST-3: Asignar movimientos individual y masivamente

**Purpose:** Justificar movimientos legacy mediante cambios explícitos, auditables e idempotentes sin duplicar tenencia.

**Files:**
- Create: `lib/accounting/application/movement_assignment_service.dart`
- Create: `lib/accounting/application/movement_assignment_command.dart`
- Create: `lib/accounting/domain/assignment_audit.dart`
- Create: `test/accounting/application/movement_assignment_service_test.dart`
- Modify: `lib/accounting/persistence/accounting_document.dart`
- Modify: `lib/accounting/adapters/legacy_persistence_bridge.dart`
- Modify: `test/accounting/adapters/legacy_persistence_bridge_test.dart`
- Existing symbols affected: none in monolith.

**Consumes:** `AccountingDocument`, wallet ID real, movement IDs, `AccountingLedgerEngine`.

**Produces:**

```dart
enum WalletAssignmentTarget { source, destination, adjustment }

sealed class MovementAssignmentCommand {
  const MovementAssignmentCommand(this.movementId);
  final String movementId;
  WalletAssignmentTarget get target;
}
final class AssignSourceWallet extends MovementAssignmentCommand {
  const AssignSourceWallet(super.movementId, this.walletId);
  final String walletId;
  @override WalletAssignmentTarget get target => WalletAssignmentTarget.source;
}
final class AssignDestinationWallet extends MovementAssignmentCommand {
  const AssignDestinationWallet(super.movementId, this.walletId);
  final String walletId;
  @override WalletAssignmentTarget get target => WalletAssignmentTarget.destination;
}
final class AssignOwnTransferDestination extends MovementAssignmentCommand {
  const AssignOwnTransferDestination(super.movementId, this.walletId);
  final String walletId;
  DestinationType get destinationType => DestinationType.ownWallet;
  @override WalletAssignmentTarget get target => WalletAssignmentTarget.destination;
}
final class ClassifyExternalTransferDestination
    extends MovementAssignmentCommand {
  const ClassifyExternalTransferDestination(super.movementId);
  DestinationType get destinationType => DestinationType.external;
  @override WalletAssignmentTarget get target => WalletAssignmentTarget.destination;
}
final class AssignAdjustmentWallet extends MovementAssignmentCommand {
  const AssignAdjustmentWallet(super.movementId, this.walletId);
  final String walletId;
  @override WalletAssignmentTarget get target => WalletAssignmentTarget.adjustment;
}

final class AssignmentStateSnapshot {
  const AssignmentStateSnapshot({required this.sourceWalletId,
    required this.destinationWalletId, required this.adjustmentWalletId,
    required this.destinationType, required this.status});
  final String? sourceWalletId;
  final String? destinationWalletId;
  final String? adjustmentWalletId;
  final DestinationType? destinationType;
  final WalletAssignmentStatus status;
}
final class AssignmentAudit {
  const AssignmentAudit({required this.id, required this.operationId,
    required this.movementId, required this.changedTargets,
    required this.before, required this.after, required this.assignedAt});
  final String id;
  final String operationId;
  final String movementId;
  final Set<WalletAssignmentTarget> changedTargets;
  final AssignmentStateSnapshot before;
  final AssignmentStateSnapshot after;
  final DateTime assignedAt;
}
final class AssignmentResult {
  const AssignmentResult({required this.document, required this.changedIds,
    required this.unchangedIds});
  final AccountingDocument document;
  final List<String> changedIds;
  final List<String> unchangedIds;
}
abstract interface class MovementAssignmentService {
  AssignmentResult assignOne(AccountingDocument document,
    {required MovementAssignmentCommand command,
    required String operationId, required DateTime assignedAt});
  AssignmentResult assignMany(AccountingDocument document,
    {required List<MovementAssignmentCommand> commands,
    required String operationId, required DateTime assignedAt});
}
```

`DefaultMovementAssignmentService` implementa esta interfaz. Deriva cada ID de
auditoría exactamente como `<operationId>:<movementId>` después de validar un
ID de operación no vacío, y serializa `changedTargets` ordenado por nombre de
enum para mantener determinista el JSON del documento.

La API no expone un comando genérico con campos anulables. Omitir un lado de la
lista significa no modificarlo; volver a enviar un comando `Assign*` reemplaza
explícitamente la asignación anterior; y
`ClassifyExternalTransferDestination` clasifica el destino como externo y
elimina cualquier `destinationWalletId` previo. La especificación no autoriza
un comando genérico para borrar una asignación sin reemplazarla, por lo que no
se ofrece. `AssignmentStateSnapshot` usa valores anulables sólo para describir
fielmente el estado antes/después, nunca para expresar una orden.

**First RED test code:**

```dart
test('assignOne replaces the event without duplicating custody', () {
  final before = legacyDocumentFixture();
  final result = service.assignOne(before,
      command: const AssignDestinationWallet('old-1',
          '11111111-1111-4111-8111-111111111111'),
      operationId: 'assignment-op-1',
      assignedAt: DateTime.utc(2026, 8, 11));
  expect(result.document.movements, hasLength(before.movements.length));
  expect(result.document.movements.single.destinationWalletId,
      '11111111-1111-4111-8111-111111111111');
  expect(result.document.movements.single.sourceWalletId, isNull);
  expect(project(result.document).totalCustody, project(before).totalCustody);
});
```

- [ ] **Step 1 — Write RED destination-assignment test.** Use `AssignDestinationWallet` for one legacy `buy`; assert same movement ID/quantity, `destinationWalletId` set, `sourceWalletId == null`, status `assigned`, one audit with exact before/after snapshots, no duplicate and unchanged aggregate custody. Run `flutter test test/accounting/application/movement_assignment_service_test.dart`; expected RED: command/service types missing.

- [ ] **Step 2 — Implement explicit command validation and event replacement.** Replace the matching event in place; never insert a movement. `AssignDestinationWallet` is accepted only for `buy` and external `transferIn`; `AssignSourceWallet` only for `sell` and `transferOut`; `AssignOwnTransferDestination` and `ClassifyExternalTransferDestination` only for `transferOut`; `AssignAdjustmentWallet` only for `balanceAdjustment`. Validate every supplied wallet as active and real. An owned transfer destination sets `DestinationType.ownWallet` plus an explicit, different destination wallet. An external destination sets `DestinationType.external` and clears `destinationWalletId`. Recompute status from required endpoints: an imported transfer with zero endpoints confirmed remains `legacyUnassigned`; a pre-existing `pending` draft stays `pending` until a command changes it; exactly one confirmed transfer endpoint is `partiallyAssigned`; and `assigned` requires every endpoint. Buy, sell, external `transferIn` and adjustment become `assigned` only when their sole required wallet role is populated. Never inspect platform/name fields. Persist `List<AssignmentAudit> assignmentAudits` in `AccountingDocument` under exact JSON key `assignmentAudits`, with constructor/fromJson default `const <AssignmentAudit>[]` for documents produced by earlier tasks. Make `LegacyPersistenceBridge.saveLegacyView` carry the current audit list unchanged. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED transfer-side tests.** Cover: only `AssignSourceWallet` leaves `transferOut` as `partiallyAssigned`; source plus `AssignOwnTransferDestination` produces `assigned` with two owned IDs; source plus `ClassifyExternalTransferDestination` produces `assigned`, `destinationType.external` and no destination wallet. Assert Mercado Pago/Bitso text changes none of those results. Run the same test file; expected RED until side/classification state is implemented.

- [ ] **Step 4 — Write and implement atomic batch assignment.** RED: submit source and destination commands for two transfers in one list; assert all commands are validated before mutation, one movement instance remains per ID, both sides are resolved, ordering is unchanged, and one audit per changed movement shares `operationId`. Include a wrong-side command and same-wallet internal transfer; assert the complete result/document/audit list is unchanged. Implement by grouping commands by movement ID, rejecting duplicate/conflicting commands for the same target, validating the entire collection, then replacing each movement once. Return sorted unique changed/unchanged IDs. Re-run; expect GREEN.

- [ ] **Step 5 — Test audit and idempotency.** Reapply an identical command with a new operation ID and assert no movement/timestamp change and no audit. Reassign a source or owned destination with an explicit `Assign*` command; assert the audit snapshot contains previous/new source, destination, adjustment, `DestinationType` and `WalletAssignmentStatus`, plus the exact changed target. Classifying a previously owned transfer as external must record the previous destination wallet and the new null destination. Invalid individual or batch operations add no audit. Run tests; expect GREEN.

- [ ] **Step 6 — Verify projection/analyze.** Compare projections before/after purchase assignment, partial/internal/external transfer assignment and reassignment: attribution may change, but aggregate quantity, cost base and movement count do not duplicate. Confirm audits are metadata and never enter ledger input, and a subsequent `saveLegacyView` round-trip preserves them byte-equivalently. Run assignment/bridge tests, accounting suite, full suite, analyzer comparison and diff check.

- [ ] **Step 7 — Commit.** `git add lib/accounting/application/movement_assignment_command.dart lib/accounting/application/movement_assignment_service.dart lib/accounting/domain/assignment_audit.dart lib/accounting/persistence/accounting_document.dart lib/accounting/adapters/legacy_persistence_bridge.dart test/accounting/application/movement_assignment_service_test.dart test/accounting/adapters/legacy_persistence_bridge_test.dart && git commit -m "feat(accounting): assign legacy movements explicitly"`.

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
  Future<WalletImageWriteBatch> stageAll(
    List<ProcessedWalletImage> images);
  Future<Uint8List> read(WalletImageRef imageRef);
  Future<void> deleteIfUnreferenced(WalletImageRef imageRef,
    Set<String> referencedImageIds);
}
abstract interface class WalletImageWriteBatch {
  Future<void> commit();
  Future<void> rollback();
}
```

`WalletImageRef.fileName` siempre es un nombre base como `<sha256>.png` o
`<sha256>.jpg`. `WalletImageStore` lo resuelve internamente bajo
`<application-support>/wallet_images/`. Un respaldo portable puede usar el
nombre de entrada `wallet_images/<basename>`, pero el decodificador extrae y
valida el basename antes de construir `WalletImageRef`; la ruta interna del
respaldo nunca se copia a `fileName`.

**First RED test code:**

```dart
test('private store verifies hash and never persists an absolute path', () async {
  final image = processedPngFixture(bytes: <int>[137, 80, 78, 71]);
  await store.write(image);
  expect(await store.read(image.imageRef), image.bytes);
  expect(image.imageRef.id, image.imageRef.sha256);
  expect(image.imageRef.fileName, '${image.imageRef.sha256}.png');
  expect(image.imageRef.fileName.contains('/'), isFalse);
  expect(image.imageRef.fileName.contains(r'\'), isFalse);
  expect(image.imageRef.fileName.contains(':'), isFalse);
});
```

- [ ] **Step 1 — Write RED service contract test.** Use a fake processor returning known PNG bytes and `WalletImageRef`; write/read in a temporary application-support directory. Assert durable `fileName` is a basename with no separator, the physical resolved file is `<temporary-root>/wallet_images/<basename>`, SHA matches, and no absolute/private/archive path enters JSON. Run `flutter test test/accounting/persistence/wallet_image_service_test.dart`; expected RED: contracts/store missing.

- [ ] **Step 2 — Implement basename metadata and private store.** Processor output uses SHA-256 as `WalletImageRef.id` and `<sha256>.png`/`<sha256>.jpg` as `fileName`. Reject empty names, `.`/`..`, any `/` or `\`, drive/UNC/absolute paths, a basename not matching the normalized hash and MIME extension, and a canonical resolved path outside the fixed private directory. `write` uses one temporary sibling; `stageAll` writes every candidate to temporary siblings and returns a batch whose `commit` promotes them and whose idempotent `rollback` removes only its temporary/new files. Delete only when the supplied referenced-ID set excludes the image ID. Add exact rejection tests for `../x.png`, `wallet_images/x.png`, `C:\x.png`, `/x.png`, `\\server\x.png` and a manipulated hash/name pair. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED channel contract test.** Mock `MethodChannel` and assert method `process`, arguments `bytes`, `preserveAlpha`, `maxLongEdge: 1024`, `jpegQuality: 82`; decode returned bytes, width, height, MIME and SHA. Run test; expected RED: adapter missing.

- [ ] **Step 4 — Implement Dart channel and Kotlin processor.** Kotlin uses `BitmapFactory.decodeByteArray`, scales preserving aspect ratio only when long edge exceeds 1024, encodes alpha images as PNG and opaque as JPEG quality 82, computes SHA-256 with `MessageDigest`, and returns a map. Register a second channel in `configureFlutterEngine` without changing alert handling.

- [ ] **Step 5 — Add native and storage-boundary tests.** In Dart, assert corrupt bytes surface `WalletImageProcessingException`; alpha/opaque response fixtures choose basename `.png`/`.jpg`; hash mismatch is rejected before storage. Assert `WalletImageRef.fromJson` and `WalletImageStore` reject traversal, absolute paths and separators in the durable reference. The archive-entry round-trip belongs to PERSIST-5, where its codec exists. Run test; expect RED then GREEN.

- [ ] **Step 6 — Verify Dart/native sources/analyze without a build artifact.** Run image tests, full suite, analyzer tuple comparison and diff check; run the existing Android unit/source checks that do not generate an APK. Do not run `flutter build`: the rollout reserves the sole debug build for IO-5. Inspect `MainActivity.kt` and `WalletImageChannel.kt` registration in the diff and defer device/native compile evidence to IO-5.

- [ ] **Step 7 — Commit.** `git add lib/accounting/persistence/wallet_image_processor.dart lib/accounting/persistence/wallet_image_store.dart lib/accounting/persistence/method_channel_wallet_image_processor.dart android/app/src/main/kotlin/mx/criptocontrolmx/app/WalletImageChannel.kt android/app/src/main/kotlin/mx/criptocontrolmx/app/MainActivity.kt test/accounting/persistence/wallet_image_service_test.dart && git commit -m "feat(wallets): store normalized private images"`.

---

### Task PERSIST-5: Respaldar y restaurar documento e imágenes local/Drive/Firebase

**Purpose:** Transportar el documento v3 completo sin romper rutas de respaldo existentes ni exceder límites de documento de nube.

**Files:**
- Create: `lib/accounting/io/accounting_backup_codec.dart`
- Create: `lib/accounting/io/accounting_backup_bundle.dart`
- Create: `lib/accounting/io/accounting_backup_restore_service.dart`
- Create: `lib/accounting/io/shared_preferences_accounting_backup_state_store.dart`
- Create: `lib/accounting/io/cloud_image_chunks.dart`
- Create: `test/accounting/io/accounting_backup_codec_test.dart`
- Modify: `lib/accounting/persistence/wallet_image_store.dart`
- Modify: `lib/cripto_control_app.dart`
- Existing symbols affected: `_buildBackupJson` (4291), `_applyBackupJson` (5064), subida/restauración Firebase (1410, 1611), Drive/local (2085, 2249, 4919).

**Consumes:** `AccountingDocument`, `ProcessedWalletImage`, and the existing
backup values: `List<PortfolioSnapshot>`, `Map<String, double> _currentPrices`,
`double _sellFeePercent`, `Map<String, String> _priceModes`, and
`Map<String, int> _manualPriceUpdatedAtMs`. The monolith converts
`PortfolioSnapshot`/`CoinSnapshot` to the neutral DTOs below; files under
`lib/accounting/` never import `cripto_control_app.dart`.

**Produces:**

```dart
enum AccountingBackupOrigin { legacyV1, legacyV2, schemaV3 }

final class BackupCoinSnapshot {
  const BackupCoinSnapshot({required this.coin, required this.quantity,
    required this.costBase, required this.avgPrice,
    required this.currentValue, required this.unrealizedPL,
    required this.realizedPL});
  final String coin;
  final double quantity;
  final double costBase;
  final double avgPrice;
  final double currentValue;
  final double unrealizedPL;
  final double realizedPL;
  Map<String, Object?> toJson();
  factory BackupCoinSnapshot.fromJson(Map<String, Object?> json);
}
final class BackupPortfolioSnapshot {
  const BackupPortfolioSnapshot({required this.id, required this.createdAt,
    required this.totalCostBase, required this.totalCurrentValue,
    required this.totalUnrealizedPL, required this.totalRealizedPL,
    required this.movementCount, required this.coins});
  final String id;
  final DateTime createdAt;
  final double totalCostBase;
  final double totalCurrentValue;
  final double totalUnrealizedPL;
  final double totalRealizedPL;
  final int movementCount;
  final List<BackupCoinSnapshot> coins;
  Map<String, Object?> toJson();
  factory BackupPortfolioSnapshot.fromJson(Map<String, Object?> json);
}
final class AccountingBackupSettings {
  const AccountingBackupSettings({required this.sellFeePercent,
    required this.priceModes, required this.manualPricesUpdatedAtMs,
    this.preservedFields = const <String, Object?>{}});
  final double sellFeePercent;
  final Map<String, String> priceModes;
  final Map<String, int> manualPricesUpdatedAtMs;
  final Map<String, Object?> preservedFields;
  Map<String, Object?> toJson();
  factory AccountingBackupSettings.fromJson(Map<String, Object?> json);
}
final class PortableWalletImage {
  const PortableWalletImage({required this.imageRef, required this.bytes});
  final WalletImageRef imageRef;
  final Uint8List bytes;
  ProcessedWalletImage toProcessed() =>
      ProcessedWalletImage(bytes, imageRef);
}
final class AccountingBackupBundle {
  const AccountingBackupBundle({required this.document,
    required this.snapshots, required this.currentPrices,
    required this.settings, required this.walletImages,
    required this.exportedAt,
    this.preservedTopLevelFields = const <String, Object?>{}});
  final AccountingDocument document;
  final List<BackupPortfolioSnapshot> snapshots;
  final Map<String, double> currentPrices;
  final AccountingBackupSettings settings;
  final List<PortableWalletImage> walletImages;
  final DateTime exportedAt;
  final Map<String, Object?> preservedTopLevelFields;
}
final class DecodedAccountingBackup {
  const DecodedAccountingBackup({required this.bundle,
    required this.origin, required this.warnings});
  final AccountingBackupBundle bundle;
  final AccountingBackupOrigin origin;
  final List<String> warnings;
}
abstract interface class AccountingBackupCodec {
  Map<String, Object?> encodeV3(AccountingBackupBundle bundle);
  DecodedAccountingBackup decodeAny(Map<String, Object?> json);
}
abstract interface class AccountingBackupStateStore {
  Future<AccountingBackupApplicationState> read();
  Future<void> write(AccountingBackupApplicationState state);
}
final class AccountingBackupApplicationState {
  const AccountingBackupApplicationState({required this.snapshots,
    required this.currentPrices, required this.settings});
  final List<BackupPortfolioSnapshot> snapshots;
  final Map<String, double> currentPrices;
  final AccountingBackupSettings settings;
}
final class AccountingBackupRestoreResult {
  const AccountingBackupRestoreResult({required this.document,
    required this.origin, required this.warnings});
  final AccountingDocument document;
  final AccountingBackupOrigin origin;
  final List<String> warnings;
}
final class AccountingRestoreRollbackException implements Exception {
  const AccountingRestoreRollbackException({required this.writeCause,
    required this.rollbackCause});
  final Object writeCause;
  final Object rollbackCause;
}
abstract interface class AccountingBackupRestoreService {
  Future<AccountingBackupRestoreResult> restore(
    DecodedAccountingBackup decoded);
}
final class CloudImageManifest {
  const CloudImageManifest({required this.imageId, required this.sha256,
    required this.chunkCount, required this.byteLength});
  final String imageId;
  final String sha256;
  final int chunkCount;
  final int byteLength;
}
final class CloudImageChunk {
  const CloudImageChunk({required this.imageId, required this.index,
    required this.bytes});
  final String imageId;
  final int index;
  final Uint8List bytes;
}
List<CloudImageChunk> splitCloudImage(String imageId, Uint8List bytes,
  {int chunkBytes = 600000});
Uint8List joinCloudImage(CloudImageManifest manifest,
  List<CloudImageChunk> chunks);
```

`DefaultAccountingBackupCodec` implementa `AccountingBackupCodec`.

**First RED test code:**

```dart
test('backup restores image bytes only after SHA-256 validation', () async {
  final source = completeBackupBundleFixture();
  final encoded = codec.encodeV3(source);
  final decoded = codec.decodeAny(encoded);
  final restored = await restoreService.restore(decoded);
  expect(restored.document.toJson(), source.document.toJson());
  expect(await targetImages.read(source.walletImages.single.imageRef),
      source.walletImages.single.bytes);
  final reopened = await targetStateStore.read();
  expect(reopened.snapshots.map((value) => value.toJson()).toList(),
      source.snapshots.map((value) => value.toJson()).toList());
  expect(reopened.currentPrices, source.currentPrices);
  expect(reopened.settings.toJson(), source.settings.toJson());
});
```

- [ ] **Step 1 — Write RED complete-bundle and portable-image round-trip.** Build one `AccountingBackupBundle` containing a document with adjustment, one `LegacyMigrationProblem.unconvertible`, one `LegacyMigrationProblem.conflictingId`, one wallet image, two typed snapshots, prices and every typed setting. Assert top-level `schemaVersion` is `3` and required keys are exactly present: `wallets`, `walletImages`, `movements`, `snapshots`, `currentPrices`, `settings`, `appliedMigrationIds`, `legacyMovementMetadata`, `legacyMigrationProblems`, `legacyAccountingPolicy`, `assignmentAudits`, `updatedAt` and `exportedAt`. Assert the portable image entry is exactly `wallet_images/<basename>`, Base64 decodes to the same SHA, decode returns the original basename-only `WalletImageRef.fileName`, and entries `wallet_images/../x.png`, absolute paths or nested separators are rejected before any store write. Adjustment reason/date/wallet/asset/quantity/observed balance/note, both migration problems with complete payloads/issues, and all snapshot/price/setting values must compare byte-equivalently after decode. Run `flutter test test/accounting/io/accounting_backup_codec_test.dart`; expected RED: bundle/codec types missing.

- [ ] **Step 2 — Implement the local/Drive codec without side effects.** `encodeV3` always writes schema `3`. For each movement, call `LegacyMovementAdapter.toLegacyJson(movement, preservedFields: metadata)` only to synchronize historical aliases, then overlay every entry from `movement.toJson()` so canonical v3 keys are authoritative and all `AccountingAmount` values remain decimal `String`; never feed the synchronized legacy row back through `AccountingMovement.fromJson`. Add assertions for every amount-bearing movement field (`quantity`, `unitPriceFiat`, `fiatFeeAmount`, `receivedAmount`, `cryptoFeeAmount`, `totalDebitedAmount`, `feeFiatValue`, `adjustmentQuantity`, `observedBalance` and reconciliation quantities) proving a JSON string when non-null. Each wallet image contains `WalletImageRef`, portable entry name `wallet_images/<basename>` and Base64 bytes; decode extracts the basename and never copies the entry path to `fileName`. `decodeAny` validates all required v3 fields, IDs, references, decimal movement values, finite snapshot/price/setting doubles, safe image basenames, byte lengths and hashes before returning. For v1/v2, route movements through `AccountingMigrator`, preserve its quarantine/problems, use empty snapshots only when absent with an explicit warning, require `currentPrices`, use `sellFeePercent: 0`, automatic empty price modes and empty update timestamps when legacy settings are absent, and record exact `AccountingBackupOrigin`. Preserve unknown approved top-level/settings keys only in their dedicated `Map<String, Object?>` extension maps; canonical keys override them on v3 output. Reading never rewrites storage. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED Firebase chunk test.** Split bytes larger than 1,200,000 into `CloudImageChunk`; assert deterministic zero-based indices, image ID, manifest count/size/hash; shuffled chunks rejoin by `index`; wrong image ID, out-of-range, missing or duplicate indices fail without changing store. Run codec test; expected RED before chunk types/functions.

- [ ] **Step 4 — Implement transport and staged restoration.** Firebase replaces each bundle image byte payload with a manifest in `cloudState/current` and writes chunks under `cloudState/current/walletImageChunks/{imageId}:{index}`; local/Drive keep Base64 in the same v3 bundle. Download joins all chunks in memory and reconstructs the exact JSON consumed by `decodeAny`. `DefaultAccountingBackupRestoreService`, with constructor `(AccountingRepository, WalletImageStore, AccountingBackupStateStore)`, first reads and retains the nullable previous document plus application state, validates the complete decoded bundle and calls `WalletImageStore.stageAll`. It then commits the validated image batch, writes the new `AccountingDocument` and writes one `AccountingBackupApplicationState` through the state store. If validation/staging fails, nothing active changes. If either active-state write fails, it restores the previous document with `write(previous)` or restores absence with `clear()`, restores the prior application state, then rolls back only the batch's new files that are unreferenced by the restored document; a typed `AccountingRestoreRollbackException` reports any failed compensation instead of claiming success. Never remove a pre-existing hash. Implement `SharedPreferencesAccountingBackupStateStore` with exact keys `portfolio_snapshots_v23_json`, `prices_json`, `sell_fee_percent`, `price_modes_v1_json` and `manual_prices_updated_at_v1_json`, so a fresh instance can reopen the same typed values. Add failure-injection tests before image promotion, after image promotion, after document write and during application-state write for both prior-document-present and prior-document-null cases, asserting the previous readable state/absence after successful compensation. Re-run; expect GREEN.

- [ ] **Step 5 — Integrate narrowly and prove reopen/repeat.** Change `_buildBackupJson` to `Future<String>` because it must read private image bytes; await it at the existing Firebase, Drive and local-backup call sites only. It maps existing `PortfolioSnapshot`/`CoinSnapshot`, `_currentPrices`, `_sellFeePercent`, `_priceModes` and `_manualPriceUpdatedAtMs` to the exact bundle DTOs, loads image bytes by each `WalletImageRef`, then delegates v3 encoding. `_applyBackupJson` calls `decodeAny` and `restore`; only after success does it replace the in-memory legacy view and reconstruct projections from restored movements. Firebase/Drive retain authentication and transport only. Add v2 import and v3 image-free regressions. In a SharedPreferences-backed test perform encode → decode → restore → create fresh repository/state adapters → reopen → encode/decode/restore a second time; assert byte-equivalent document, unchanged movement/image counts, equal snapshot DTOs, prices and settings. Do not restructure surrounding methods.

- [ ] **Step 6 — Verify compatibility/analyze.** Run codec, migration, image-store, current backup-related tests, full suite, analyzer tuple comparison and diff check. Assert no projection is serialized and restored projections are rebuilt only from movements. Manually inspect `git diff -- lib/cripto_control_app.dart` for scoped edits only.

- [ ] **Step 7 — Commit.** `git add lib/accounting/io/accounting_backup_bundle.dart lib/accounting/io/accounting_backup_codec.dart lib/accounting/io/accounting_backup_restore_service.dart lib/accounting/io/shared_preferences_accounting_backup_state_store.dart lib/accounting/io/cloud_image_chunks.dart lib/accounting/persistence/wallet_image_store.dart lib/cripto_control_app.dart test/accounting/io/accounting_backup_codec_test.dart && git commit -m "feat(accounting): back up schema v3 with wallet images"`.

---

### Task PERSIST-6: Aplicar ciclo de vida seguro de carteras

**Purpose:** Permitir archivar/restaurar y bloquear eliminación destructiva cuando existe historial o referencias.

**Files:**
- Create: `lib/accounting/application/wallet_lifecycle_service.dart`
- Create: `lib/accounting/application/wallet_image_cleanup_journal.dart`
- Create: `lib/accounting/application/wallet_lifecycle_coordinator.dart`
- Create: `test/accounting/application/wallet_lifecycle_service_test.dart`
- Modify: `lib/accounting/adapters/legacy_persistence_bridge.dart`
- Modify: `test/accounting/adapters/legacy_persistence_bridge_test.dart`
- Modify: `lib/cripto_control_app.dart`
- Existing symbols affected: construcción de `LegacyPersistenceBridge` y su
  ruta `_loadData`; no se modifica navegación, UI ni cálculo.

**Consumes:** `AccountingDocument`, `AccountingRepository`, `WalletImageStore`,
`SharedPreferences`, wallet ID and current time. The cleanup journal is local
operational metadata and never enters `AccountingDocument`, backups or ledger
input.

**Produces:**

```dart
enum WalletDeleteBlockReason { movementHistory, reconciliationLink }
enum WalletDeletionDecision { delete, archive, blocked }
enum WalletDeleteCommitStatus {
  blocked,
  archived,
  committed,
  committedWithPendingCleanup,
}
final class WalletImageCleanupIntent {
  const WalletImageCleanupIntent({required this.id,
    required this.sourceWalletId, required this.imageRef,
    required this.createdAt});
  final String id;
  final String sourceWalletId;
  final WalletImageRef imageRef;
  final DateTime createdAt;
}
abstract interface class WalletImageCleanupJournal {
  Future<List<WalletImageCleanupIntent>> readAll();
  Future<void> replaceAll(List<WalletImageCleanupIntent> intents);
}
const String walletImageCleanupJournalKey =
    'wallet_image_cleanup_journal_v1';
final class PreparedWalletDeletion {
  const PreparedWalletDeletion({required this.document,
    required this.decision, required this.cleanupIntents,
    required this.blockReasons});
  final AccountingDocument document;
  final WalletDeletionDecision decision;
  final List<WalletImageCleanupIntent> cleanupIntents;
  final Set<WalletDeleteBlockReason> blockReasons;
}
final class WalletImageCleanupResult {
  const WalletImageCleanupResult({required this.deletedImageIds,
    required this.stillReferencedImageIds,
    required this.pendingRetryImageIds});
  final Set<String> deletedImageIds;
  final Set<String> stillReferencedImageIds;
  final Set<String> pendingRetryImageIds;
}
final class WalletDeleteCommitResult {
  const WalletDeleteCommitResult({required this.document,
    required this.status, required this.cleanup});
  final AccountingDocument document;
  final WalletDeleteCommitStatus status;
  final WalletImageCleanupResult cleanup;
}
abstract interface class WalletLifecycleService {
  PreparedWalletDeletion prepareArchive(AccountingDocument document,
    String walletId, DateTime updatedAt);
  AccountingDocument restore(AccountingDocument document, String walletId,
    DateTime updatedAt);
  PreparedWalletDeletion prepareDelete(AccountingDocument document,
    String walletId, DateTime preparedAt);
  PreparedWalletDeletion prepareReassignAndDelete(AccountingDocument document,
    {required String sourceWalletId, required String targetWalletId,
    required DateTime updatedAt});
}
abstract interface class WalletLifecycleCoordinator {
  Future<WalletDeleteCommitResult> commitDelete(
    PreparedWalletDeletion prepared);
  Future<WalletImageCleanupResult> recoverPendingCleanup();
}
```

`DefaultWalletLifecycleService` implements the pure lifecycle interface.
`SharedPreferencesWalletImageCleanupJournal(SharedPreferences preferences)`
implements the journal using `walletImageCleanupJournalKey`.
`DefaultWalletLifecycleCoordinator(AccountingRepository repository,
WalletImageStore images, WalletImageCleanupJournal cleanupJournal)` implements
the ordered commit and recovery interface.

`prepareDelete` is pure: it does not persist and never touches the filesystem.
For a referenced wallet it returns `blocked`; `prepareArchive` returns
`archive` and preserves image/history. For an empty deletable wallet
it returns `delete`, a document without that wallet, and at most one cleanup
intent for its image. The durable journal is the smallest recovery mechanism
compatible with SharedPreferences and is not accounting truth.

`commitDelete` returns `blocked` without writes for a blocked preparation and
writes an archive document without journal/image calls for an archive
preparation. For deletion it has one mandatory order: append/deduplicate cleanup intents in
the journal; write the prepared v3 document; re-read the authoritative document;
then process intents whose image IDs are no longer referenced. Successful or
still-referenced intents are removed from the journal; physical failures remain
for retry and yield `committedWithPendingCleanup`. If journal persistence or
document persistence fails, no image delete is attempted. On each
`LegacyPersistenceBridge.load`, after choosing/migrating the authoritative v3
document, `recoverPendingCleanup` repeats the same re-read/reference check.

**First RED test code:**

```dart
test('wallet with movement history is archived, never deleted', () {
  final document = documentWithWalletHistory();
  const walletId = '11111111-1111-4111-8111-111111111111';
  final deletion = service.prepareDelete(document, walletId, clock);
  expect(deletion.decision, WalletDeletionDecision.blocked);
  expect(deletion.blockReasons, contains(WalletDeleteBlockReason.movementHistory));
  final archived = service.prepareArchive(document, walletId, clock);
  expect(archived.decision, WalletDeletionDecision.archive);
  expect(archived.document.wallets.single.status, WalletStatus.archived);
  expect(archived.document.movements, document.movements);
});
```

- [ ] **Step 1 — Write RED archive/restore test.** Archive wallet with movements and an image; assert history, projections and image reference remain, status/updatedAt change, no cleanup intent exists and it is excluded only from active selection. Restore reverses status without changing IDs/events/image. Run `flutter test test/accounting/application/wallet_lifecycle_service_test.dart`; expected RED: service missing.

- [ ] **Step 2 — Implement immutable lifecycle transitions.** `prepareArchive` replaces only the wallet record and document `updatedAt`, returns `archive` with no cleanup intent, and performs no I/O; `restore` reverses the status. Reject virtual/unknown IDs. Neither method calls repository, journal or image store. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED preparation tests.** Cover blockers for source/destination/adjustment wallet references and reconciliation links; assert `blocked`, byte-equivalent document, empty cleanup intents and every block reason. For an empty wallet with an image, assert `delete`, a document missing only that wallet, and one intent containing its exact `WalletImageRef`; assert no repository/journal/store call occurred. A shared image still referenced by another wallet may be a candidate but must be retained during commit/recovery. Run the test; expected RED: preparation contract absent.

- [ ] **Step 4 — Implement pure reference scan and journal.** Inspect canonical movement fields and links; do not rely on projections/platform names. Implement JSON round-trip and ID-deduplicating `replaceAll` for `SharedPreferencesWalletImageCleanupJournal`; validate image reference basenames on read. `prepareDelete` creates deterministic intent ID `delete:<walletId>:<imageId>` and never deletes or persists. Add journal tests proving repeated enqueue/replace is byte-equivalent. Re-run; expect GREEN.

- [ ] **Step 5 — Write RED commit-order/failure tests and implement coordinator.** With ordered fakes assert: journal intent write precedes repository write; repository success precedes repository re-read; re-read/reference scan precedes physical delete. Cover journal failure before document write, repository failure after intent but before document commit, interruption after document commit but before delete, physical delete failure, recovery on reopen, repeated recovery, and an image still referenced. Journal/repository failures perform zero deletes; cleanup failure returns `committedWithPendingCleanup` and retains intent; successful retry returns `committed` and removes it; a referenced image is never deleted and its stale intent is safely removed. Re-run; expect GREEN.

- [ ] **Step 6 — Test reassignment and startup recovery, then verify H2.** `prepareReassignAndDelete` replaces every source/destination/adjustment reference in one document, rejects same-wallet internal transfer, rebuilds projections before removal, and returns a `delete` decision plus cleanup intent without I/O. Replace the bridge's three-argument constructor with the final `LegacyPersistenceBridge(repository, migrator, adapter, lifecycleCoordinator)`; `load` invokes `recoverPendingCleanup` after authoritative v3 load/migration and before returning. Update the bridge test and wire only that dependency in `_loadData`. Prove reopen recovers an interruption after document commit, while an interruption before document commit sees the still-referenced image and never deletes it. Run all persistence/migration/I/O accounting tests, full suite, analyzer tuple comparison and diff check. Present document v3, migration report, image privacy/hash, journal recovery and lifecycle evidence at H2.

- [ ] **Step 7 — Commit.** `git add lib/accounting/application/wallet_image_cleanup_journal.dart lib/accounting/application/wallet_lifecycle_coordinator.dart lib/accounting/application/wallet_lifecycle_service.dart lib/accounting/adapters/legacy_persistence_bridge.dart lib/cripto_control_app.dart test/accounting/application/wallet_lifecycle_service_test.dart test/accounting/adapters/legacy_persistence_bridge_test.dart && git commit -m "feat(wallets): protect wallet lifecycle history"`.
