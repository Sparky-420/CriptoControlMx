# Wallet UI Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrar Carteras desde “Más”, permitir administración/asignación/movimientos y mostrar custodia/rendimiento sin trasladar reglas contables a widgets.

**Architecture:** `WalletsController` coordina repositorio y `AccountingLedgerEngine`; widgets reciben view models inmutables y comandos tipados. El monolito sólo crea dependencias, abre rutas y sincroniza su vista legacy.

**Tech Stack:** Flutter Material vigente, `RadioGroup`, Navigator existente, pruebas de widgets con `flutter_test`; sin paquetes ni cambios de versión.

## Global Constraints

- Requiere PERSIST-1, PERSIST-2, PERSIST-2B y PERSIST-3 a PERSIST-6, además de aprobación H2.
- UI no calcula costo, proporciones, diferencias ni P&L; muestra valores de `LedgerProjection`.
- Advertir siempre que tenencia conciliada y posición conocida difieran.
- No mostrar `realizedPnlKnown` como P&L total cuando venta sea `partiallyKnown`.
- Formularios nunca deducen destino propio por plataforma.
- No usar parámetros obsoletos `groupValue`/`onChanged` en `Radio`; usar `RadioGroup<T>`.
- Campos accesibles tienen label/hint/error semánticos; vacíos y fallos son estados explícitos.
- Cambios en `cripto_control_app.dart` son aditivos y acotados.

---

### Task UI-1: Crear controlador e ingreso “Carteras” desde “Más”

**Purpose:** Conectar documento, proyección y navegación sin sustituir el estado global histórico.

**Files:**
- Create: `lib/wallets/application/wallets_controller.dart`
- Create: `lib/wallets/ui/wallets_page.dart`
- Create: `lib/wallets/ui/wallets_view_state.dart`
- Create: `test/wallets/ui/wallet_entry_point_test.dart`
- Modify: `lib/cripto_control_app.dart`
- Existing symbols affected: `_CriptoControlAppState` (371), `_loadData` (2375), `_saveData` (2990), root `build` (5564), `MoreTab` (19053) and its constructor (19140).

**Consumes:** `AccountingRepository`, `AccountingLedgerEngine`, `WalletLifecycleService`.

**Produces:**

```dart
sealed class WalletsViewState { const WalletsViewState(); }
final class WalletsLoading extends WalletsViewState { const WalletsLoading(); }
final class WalletsReady extends WalletsViewState {
  const WalletsReady(this.document, this.projection);
  final AccountingDocument document;
  final LedgerProjection projection;
}
final class WalletsFailure extends WalletsViewState {
  const WalletsFailure(this.message, this.retry);
  final String message;
  final Future<void> Function() retry;
}
final class WalletsController extends ChangeNotifier {
  WalletsController(this.repository, this.engine);
  WalletsViewState get state;
  Future<void> load();
  Future<void> replaceDocument(AccountingDocument document);
}
final class WalletsPage extends StatelessWidget {
  const WalletsPage({super.key, required this.controller});
  final WalletsController controller;
}
```

**First RED test code:**

```dart
testWidgets('opens Carteras from Más without replacing existing tabs', (tester) async {
  await tester.pumpWidget(const CriptoControlApp());
  await tester.tap(find.text('Más'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Carteras'));
  await tester.pumpAndSettle();
  expect(find.byType(WalletsPage), findsOneWidget);
  expect(find.text('Carteras'), findsWidgets);
});
```

- [ ] **Step 1 — Write RED navigation test.** Pump `CriptoControlApp` with mocked preferences, tap “Más” then “Carteras”, assert `find.byType(WalletsPage)` and accessible route name. Run `flutter test test/wallets/ui/wallet_entry_point_test.dart`; expected RED: entry/page absent.

- [ ] **Step 2 — Implement controller state transitions.** Test fake repository success/failure/retry first in the same file; then load document or an empty v3 document and project it. Run test; expect GREEN for controller cases.

- [ ] **Step 3 — Add minimal page states.** Loading uses labeled progress; failure shows message and “Reintentar”; ready initially shows count and empty-state copy “Aún no tienes carteras”. Re-run widget test; expect GREEN.

