# Wallet I/O and Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Caracterizar la pérdida de hora, completar JSON/CSV/XLSX y demostrar el ciclo integral con regresiones, comparación exacta de analyzer y build debug.

**Architecture:** Codecs y exportadores consumen `AccountingDocument`/`LedgerProjection`; no recalculan contabilidad. La prueba horaria recorre cada frontera antes de autorizar una corrección. El E2E usa repositorios temporales y fakes de I/O para ser determinista.

**Tech Stack:** Flutter test, JSON, CSV existente, paquete `excel` existente, SharedPreferences, build Android debug; sin dependencias ni versión nuevas.

## Global Constraints

- Requiere UI-1 a UI-6 y aprobación H3.
- IO-1 se ejecuta antes de cualquier cambio destinado a fecha/hora.
- Si IO-1 no reproduce el fallo, no se modifica código funcional de fecha; se conserva la caracterización verde.
- Encabezados CSV/XLSX históricos conservan nombre, posición y semántica; columnas v3 se anexan.
- Importar una transferencia interna jamás crea un segundo evento.
- El caso `127.75883985 UNI` vive sólo en fixtures/pruebas.
- Verificación final acepta diagnósticos baseline preexistentes, pero ninguno nuevo y total <=30.
- `flutter build apk --debug` es verificación local; no copiar/agregar/publicar el APK.

---

### Task IO-1: Caracterizar fecha/hora a través de todo el ciclo

**Purpose:** Determinar con evidencia si `30/07/2026 20:54` se convierte en `30/07/2026 00:00` y localizar la primera frontera que pierde la hora.

**Files:**
- Create: `test/wallets/io/movement_datetime_roundtrip_test.dart`
- Create: `test/wallets/io/datetime_trace_harness.dart`
- Conditional Modify only after demonstrated RED at form/model/copy boundary: `lib/cripto_control_app.dart`
- Conditional Modify only after demonstrated RED at canonical model boundary: `lib/accounting/domain/accounting_movement.dart`
- Conditional Modify only after demonstrated RED at persistence boundary: `lib/accounting/persistence/shared_preferences_accounting_repository.dart`
- Conditional Modify only after demonstrated RED at list/detail/edit boundary: `lib/wallets/ui/wallet_history_list.dart`, `lib/wallets/ui/wallet_detail_page.dart` or `lib/wallets/ui/movement_wallet_fields.dart`, according to the first failing assertion
- Conditional Modify only after demonstrated RED at backup export/import boundary: `lib/accounting/io/accounting_backup_codec.dart`
- Existing symbols observed: `_showAddMovementSheet` (3359), `Movement.copyWith` in class at 25093, `Movement.toJson/fromJson`, `_saveData` (2990), `_loadData` (2375), list build in `MovementsTab` (8241), detail/edit routes, `_buildMovementsCsv` (4314), `_buildXlsxBytes` (4540), `_buildBackupJson` (4291), `_applyBackupJson` (5064).

**Consumes:** current movement form, `Movement` and `AccountingMovement`, repository, list/detail/editor widgets, JSON/CSV/XLSX codecs.

**Produces:**

```dart
final class DateTimeTrace {
  const DateTimeTrace({required this.form, required this.model,
    required this.copy, required this.json, required this.persisted,
    required this.reopened, required this.list, required this.detail,
    required this.edited, required this.exported, required this.imported});
  final DateTime form;
  final DateTime model;
  final DateTime copy;
  final DateTime json;
  final DateTime persisted;
  final DateTime reopened;
  final DateTime list;
  final DateTime detail;
  final DateTime edited;
  final DateTime exported;
  final DateTime imported;
}
```

**First RED test code:**

The complete trace test below is written before any production correction.

- [ ] **Step 1 — Write the characterization test before any fix.** Use the exact local value and assert every named boundary:

```dart
testWidgets('preserves 30/07/2026 20:54 through the complete movement cycle',
    (tester) async {
  final expected = DateTime(2026, 7, 30, 20, 54);
  final trace = await traceMovementDateTime(tester, expected);
  expect(<DateTime>[
    trace.form, trace.model, trace.copy, trace.json, trace.persisted,
    trace.reopened, trace.list, trace.detail, trace.edited,
    trace.exported, trace.imported,
  ], everyElement(expected));
});
```

