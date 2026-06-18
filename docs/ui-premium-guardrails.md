# CriptoControlMx — UI premium sin tocar matemática

## Rama

`ui-premium-sin-tocar-matematica`

## Objetivo

Mejorar la percepción de calidad visual sin alterar el núcleo financiero de la app.

## Guardrails matemáticos

No se modificaron:

- `_computeStats()`
- costo base
- promedio histórico
- cálculo de venta
- resultado realizado / no realizado
- break-even neto
- comisión de salida
- estructura JSON de movimientos
- importación/exportación de respaldos
- snapshots
- persistencia de precios y movimientos

## Cambios aplicados

### 1. Arranque premium controlado

Se agregó `lib/ui/premium_boot_gate.dart` para pintar una primera pantalla Flutter antes de cargar `CriptoControlApp`.

Esto evita que el usuario vea una pantalla blanca mientras se ejecuta el seed inicial del respaldo incluido.

### 2. Splash nativo oscuro

Se actualizaron:

- `android/app/src/main/res/drawable/launch_background.xml`
- `android/app/src/main/res/drawable-v21/launch_background.xml`
- `android/app/src/main/res/values/styles.xml`
- `android/app/src/main/res/values-night/styles.xml`

El objetivo es evitar el salto visual blanco/rosado antes del primer frame de Flutter.

### 3. Mensaje visual de confianza

La pantalla inicial comunica explícitamente:

- app: `CriptoControlMx`
- propósito: `Control matemático de cartera`
- estado: `Preparando cartera local sin alterar cálculos...`
- sello visual: `Fórmulas intactas`

## Inspiración Canva

Canva se usó como punto de referencia de dirección visual: estética fintech oscura, jerarquía limpia, sensación de producto serio y foco en confianza.

No se incorporó ningún asset externo de Canva en el código para evitar dependencia visual o problemas de propiedad.

## Próxima capa recomendada

La siguiente iteración debería tocar `lib/cripto_control_app.dart`, pero con una regla estricta: separar primero UI de cálculo.

Orden recomendado:

1. Extraer tema a `lib/ui/premium_theme.dart`.
2. Extraer componentes visuales a `lib/ui/components/`.
3. Mantener modelos y cálculo en archivos propios.
4. Recién después rediseñar tarjetas, navegación y páginas internas.

Eso permite mejorar toda la interfaz sin meter mano accidental en fórmulas.