- [ ] **Step 4 — Integrate narrowly into monolith.** Add repository/controller fields, initialize after `_loadData`, dispose controller, pass `onOpenWallets` into `MoreTab`, and `Navigator.push` the page. Keep existing tabs/callbacks unchanged. Re-run navigation test.

- [ ] **Step 5 — Add regression assertion.** Verify “Resumen”, “Monedas” and existing “Más” actions remain findable after returning from Carteras. Run entry test and `test/widget_test.dart`; expect GREEN.

- [ ] **Step 6 — Verify/analyze.** Format touched Dart files, run wallet UI test, full suite, analyzer tuple comparison and diff check; inspect monolith diff scope.

- [ ] **Step 7 — Commit.** `git add lib/wallets/application/wallets_controller.dart lib/wallets/ui/wallets_page.dart lib/wallets/ui/wallets_view_state.dart lib/cripto_control_app.dart test/wallets/ui/wallet_entry_point_test.dart && git commit -m "feat(wallets): open wallets from more tab"`.

---

### Task UI-2: Listar, crear, editar, archivar y restaurar carteras

**Purpose:** Administrar metadatos de cartera e imagen mediante servicios existentes y validación visible.

**Files:**
- Create: `lib/wallets/ui/wallet_list_view.dart`
- Create: `lib/wallets/ui/wallet_editor_page.dart`
- Create: `lib/wallets/application/wallet_editor_controller.dart`
- Create: `test/wallets/ui/wallet_list_page_test.dart`
- Create: `test/wallets/ui/wallet_editor_page_test.dart`
- Modify: `lib/wallets/ui/wallets_page.dart`
- Modify: `lib/wallets/application/wallets_controller.dart`
- Existing symbols affected: none in monolith.

**Consumes:** `Wallet`, `WalletImageProcessor`, `WalletImageStore`, `WalletLifecycleService`, `EntityIdGenerator`.

**Produces:**

```dart
sealed class WalletImageChange { const WalletImageChange(); }
final class KeepWalletImage extends WalletImageChange {
  const KeepWalletImage();
}
final class RemoveWalletImage extends WalletImageChange {
  const RemoveWalletImage();
}
final class ReplaceWalletImage extends WalletImageChange {
  const ReplaceWalletImage(this.bytes);
  final Uint8List bytes;
}
final class WalletDraft {
  const WalletDraft({required this.name, required this.provider,
    this.colorArgb, this.note,
    this.imageChange = const KeepWalletImage()});
  final String name;
  final String provider;
  final int? colorArgb;
  final String? note;
  final WalletImageChange imageChange;
}
final class WalletDraftErrors {
  const WalletDraftErrors({this.name, this.provider, this.image});
  final String? name;
  final String? provider;
  final String? image;
  bool get isEmpty;
}
final class WalletEditorController {
  Future<Wallet> create(WalletDraft draft);
  Future<Wallet> update(String walletId, WalletDraft draft);
}
```

**First RED test code:**

```dart
testWidgets('rejects blank wallet identity fields', (tester) async {
  await tester.pumpWidget(editorHarness());
  await tester.enterText(find.byKey(const Key('wallet-name')), '   ');
  await tester.enterText(find.byKey(const Key('wallet-provider')), '');
  await tester.tap(find.text('Guardar'));
  await tester.pump();
  expect(find.text('Escribe un nombre para la cartera'), findsOneWidget);
  expect(find.text('Escribe el proveedor o tipo'), findsOneWidget);
});
```

- [ ] **Step 1 — Write RED list test.** Pump active and archived wallets; assert active cards first, archived section collapsed, provider/color/image semantics, and empty state. Run `flutter test test/wallets/ui/wallet_list_page_test.dart`; expected RED: list absent.

- [ ] **Step 2 — Implement presentational list.** Accept `List<Wallet>`, callbacks `ValueChanged<String> onOpen`, `onArchive`, `onRestore`; no repository access. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED editor validation test.** Submit whitespace name/provider, assert exact field errors; enter “Mi Mercado Pago”, “Mercado Pago”, note/color, fake image and assert `WalletDraft`. Add an existing wallet with the same name/provider and assert a non-blocking warning plus provider/short-ID disambiguation; saving remains allowed because names do not prove identity. Run `flutter test test/wallets/ui/wallet_editor_page_test.dart`; expected RED: editor absent.

