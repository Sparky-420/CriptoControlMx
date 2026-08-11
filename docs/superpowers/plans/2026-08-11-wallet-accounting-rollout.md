# Wallet Accounting Rollout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar la arquitectura de carteras contables aprobada mediante cuatro planes ejecutables, ordenados y verificables, sin alterar la semántica contable histórica ni introducir deuda nueva de análisis estático.

**Architecture:** El ledger canónico es la única fuente de verdad. Custodia y rendimiento son proyecciones separadas, deterministas y reconstruibles. `cripto_control_app.dart` permanece como adaptador temporal hasta que UI, persistencia e I/O consuman las nuevas interfaces.

**Tech Stack:** Flutter/Dart 3.9, `shared_preferences`, JSON, `excel`, Firebase/Google Drive existentes, Kotlin/Android para imágenes privadas; sin cambios en `pubspec.yaml`.

## Global Constraints

- Base inmutable de planificación: `6ac4d0a86f4f4de0a3ea5b70c87f61cc898fb754` en `feature/carteras-contables`.
- Baseline: 43/43 pruebas; 30 diagnósticos preexistentes de `flutter analyze` (11 warnings, 19 infos), todos documentados por archivo, regla y mensaje; `git diff --check` limpio.
- Cada tarea termina con comparación estructural contra `docs/superpowers/baselines/2026-08-10-wallets-baseline.md`; cero diagnósticos nuevos y total final menor o igual a 30.
- No modificar versión ni dependencias. No generar APK/AAB de distribución. El único build permitido por el plan es `flutter build apk --debug` en la verificación final.
- No tocar, mover, copiar, eliminar ni agregar APK, `play_store_assets/` o `qa_visual/`.
- No refactorizar de forma general `lib/cripto_control_app.dart`; sólo añadir adaptadores y puntos de entrada acotados y cubiertos.
- Cantidades contables se representan con `AccountingAmount`; `double` sólo se usa en el borde heredado o visual.
- Los saldos son derivados. Ningún repositorio persiste una proyección como fuente de verdad.
- Una transferencia interna es exactamente un `AccountingMovement` persistido de tipo `transferOut`, con `destinationType: DestinationType.ownWallet`, `sourceWalletId` y `destinationWalletId`; el normalizador deriva dos piernas y nunca persiste una segunda.
- No se deduce propiedad por nombre de plataforma.
- `balanceAdjustment` modifica únicamente custodia y conciliación; nunca lotes, costo promedio, capital invertido ni P&L.
- `SaleCostConsumptionPolicy.knownFirst` aplica únicamente a ventas. `TransferCostAllocationPolicy.proportional` aplica a transferencias internas y externas.
- Déficit de custodia y cantidad de costo desconocido son estados distintos.
- Las comisiones se aplican una sola vez, con `FiatFeeTreatment` explícito.
- Los movimientos legacy globales permanecen en `virtual:unassigned` hasta asignación explícita.

---

## Orden de ejecución y dependencias

| Orden | Plan | Entrada | Salida | Dependencia |
|---:|---|---|---|---|
| 1 | `2026-08-11-wallet-ledger-core.md` | Especificación aprobada y baseline verde/autorizada | Dominio, normalización, proyecciones y adaptador legacy probados | Ninguna |
| 2 | `2026-08-11-wallet-persistence-migration.md` | API pública de CORE-1 a CORE-6 estable | Documento v3, migración, repositorios, imágenes y backup compatibles | Ledger core |
| 3 | `2026-08-11-wallet-ui-integration.md` | Repositorios y proyecciones estables | Flujo de Carteras y formularios integrado desde “Más” | Core + persistencia |
| 4 | `2026-08-11-wallet-io-verification.md` | UI e I/O conectados al documento v3 | Caracterización horaria, import/export completo, E2E, análisis y build debug | Core + persistencia + UI |

No se solapan planes. Un plan puede comenzar sólo después de que el commit de salida del anterior tenga pruebas verdes y comparación de análisis aceptada.

## Estrategia temporal de compatibilidad con el monolito

1. El nuevo código vive bajo `lib/accounting/` y `lib/wallets/`; no importa símbolos privados del monolito.
2. `LegacyMovementAdapter` convierte el mapa JSON de `Movement` a `AccountingMovement`; `LegacyFinancialAdapter` convierte `LedgerProjection` a DTOs neutrales que el monolito adapta a `CoinStats`, `CoinAudit` y `PortfolioTotals`. `AccountingLedgerEngine` recibe un `LedgerInput` completo. Ningún archivo bajo `lib/accounting/` importa `cripto_control_app.dart`.
3. `_loadData` y `_saveData` delegan gradualmente en `AccountingRepository`; la lista heredada `_movements` se conserva como vista adaptada durante el rollout.
4. Exportadores e importadores reciben `AccountingDocument`; los encabezados históricos no cambian de posición y los campos v3 se anexan.
5. Sólo al terminar IO-5 se considera seguro retirar rutas de lectura duplicadas; esa retirada queda fuera del alcance de estos planes.