Run: `flutter test test/wallets/io/movement_datetime_roundtrip_test.dart --reporter expanded`. Expected outcome is observational: RED must name the first boundary returning `2026-07-30 00:00`; GREEN proves the defect is not reproducible under this scenario.

- [ ] **Step 2 — Expand scenarios without changing production.** Add local time, ISO with explicit `-06:00`, UTC converted to local, DST-neutral dates for Mexico City, create/edit without changing date and JSON backup export/import. Observe CSV/XLSX exported cells separately through the existing builders; their importers do not exist until IO-3 and are not consumed here. Record each boundary in assertion reasons. Run the same command.

- [ ] **Step 3 — Follow the evidence branch.** If every scenario is GREEN, add a test name/comment documenting “not reproduced” and make no production change. If RED, inspect only the first failing boundary, write a narrower unit test that fails there, and list its exact observed/expected values in the commit body.

- [ ] **Step 4 — Apply only a demonstrated minimal fix.** Examples allowed only when proven: preserve time when merging a selected calendar date, make `copyWith` distinguish omitted/null, or parse the exported ISO value without truncation. Do not normalize to midnight and do not change timezone policy elsewhere. Re-run the narrow test and full trace; expect GREEN.

- [ ] **Step 5 — Confirm list/detail/edit/export/import rendering.** Widget assertions use text `30/07/2026 20:54`; backup JSON exports and imports an ISO string retaining time/offset semantics; CSV/XLSX exports retain the same date and time in their cells. Full tabular re-import is added only after its interfaces exist in IO-3. Run the trace plus existing movement tests.

- [ ] **Step 6 — Verify/analyze.** Run formatter, date trace, wallet UI/I/O tests, full suite, analyzer tuple comparison and diff check. Confirm production diff is empty if no reproduction.

- [ ] **Step 7 — Commit exact branch output.** Run `git add test/wallets/io/movement_datetime_roundtrip_test.dart test/wallets/io/datetime_trace_harness.dart lib/cripto_control_app.dart lib/accounting/domain/accounting_movement.dart lib/accounting/persistence/shared_preferences_accounting_repository.dart lib/wallets/ui/wallet_history_list.dart lib/wallets/ui/wallet_detail_page.dart lib/wallets/ui/movement_wallet_fields.dart lib/accounting/io/accounting_backup_codec.dart`; unchanged candidates add no diff. Run `git commit -m "test(accounting): characterize movement datetime round trip"` when no production hunk exists, or `git commit -m "fix(accounting): preserve movement datetime"` when a minimal proven correction exists; describe the first demonstrated boundary in the commit body.

---

### Task IO-2: Completar importación/exportación JSON v3 y legacy

**Purpose:** Garantizar que todos los campos contables, ajustes, asignaciones, transferencias e imágenes sobreviven al JSON sin perder compatibilidad.

**Files:**
- Create: `lib/accounting/io/accounting_json_io.dart`
- Create: `test/accounting/io/accounting_json_io_test.dart`
- Modify: `lib/accounting/io/accounting_backup_codec.dart`
- Modify: `lib/cripto_control_app.dart`
- Existing symbols affected: `_buildBackupJson` (4291), `_applyBackupJson` (5064), import/export local/Drive/Firebase callers.

**Consumes:** `AccountingBackupCodec`, `AccountingMigrator`, existing backup JSON v1/v2 fixtures.

**Produces:**

```dart
final class AccountingJsonIo {
  const AccountingJsonIo(this.codec);
  Future<String> exportDocument(AccountingDocument document,
    WalletImageStore images, {bool pretty = true});
  Future<AccountingDocument> importDocument(String source,
    WalletImageStore images);
}
```

**First RED test code:**

```dart
test('v3 JSON preserves an internal transfer as one event', () async {
  final source = documentWithSingleInternalTransfer();
  final json = await io.exportDocument(source, images);
  final restored = await io.importDocument(json, restoredImages);
  expect(restored.movements, hasLength(1));
  expect(restored.movements.single.type, MovementType.transferOut);
  expect(restored.movements.single.destinationType, DestinationType.ownWallet);
});
```

