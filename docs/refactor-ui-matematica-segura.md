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

Incluye copias de frontera para:

- `computeStats`
- `auditCoin`
- `totals`
- `wouldCreateInvalidPosition`

La logica se copio sin cambiar formulas respecto al archivo monolitico.

### 5. Navegacion y tabs

Agregado:

- `lib/ui/tabs/app_tab_registry.dart`

Centraliza etiquetas e iconos de las tabs:

- Resumen
- Movimientos
- Simular
- Monedas
- Ajustes

## Estado tecnico

Estos archivos nuevos aun no sustituyen completamente el monolito `lib/cripto_control_app.dart`.

Motivo: evitar un cambio masivo que pueda romper la APK funcional.

## Proximo corte seguro

1. Correr `flutter analyze`.
2. Conectar primero solo `AppTabRegistry` porque es de bajo riesgo.
3. Conectar `premium_panels.dart` componente por componente.
4. Conectar modelos y `PortfolioMath` solo despues de comparar outputs con la implementacion actual.

## Garantia de rollback

Si algo falla, basta con volver a:

- `ui-premium-sin-tocar-matematica`, o
- `master`

No hay merge automatico hacia `master`.