- [ ] **Step 4 — Implement form/controller.** Trim required fields, normalize empty `note` to null, use `Form` validation; process image before document commit and remove newly written image on commit failure. When replacing an image, delete the previous private file only after document write succeeds and only when no wallet references it. Edit preserves wallet ID/createdAt/schemaVersion and changes updatedAt. Re-run; expect GREEN.

- [ ] **Step 5 — Add archive/restore tests and wiring.** Tap actions, confirm dialog text states history is preserved, invoke lifecycle service, refresh controller. Deletion is not exposed for wallets with block reasons. Run both widget tests; expect GREEN.

- [ ] **Step 6 — Verify/analyze.** Format, wallet tests, persistence lifecycle/image tests, full suite, analyzer tuple comparison and diff check.

- [ ] **Step 7 — Commit.** `git add lib/wallets/ui/wallet_list_view.dart lib/wallets/ui/wallet_editor_page.dart lib/wallets/application/wallet_editor_controller.dart lib/wallets/ui/wallets_page.dart lib/wallets/application/wallets_controller.dart test/wallets/ui/wallet_list_page_test.dart test/wallets/ui/wallet_editor_page_test.dart && git commit -m "feat(wallets): manage wallet profiles"`.

---

### Task UI-3: Mostrar detalle, saldos, historial y conciliación

**Purpose:** Presentar claramente tenencia conciliada, posición con costo conocido y diferencia, además del historial auditable.

**Files:**
- Create: `lib/wallets/ui/wallet_detail_page.dart`
- Create: `lib/wallets/ui/wallet_asset_balance_card.dart`
- Create: `lib/wallets/ui/wallet_history_list.dart`
- Create: `lib/wallets/ui/wallet_formatters.dart`
- Create: `test/wallets/ui/wallet_detail_page_test.dart`
- Modify: `lib/wallets/ui/wallets_page.dart`
- Existing symbols affected: existing date/amount formatting in monolith is observed but not imported if private.

**Consumes:** `WalletAssetProjection`, ordered `AccountingMovement` list, display currency.

**Produces:**

```dart
final class WalletDetailViewModel {
  const WalletDetailViewModel({required this.wallet,
    required this.positions, required this.history});
  final Wallet wallet;
  final List<WalletAssetProjection> positions;
  final List<AccountingMovement> history;
}
String formatAccountingAmount(AccountingAmount value, {int maxDecimals = 8});
String reconciliationWarning(WalletAssetProjection value);
```

**First RED test code:**

```dart
testWidgets('separates custody, known position and unknown difference',
    (tester) async {
  await tester.pumpWidget(detailHarness(known: '127', custody: '127.75883985'));
  expect(find.text('Tenencia conciliada'), findsOneWidget);
  expect(find.text('127.75883985 UNI'), findsOneWidget);
  expect(find.text('Posición con costo conocido'), findsOneWidget);
  expect(find.text('Diferencia sin costo base'), findsOneWidget);
  expect(find.text('+0.75883985 UNI'), findsOneWidget);
});
```

- [ ] **Step 1 — Write RED reconciliation-card test.** Fixture: known `127`, reconciled `127.75883985`; assert labels and values “Tenencia conciliada”, “Posición con costo conocido”, “Diferencia sin costo base”, `+0.75883985 UNI`, plus warning semantics. Run `flutter test test/wallets/ui/wallet_detail_page_test.dart`; expected RED: detail widgets absent.

- [ ] **Step 2 — Implement formatters and balance card.** Use projected fields only; positive/negative sign and accessible color-independent icon/text; show custody deficit separately, never label it unknown cost. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED sale-status test.** Provide `partiallyKnown` sale; assert total/known/pending quantities, demonstrated basis and “P&L conocido (no definitivo)”; ensure no “P&L total” label. Provide insufficient-custody issue and assert visible alert. Run test; expected RED before rendering.

- [ ] **Step 4 — Implement history/detail page.** Filter canonical events by explicit wallet fields, include adjustments with reason/observed/note and incompatible historical events with issue badge; sort by normalizer order. Re-run; expect GREEN.