- [ ] **Step 1 — Write RED complete-v3 test.** Fixture includes all enum variants and nullable fields, one internal transfer as a single `transferOut`, external transfer, adjustment with reason/date/wallet/asset/quantity/observed/notes, links, audits and image. Assert canonical map equality after round-trip. Run `flutter test test/accounting/io/accounting_json_io_test.dart`; expected RED: facade/coverage missing.

- [ ] **Step 2 — Implement deterministic JSON facade.** Pretty output uses two-space indent; maps/sets have stable ordering; decimals remain strings and dates ISO. Decode stages document/images before replacing any persisted state. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED compatibility tests.** Import representative current backup with only `movements`, older field aliases and image-free v3; assert migration report, virtual unassigned and unchanged legacy aggregates. Export-import-export v3 must be semantically identical. Run test; expected RED before routing.

- [ ] **Step 4 — Implement version routing.** Read top-level `schemaVersion`; version 3 uses canonical fields and v1/v2 delegate to the migrator. Reject future version with visible typed error. Never map `sourcePlatform == destinationPlatform` or names to ownership. Re-run; expect GREEN.

- [ ] **Step 5 — Integrate exact monolith boundaries.** `_buildBackupJson` calls facade/codec data builder; `_applyBackupJson` imports into a staged document then refreshes both controller and legacy adapter list. Preserve settings/prices/snapshots behavior. Run old/current backup regression tests.

- [ ] **Step 6 — Verify/analyze.** Format, JSON/backup/migration tests, full suite, analyzer tuple comparison, diff check and scoped monolith diff review.

- [ ] **Step 7 — Commit.** `git add lib/accounting/io/accounting_json_io.dart lib/accounting/io/accounting_backup_codec.dart lib/cripto_control_app.dart test/accounting/io/accounting_json_io_test.dart && git commit -m "feat(accounting): import and export complete schema v3 JSON"`.

---

### Task IO-3: Extender CSV y XLSX sin alterar columnas históricas

**Purpose:** Exportar datos v3 auditables y reimportables anexando columnas a los formatos actuales.

**Files:**
- Create: `lib/accounting/io/accounting_tabular_io.dart`
- Create: `test/accounting/io/accounting_tabular_io_test.dart`
- Modify: `lib/cripto_control_app.dart`
- Existing symbols affected: `_buildMovementsCsv` (4314), `_buildXlsxBytes` (4540), export calls (4833, 4894).

**Consumes:** canonical movements, `legacyMovementMetadata`, wallet names, `LedgerProjection`, package `excel` and existing CSV escaping behavior.

**Produces:**

```dart
final class AccountingTabularIo {
  String buildCsv(AccountingDocument document, LedgerProjection projection);
  Uint8List buildXlsx(AccountingDocument document, LedgerProjection projection);
  List<AccountingMovement> importCsv(String csv);
  List<AccountingMovement> importXlsx(Uint8List bytes);
}
```

**First RED test code:**

```dart
test('CSV keeps the historical prefix and appends v3 columns', () {
  final document = documentFixture();
  final header = io.buildCsv(document, project(document)).split('\n').first.split(',');
  expect(header.take(historicalCsvHeaders.length), historicalCsvHeaders);
  expect(header.skip(historicalCsvHeaders.length), newWalletCsvHeaders);
});
```

Historical CSV prefix, unchanged and in order:

```text
fecha,tipo,tipo_raw,cripto,cantidad,precio_unitario_mxn,comision_mxn,total_bruto_mxn,plataforma,cartera,red,nota,cantidad_recibida,comision_cripto,activo_comision,total_descontado,valor_comision_mxn,plataforma_origen,plataforma_destino
```

Append exactly:

```text
source_wallet_id,destination_wallet_id,destination_type,external_recipient_name,external_destination_platform,wallet_assignment_status,adjustment_wallet_id,adjustment_quantity,observed_balance,adjustment_reason,accounting_completeness,known_quantity,unknown_cost_quantity
```

- [ ] **Step 1 — Write RED header-lock test.** Parse CSV header and XLSX `Historial` header; assert every current header remains at its index and new headers follow in the exact order above (Spanish XLSX labels are the title-cased equivalents). Run `flutter test test/accounting/io/accounting_tabular_io_test.dart`; expected RED: exporter absent/new columns missing.

