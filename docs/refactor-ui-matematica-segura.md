# Refactor UI matematica segura

Esta rama existe para separar UI y calculo por fases.

Regla: no tocar master y no modificar formulas financieras durante la extraccion visual.

## Base

La rama `refactor-ui-matematica-segura` sale de `ui-premium-sin-tocar-matematica`.

`master` queda intacta.

## Avance de los 5 pasos

### 1. Tema y tokens UI

Agregado:

- `lib/ui/premium_colors.dart`

Uso actual:

- `lib/ui/premium_boot_gate.dart` ya consume los colores extraidos.

### 2. Componentes visuales reutilizables

Agregado:

- `lib/ui/components/premium_panels.dart`

Incluye copias de frontera para:

- `CardPanel`
- `SheetHeader`
- `MetricTile`
- `SimpleValue`
- `InfoLine`
- `StatusPill`
- `EmptyState`

### 3. Modelos de dominio

Agregado:

- `lib/domain/portfolio_models.dart`

Incluye copias de frontera para:

- `MovementType`
- `ScenarioType`
- `Movement`
- `CoinStats`
- `CoinAudit`
- `PortfolioTotals`
- `ScenarioResult`
- `CoinSnapshot`
- `PortfolioSnapshot`
- helpers JSON basicos

### 4. Matematica de cartera

Agregado:

- `lib/domain/portfolio_math.dart`
- `lib/domain/portfolio_state.dart`

Incluye copias de frontera para:

- `computeStats`
- `auditCoin`
- `totals`
- `wouldCreateInvalidPosition`
- proyeccion `PortfolioState.fromInputs`

La logica se copio sin cambiar formulas respecto al archivo monolitico.

### 5. Navegacion y tabs

Agregado:

- `lib/ui/tabs/app_tab_registry.dart`
- `lib/ui/navigation/main_navigation_bar.dart`

Centraliza etiquetas e iconos de las tabs:

- Resumen
- Movimientos
- Simular
- Monedas
- Ajustes

## Pruebas agregadas

Agregado:

- `test/portfolio_math_test.dart`
- `test/portfolio_state_test.dart`
- `test/portfolio_models_test.dart`
- `test/formatters_test.dart`
- `test/main_navigation_bar_test.dart`

Cubren:

- venta con costo promedio
- resultado realizado
- valor actual
- bloqueo de venta mayor a la posicion disponible
- totales proyectados desde `PortfolioState`
- compatibilidad JSON con aliases legacy y en español
- formulas de break-even neto en `CoinStats`
- formatos monetarios, cripto, fechas y CSV
- render y seleccion de tabs en `MainNavigationBar`

## Guardrails agregados

Agregado:

- `tool/refactor_guard.dart`

El workflow ejecuta:

- `dart run tool/refactor_guard.dart`
- `flutter analyze --no-fatal-infos --no-fatal-warnings`
- `flutter test`
- `flutter build apk --debug`

## Estado tecnico

Estos archivos nuevos aun no sustituyen completamente el monolito `lib/cripto_control_app.dart`.

Motivo: evitar un cambio masivo que pueda romper la APK funcional.

## Proximo corte seguro

1. Correr `flutter analyze`.
2. Correr `flutter test`.
3. Conectar primero solo `MainNavigationBar` porque es de bajo riesgo.
4. Conectar `premium_panels.dart` componente por componente.
5. Conectar modelos y `PortfolioMath` solo despues de comparar outputs con la implementacion actual.

## Garantia de rollback

Si algo falla, basta con volver a:

- `ui-premium-sin-tocar-matematica`, o
- `master`

No hay merge automatico hacia `master`.