- [ ] **Step 5 — Add empty/error/detail navigation cases.** No assets/history yields purposeful copy; tapping wallet card pushes the correct ID; archived banner remains visible. Run detail and list tests.

- [ ] **Step 6 — Verify/analyze.** Format, UI and projection tests, full suite, analyzer tuple comparison and diff check.

- [ ] **Step 7 — Commit.** `git add lib/wallets/ui/wallet_detail_page.dart lib/wallets/ui/wallet_asset_balance_card.dart lib/wallets/ui/wallet_history_list.dart lib/wallets/ui/wallet_formatters.dart lib/wallets/ui/wallets_page.dart test/wallets/ui/wallet_detail_page_test.dart && git commit -m "feat(wallets): show custody and accounting detail"`.

---

### Task UI-4: Implementar asistente de asignación con progreso

**Purpose:** Permitir atribución explícita de movimientos legacy, individual o masiva, mostrando pendientes y efecto previo.

**Files:**
- Create: `lib/wallets/ui/assignment_wizard_page.dart`
- Create: `lib/wallets/ui/assignment_progress.dart`
- Create: `lib/wallets/application/assignment_wizard_controller.dart`
- Create: `test/wallets/ui/assignment_wizard_page_test.dart`
- Modify: `lib/wallets/ui/wallets_page.dart`
- Existing symbols affected: none.

**Consumes:** `MovementAssignmentService`, `AccountingLedgerEngine`, pending/legacy movements.

**Produces:**

```dart
final class AssignmentPreview {
  const AssignmentPreview({required this.selectedIds,
    required this.targetWalletId, required this.before,
    required this.after});
  final Set<String> selectedIds;
  final String targetWalletId;
  final LedgerProjection before;
  final LedgerProjection after;
}
final class AssignmentWizardController extends ChangeNotifier {
  Set<String> get selectedIds;
  int get assignedCount;
  int get totalCount;
  AssignmentPreview preview(String walletId);
  Future<AssignmentResult> commit(String walletId);
}
```

**First RED test code:**

```dart
testWidgets('previews a two-of-three mass assignment before commit',
    (tester) async {
  await tester.pumpWidget(wizardHarness(pending: pendingFixtures(3)));
  expect(find.text('0 de 3 asignados'), findsOneWidget);
  await tester.tap(find.byKey(const Key('pending-old-1')));
  await tester.tap(find.byKey(const Key('pending-old-2')));
  await tester.tap(find.text('Vista previa'));
  await tester.pump();
  expect(find.text('2 movimientos seleccionados'), findsOneWidget);
  expect(fakeRepository.writeCount, 0);
});
```

- [ ] **Step 1 — Write RED pending/progress test.** Pump three pending items; assert `0 de 3 asignados`, select two via checkboxes, preview target wallet and assert `2 de 3` selection summary without committing. Run `flutter test test/wallets/ui/assignment_wizard_page_test.dart`; expected RED: wizard absent.

- [ ] **Step 2 — Implement controller selection/preview.** Preview applies assignment service to an in-memory document and projects before/after; it does not write. Keep IDs sorted in UI. Re-run; expect GREEN.

- [ ] **Step 3 — Write RED individual/mass commit tests.** One-item action changes one; select-all changes remaining; fake repository records one write per commit; repeated commit is unchanged. Run test; expected RED before commit wiring.

- [ ] **Step 4 — Implement transactional commit.** Call service, repository write, controller reload; show failure without clearing selection. Do not create movements. Re-run; expect GREEN.

- [ ] **Step 5 — Add `partiallyAssigned` and no-active-wallet states.** Partial transfer exposes segment selection limitation and remains pending until fully justified; no active wallet links to create flow. Assert exact explanatory text. Run test.

- [ ] **Step 6 — Verify/analyze.** Format, wizard/service/projection tests, full suite, analyzer tuple comparison and diff check.

- [ ] **Step 7 — Commit.** `git add lib/wallets/ui/assignment_wizard_page.dart lib/wallets/ui/assignment_progress.dart lib/wallets/application/assignment_wizard_controller.dart lib/wallets/ui/wallets_page.dart test/wallets/ui/assignment_wizard_page_test.dart && git commit -m "feat(wallets): assign pending movements with preview"`.

---