- [ ] **Step 2 — Implement row mapping once.** Private `List<Object?> movementRow(AccountingMovement, Map<String, Wallet>, LedgerProjection)` feeds both CSV and XLSX. Read completeness/known/unknown from the projection and do not recalculate them. CSV escaping handles commas/quotes/newlines. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED full row round-trip.** Cover adjustment, internal one-event transfer, external transfer and exact decimals; import CSV/XLSX and assert movement semantic equality. The three projection-only columns are validated against a newly projected result and ignored as source-of-truth on import. Run test; expected RED: importers absent or types lost.

- [ ] **Step 4 — Implement strict import with legacy prefix support.** Resolve columns by header name and accept files with only the historical prefix as legacy/unassigned. Because the approved columns do not include an ID, derive a stable UUID from the normalized source row plus its occurrence ordinal; repeated import yields the same IDs and the repository/migrator rejects conflicts. Never synthesize a destination event. Re-run; expect GREEN.

- [ ] **Step 5 — Replace only builder bodies in monolith.** `_buildMovementsCsv` and `_buildXlsxBytes` delegate with the current document and `LedgerProjection`; file pick/share flows remain. Test historical fixture byte semantics excluding permitted appended columns.

- [ ] **Step 6 — Verify/analyze.** Format, tabular/JSON tests, full suite, analyzer tuple comparison and diff check.

- [ ] **Step 7 — Commit.** `git add lib/accounting/io/accounting_tabular_io.dart lib/cripto_control_app.dart test/accounting/io/accounting_tabular_io_test.dart && git commit -m "feat(accounting): append wallet fields to tabular exports"`.

---

### Task IO-4: Demostrar el ciclo integral y el caso Mercado Pago

**Purpose:** Probar todas las fronteras del flujo solicitado con persistencia/reapertura/importación reales en memoria y widgets de producción.

**Files:**
- Create: `test/wallets/integration/wallet_accounting_flow_test.dart`
- Create: `test/wallets/integration/wallet_flow_harness.dart`
- Existing symbols affected: all public APIs created por CORE/PERSIST/UI/IO; no nueva API prevista.

**Consumes:** controllers, repository mock SharedPreferences, projectors, JSON/CSV/XLSX codecs and wallet widgets.

**Produces:** Test harness only:

```dart
final class WalletFlowHarness {
  static Future<WalletFlowHarness> create(WidgetTester tester);
  Future<Wallet> createWallet(WalletDraft draft);
  Future<void> assign(Set<String> movementIds, String walletId);
  Future<void> reopen();
  LedgerProjection calculate();
  Future<void> edit(AccountingMovement movement);
  Future<void> delete(String movementId);
  Future<String> exportJson();
  Future<void> importIntoEmptyRepository(String value);
  LedgerProjection get projectionBeforeExport;
}
```

**First RED test code:**

```dart
testWidgets('completes the persisted wallet accounting lifecycle', (tester) async {
  final flow = await WalletFlowHarness.create(tester);
  final wallet = await flow.createWallet(mercadoPagoDraft());
  await flow.assign(<String>{'legacy-uni'}, wallet.id);
  await flow.reopen();
  expect(flow.calculate().positions, isNotEmpty);
  final exported = await flow.exportJson();
  await flow.importIntoEmptyRepository(exported);
  expect(flow.calculate(), flow.projectionBeforeExport);
});
```

- [ ] **Step 1 — Write RED complete-flow test.** Execute, with assertions after each arrow: crear cartera → asignar legacy → guardar → reabrir → calcular → mostrar detalle → editar ajuste → eliminar ajuste → exportar → importar en repositorio vacío → conciliar. Run `flutter test test/wallets/integration/wallet_accounting_flow_test.dart --reporter expanded`; expected RED must identify the first unwired boundary.

- [ ] **Step 2 — Build harness from production interfaces only.** Use `SharedPreferences.setMockInitialValues`, fake image processor/store temp, real repository/migrator/projector/codecs/controllers. Do not reproduce formulas in test helpers. Re-run and address only missing wiring proven by RED.

- [ ] **Step 3 — Add mandatory external-transfer fixture.** Create `Mi Mercado Pago`; external destination `Primo`/`Bitso`; received `1 UNI`; fee `0.00167532 UNI`; total debit `1.00167532 UNI`; observed `127.75883985 UNI`. Assert one persisted transfer, no owned Bitso wallet/credit, realized P&L `$0`, proportional known/unknown removal and visible reconciliation difference. Run test.