## Criterios de entrada y salida

### Entrada global

- Rama y commit coinciden con la base aprobada.
- Worktree limpio; checkout original intacto.
- Especificación y baseline leídas completas.
- No existen cambios ajenos en los archivos de la tarea.

### Salida por tarea

- Prueba RED observada por la razón indicada.
- Implementación mínima GREEN.
- Regresiones de su subsistema verdes.
- `git diff --check` limpio.
- Comparación por archivo, severidad, regla y mensaje contra la baseline sin diagnósticos nuevos.
- Commit limitado a los archivos enumerados en la tarea.

### Salida global

- Flujo crear → asignar → guardar → reabrir → calcular → mostrar → editar → eliminar → exportar → importar → conciliar verde.
- JSON v3 y respaldos legacy compatibles.
- CSV/XLSX conservan columnas históricas y anexan las nuevas.
- 0 diagnósticos nuevos y total de `flutter analyze` menor o igual a 30.
- `flutter test`, `git diff --check` y `flutter build apk --debug` exitosos.

## Puntos de revisión humana

| Puerta | Momento | Evidencia para revisar | Decisión requerida |
|---|---|---|---|
| H1 | Después de CORE-6 | API pública del dominio, casos de venta/transferencia/ajuste y adaptador legacy | Aprobar semántica antes de persistir |
| H2 | Después de PERSIST-6 | JSON v3, reporte de migración, política de imágenes y restauración | Aprobar compatibilidad y privacidad |
| H3 | Después de UI-6 | Capturas/pruebas de widgets, textos de advertencia y flujo de asignación | Aprobar UX antes del E2E |
| H4 | Después de IO-5 | Matriz final, diff de análisis, pruebas, build debug y riesgos | Autorizar integración posterior |

## Matriz de cobertura de la especificación