### Task UI-5: Capturar origen, destino y vista previa con API Radio vigente

**Purpose:** Hacer inequívocos los movimientos entre cartera propia y destino externo, validar custodia y previsualizar impacto contable.

**Files:**
- Create: `lib/wallets/ui/movement_wallet_fields.dart`
- Create: `lib/wallets/ui/movement_impact_preview.dart`
- Create: `lib/wallets/application/movement_draft_controller.dart`
- Create: `test/wallets/ui/movement_wallet_fields_test.dart`
- Modify: `lib/cripto_control_app.dart`
- Existing symbols affected: `_showAddMovementSheet` (3359), `MovementsTab` (8241) and existing movement form callbacks.

**Consumes:** active wallets, current custody, `AccountingLedgerEngine`, `AccountingMovement` constructor.

**Produces:**

```dart
final class MovementWalletDraft {
  const MovementWalletDraft({required this.sourceWalletId,
    required this.destinationType, this.destinationWalletId,
    this.externalRecipientName, this.externalDestinationPlatform});
  final String sourceWalletId;
  final DestinationType destinationType;
  final String? destinationWalletId;
  final String? externalRecipientName;
  final String? externalDestinationPlatform;
}
final class MovementImpactPreviewModel {
  const MovementImpactPreviewModel({required this.before,
    required this.after, required this.issues});
  final LedgerProjection before;
  final LedgerProjection after;
  final List<ProjectionIssue> issues;
}
```

**First RED test code:**

```dart
testWidgets('uses RadioGroup for explicit destination ownership', (tester) async {
  await tester.pumpWidget(movementWalletFieldsHarness());
  expect(find.byType(RadioGroup<DestinationType>), findsOneWidget);
  await tester.tap(find.text('Destino externo'));
  await tester.pump();
  expect(find.byKey(const Key('external-recipient')), findsOneWidget);
  expect(find.byKey(const Key('owned-destination-wallet')), findsNothing);
});
```

- [ ] **Step 1 — Write RED current-Radio-API test.** Pump fields and assert a `RadioGroup<DestinationType>` ancestor controls two `Radio<DestinationType>` values; interact through labels “Cartera propia”/“Destino externo”. Run `flutter test test/wallets/ui/movement_wallet_fields_test.dart`; expected RED: component absent.

- [ ] **Step 2 — Implement with `RadioGroup`.** Use this exact structure, without deprecated radio parameters:

```dart
RadioGroup<DestinationType>(
  groupValue: draft.destinationType,
  onChanged: onDestinationTypeChanged,
  child: const Column(children: <Widget>[
    Radio<DestinationType>(value: DestinationType.ownWallet),
    Radio<DestinationType>(value: DestinationType.external),
  ]),
)
```

Pair each radio with a tappable semantic label. Run the widget test; expect GREEN and no avoidable analyzer info.

- [ ] **Step 3 — Write RED validation matrix.** Assert source required; own destination required/different from source/external fields null; external recipient and platform required/destination wallet null; sale amount cannot exceed reconciled custody; partially-known sale shows pending-cost warning. Run test; expected RED before validation.

- [ ] **Step 4 — Implement draft controller and preview.** Build one candidate `AccountingMovement`, append to an in-memory `LedgerInput` and call `AccountingLedgerEngine`; UI renders returned deltas/issues. No formula lives in the widget. Re-run; expect GREEN.

- [ ] **Step 5 — Integrate form minimally.** Add wallet fields to `_showAddMovementSheet`; old data can choose “Sin asignar (legacy)” only when editing legacy, never for new events. Internal transfer saves one `transferOut`; external saves one `transferOut` with external fields. Add widget assertion that saved list length increases by one.

- [ ] **Step 6 — Verify/analyze.** Run formatter, field test, existing transfer tests, full suite, analyzer tuple comparison and diff check; specifically confirm no new `deprecated_member_use` diagnostic.

- [ ] **Step 7 — Commit.** `git add lib/wallets/ui/movement_wallet_fields.dart lib/wallets/ui/movement_impact_preview.dart lib/wallets/application/movement_draft_controller.dart lib/cripto_control_app.dart test/wallets/ui/movement_wallet_fields_test.dart && git commit -m "feat(wallets): capture explicit movement destinations"`.