- [ ] **Step 4 — Add negative/edge flow.** Include negative reconciliation, sale below/equal/above known, insufficient custody, transfer proportional confirmation, edit/delete exact rebuild, archive/restore, image backup and legacy import. Assert audit records remain. Run integration and focused unit tests.

- [ ] **Step 5 — Add tabular and cloud round-trips.** Export/import JSON, CSV, XLSX and Firebase chunk transport from the same fixture; assert document/projection semantic equality and one-event internal transfers in every result.

- [ ] **Step 6 — Verify/analyze.** Format test files, run the integration test three times for determinism, full suite, analyzer tuple comparison and diff check. Expected GREEN: the three projections and serialized documents are identical and no analyzer tuple is new.

- [ ] **Step 7 — Commit only the planned evidence.** `git add test/wallets/integration/wallet_accounting_flow_test.dart test/wallets/integration/wallet_flow_harness.dart && git commit -m "test(accounting): verify complete wallet accounting flow"`. If Step 1 exposes missing production wiring, stop IO-4, return to the owning earlier task, add its already enumerated production file in that task’s corrective commit, then restart IO-4 from RED.

---

### Task IO-5: Ejecutar regresión final, comparación de baseline y build debug

**Purpose:** Producir evidencia reproducible de que el rollout no introduce regresiones ni diagnósticos y compila en Android debug.

**Files:**
- Create: `docs/superpowers/verification/2026-08-11-wallet-accounting-results.md`
- Existing symbols affected: none planned.

**Consumes:** baseline approved, compare tool, all plan commits.

**Produces:** A verification report containing commit range, environment, commands, test totals, analyzer tuple diff, build result, diff check and residual risks.

**First acceptance test code:**

```powershell
flutter test --reporter expanded
if ($LASTEXITCODE -ne 0) { throw 'La suite completa falló' }
dart run tool/compare_analyze_baseline.dart `
  docs/superpowers/baselines/2026-08-10-wallets-baseline.md `
  build/verification/flutter-analyze-current.txt
if ($LASTEXITCODE -ne 0) { throw 'El análisis difiere de la baseline' }
```

Expected initial failure: any unfinished task, new diagnostic or missing report blocks IO-5. Expected GREEN after the plan sequence: both exit codes are zero and the report records the evidence.

- [ ] **Step 1 — Capture pre-verification state.** Record `git rev-parse HEAD`, branch, `git status --short`, `flutter --version`, `dart --version`; confirm no APK/assets/QA changes. Start report with exact outputs.

- [ ] **Step 2 — Run focused suites.** Execute `flutter test test/accounting`, `flutter test test/wallets`, `flutter test test/accounting_hotfix_test.dart`, `flutter test test/transfer_crypto_fee_hotfix_test.dart`, `flutter test test/widget_test.dart`. Any failure blocks progression; use `superpowers:systematic-debugging` and commit a scoped fix separately before restarting IO-5.

- [ ] **Step 3 — Run full suite and diff check.** Execute `flutter test --reporter expanded` and `git diff --check`; record passed/failed/skipped totals and exact commands.

- [ ] **Step 4 — Compare analyzer structurally.** Run rollout protocol. Embed a table of removed, unchanged, moved and new tuples by `(archivo, severidad, regla, mensaje)`. Acceptance: new `0`, total `<=30`; explain every removed/moved tuple. A new tuple blocks build until fixed.

- [ ] **Step 5 — Build debug only.** Run `flutter build apk --debug`; record success/path/size for evidence but do not copy, stage or distribute output. Confirm `git status --short` has no generated artifact.

- [ ] **Step 6 — Audit invariants and matrix.** Run searches proving no production `127.75883985`, no deprecated `Radio` parameters in new UI, no platform ownership inference, no second persisted internal-transfer event, no dependency/version diff, and no changes under protected artifact paths. Complete every rollout matrix row with test command/result and present H4.

- [ ] **Step 7 — Commit report after all gates are green.** `git add docs/superpowers/verification/2026-08-11-wallet-accounting-results.md && git commit -m "docs(accounting): record wallet rollout verification"`. Stop for human integration decision; do not push, merge, rebase, tag or build release artifacts.