| Requisito | Plan / tarea | Prueba escrita primero | Criterio de aceptación |
|---|---|---|---|
| Cantidad decimal exacta y JSON canónico | CORE-1 | `accounting_amount_test.dart` | Operaciones y round-trip sin pérdida decimal |
| `Wallet`, enums y estados aprobados | CORE-1 | `wallet_test.dart` | Firmas y serialización v3 exactas |
| Ampliación compatible de `Movement` | CORE-1, CORE-6 | `accounting_movement_test.dart`, `legacy_financial_adapter_test.dart` | Legacy entra sin perder campos; nuevos campos no se infieren por plataforma |
| Normalización, validación y orden fecha/ID | CORE-2 | `movement_normalizer_test.dart` | Orden estable por `occurredAt`, luego `id`; errores tipados |
| Custodia separada de rendimiento | CORE-3, CORE-4 | `custody_projection_test.dart`, `performance_projection_test.dart` | Cambiar ajuste no cambia costo ni P&L |
| Ajuste positivo/negativo sólo de custodia | CORE-3 | `custody_projection_test.dart` | Diferencia = tenencia conciliada − posición conocida |
| Venta menor, igual y mayor a posición conocida | CORE-4 | `sale_known_first_test.dart` | `complete` o `partiallyKnown`; nunca costo cero implícito |
| Custodia insuficiente | CORE-4 | `sale_known_first_test.dart` | `insufficientCustody`; historial preservado |
| Transferencia proporcional, no known-first | CORE-5 | `transfer_projection_test.dart` | Segmentos conocido/desconocido salen proporcionalmente |
| Transferencia interna en un movimiento | CORE-2, CORE-5 | `movement_normalizer_test.dart`, `transfer_projection_test.dart` | Una entrada persistida produce dos piernas derivadas |
| Transferencia externa inequívoca | CORE-5 | `transfer_projection_test.dart` | Sin acreditación a cartera propia |
| Comisiones mismo activo, otro cripto, fiat y combinadas | CORE-5 | `fee_projection_test.dart` | Cada cargo se aplica una vez al activo/costo correcto |
| Reconstrucción tras crear, editar y eliminar | CORE-3, UI-6 | `ledger_rebuild_test.dart`, `wallet_movement_actions_test.dart` | Replay total produce estado exacto sin deltas residuales |
| Justificar una diferencia sin duplicar tenencia | CORE-3 | `ledger_rebuild_test.dart` | El movimiento real aporta custodia/costo y el ajuste aplica sólo el remanente no enlazado |
| Resultado combinado y cuatro estados de completitud | CORE-6 | `accounting_ledger_engine_test.dart` | Resultado tipado con `complete`, `partiallyKnown`, `pendingAssignment`, `unassignedLegacy`, cantidades, causa e IDs |
| Adaptador mínimo al motor anterior | CORE-6 | `legacy_financial_adapter_test.dart` | Resultados legacy sin cambiar método de costo promedio conocido |
| Repositorios y documento v3 | PERSIST-1 | `accounting_repository_test.dart` | Escritura atómica lógica y lectura v3 idempotente |
| Migración legacy y agrupador virtual | PERSIST-2 | `accounting_migrator_test.dart` | `virtual:unassigned`, sin atribución automática ni duplicados |
| Coherencia temporal entre lista legacy y documento v3 | PERSIST-2B | `legacy_persistence_bridge_test.dart` | Carga prioriza v3; vista legacy guarda sólo v3 y conserva campos canónicos/borrados explícitos |
| Asignación individual/masiva | PERSIST-3 | `movement_assignment_service_test.dart` | Sólo IDs elegidos cambian; reintento no duplica |
| Imágenes privadas, 1024 px, PNG/JPEG, SHA-256 | PERSIST-4 | `wallet_image_service_test.dart`, prueba Kotlin | Archivo privado y metadatos verificables sin dependencia nueva |
| Backup/restauración de imágenes local/nube | PERSIST-5 | `accounting_backup_codec_test.dart` | Base64 local/Drive y chunks Firebase restauran mismo hash |
| Archivar/restaurar y evitar borrado destructivo | PERSIST-6 | `wallet_lifecycle_service_test.dart` | Cartera con historial no se elimina; reasignación total es atómica; archivo/restauración conserva historial |
| Entrada “Carteras” desde “Más” | UI-1 | `wallet_entry_point_test.dart` | Navegación accesible sin alterar tabs existentes |
| Resumen, listado, alta y edición | UI-2 | `wallet_list_page_test.dart`, `wallet_editor_page_test.dart` | Nombre/imagen/proveedor/color/notas persistidos |
| Saldos, historial y advertencia de conciliación | UI-3 | `wallet_detail_page_test.dart` | Tenencia, posición conocida y diferencia separadas |
| Asistente de asignación y progreso | UI-4 | `assignment_wizard_page_test.dart` | Pendientes y avance coherentes con servicio de asignación |
| Origen, destino propio/externo y vista previa | UI-5 | `movement_wallet_fields_test.dart` | Destino inequívoco; sin inferencia por plataforma |
| API vigente sin `Radio` obsoleto | UI-5 | `movement_wallet_fields_test.dart` | `RadioGroup` controla selección; analyze sin diagnóstico nuevo |
| Edición/eliminación, vacíos, errores y accesibilidad | UI-6 | `wallet_movement_actions_test.dart`, `wallet_accessibility_test.dart` | Rebuild exacto y semántica etiquetada |
| Caracterización 30/07/2026 20:54 | IO-1 | `movement_datetime_roundtrip_test.dart` | Trazabilidad completa; parche sólo si RED demuestra causa |
| JSON import/export completo y legacy | IO-2 | `accounting_json_io_test.dart` | Campos de ajuste, cartera, motivo, observado y notas sobreviven |
| CSV/XLSX históricos + columnas nuevas | IO-3 | `accounting_tabular_io_test.dart` | Encabezados previos conservan orden; nuevos se anexan |
| Ciclo integral requerido | IO-4 | `wallet_accounting_flow_test.dart` | Todos los verbos del flujo sobreviven a reapertura/importación |
| Caso Mi Mercado Pago → Bitso externo | CORE-5, IO-4 | `transfer_projection_test.dart`, `wallet_accounting_flow_test.dart` | 1 UNI recibido, 0.00167532 fee, 1.00167532 debitado, observado 127.75883985, P&L $0, sin destino propio |
| Regresión, analyze comparado y build debug | IO-5 | Suite completa | 0 diagnósticos nuevos, <=30 total, build debug exitoso |

## Protocolo de comparación de `flutter analyze`

Cada tarea genera `build/verification/flutter-analyze-current.txt` mediante:

```powershell
New-Item -ItemType Directory -Force build/verification | Out-Null
flutter analyze 2>&1 | Tee-Object build/verification/flutter-analyze-current.txt
dart run tool/compare_analyze_baseline.dart `
  docs/superpowers/baselines/2026-08-10-wallets-baseline.md `
  build/verification/flutter-analyze-current.txt
```

El comparador, creado en CORE-1 y probado con fixtures, compara la tupla `(archivo, severidad, regla, mensaje)`, falla ante cualquier tupla nueva y también falla si el total supera 30. El archivo de salida bajo `build/` no se agrega a Git.

## Entregables por plan

- Core: tipos públicos, validación, normalización, proyecciones, adaptadores y pruebas unitarias.
- Persistencia: documento v3, migración, repositorios, imágenes, backup, lifecycle y pruebas.
- UI: páginas y componentes de carteras, integración acotada y pruebas de widgets.
- I/O y verificación: caracterización horaria, codecs/exportadores, E2E, comparación final y build debug.

## Recomendación de ejecución

Usar `superpowers:subagent-driven-development` en una sesión posterior, respetando el orden estricto y las puertas H1–H4. No iniciar implementación desde este documento.