---

### Task UI-6: Editar/eliminar con reconstrucción y cerrar accesibilidad/errores

**Purpose:** Asegurar que mutaciones reproducen el ledger completo y que todos los estados son operables y comprensibles.

**Files:**
- Create: `lib/wallets/application/wallet_movement_service.dart`
- Create: `lib/wallets/ui/wallet_error_view.dart`
- Create: `test/wallets/ui/wallet_movement_actions_test.dart`
- Create: `test/wallets/ui/wallet_accessibility_test.dart`
- Modify: `lib/wallets/ui/wallet_detail_page.dart`
- Modify: `lib/wallets/application/wallets_controller.dart`
- Modify: `lib/cripto_control_app.dart`
- Existing symbols affected: movement edit/delete callbacks around `MovementsTab` and detail route, without moving their implementations.

**Consumes:** repository, `AccountingLedgerEngine`, canonical movement ID and replacement event.

**Produces:**

```dart
final class WalletMovementMutationResult {
  const WalletMovementMutationResult(this.document, this.projection);
  final AccountingDocument document;
  final LedgerProjection projection;
}
final class WalletMovementService {
  Future<WalletMovementMutationResult> create(AccountingMovement value);
  Future<WalletMovementMutationResult> replace(String id,
    AccountingMovement value);
  Future<WalletMovementMutationResult> delete(String id);
}
```

**First RED test code:**

```dart
test('editing and deleting an adjustment rebuilds custody only', () async {
  await service.create(adjustment(id: 'adj-1', quantity: '0.75883985'));
  final edited = await service.replace(
      'adj-1', adjustment(id: 'adj-1', quantity: '0.5'));
  expect(position(edited).reconciliationDifference.toJson(), '0.5');
  final deleted = await service.delete('adj-1');
  expect(position(deleted).reconciliationDifference, AccountingAmount.zero);
  expect(performance(deleted), performanceBeforeAdjustment);
});
```

- [ ] **Step 1 — Write RED exact-rebuild action test.** Create adjustment `+0.75883985`, edit to `+0.5`, delete; after each action compare controller projection with a fresh `AccountingLedgerEngine.project(LedgerInput(...))` built from repository data and the explicit policies. Assert performance/cost/P&L unchanged. Run `flutter test test/wallets/ui/wallet_movement_actions_test.dart`; expected RED: service absent.

- [ ] **Step 2 — Implement create/replace/delete as full replay.** Validate ID uniqueness/equality, write a new document, then project all events; on repository error keep prior controller state and history. Re-run; expect GREEN.

- [ ] **Step 3 — Add sale/transfer mutation tests.** Editing external to internal requires destination fields to switch atomically; deleting an internal transfer removes both derived legs because only one event existed; insufficient-custody historical event remains visible if an earlier adjustment is deleted. Run action test; expect GREEN after validation integration.

- [ ] **Step 4 — Write RED accessibility test.** Use `SemanticsTester`; assert wallet image has name, reconciliation alert has role/live-region, buttons have labels, progress has value, errors are announced, and tap targets are at least 48 logical pixels. Run `flutter test test/wallets/ui/wallet_accessibility_test.dart`; expected RED until semantics are present.

- [ ] **Step 5 — Implement semantics and empty/error states.** Add keyed widgets for loading, no wallets, no assets, no history, persistence failure and invalid historical event. Retry never discards local displayed state. Run accessibility and all wallet UI tests; expect GREEN.

- [ ] **Step 6 — Verify and prepare H3.** Run formatter, wallet/accounting tests, full suite, analyzer tuple comparison and diff check. Review new UI files for direct arithmetic (`+`, `-`, `*`, `/`) on accounting fields; only formatting operations are allowed. Present widget evidence at H3.

- [ ] **Step 7 — Commit.** `git add lib/wallets/application/wallet_movement_service.dart lib/wallets/ui/wallet_error_view.dart lib/wallets/ui/wallet_detail_page.dart lib/wallets/application/wallets_controller.dart lib/cripto_control_app.dart test/wallets/ui/wallet_movement_actions_test.dart test/wallets/ui/wallet_accessibility_test.dart && git commit -m "feat(wallets): rebuild ledger after wallet edits"`.
