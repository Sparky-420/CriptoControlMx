# CriptoControlMx V2 Roadmap

## Objetivo
Construir la versión 2 sobre la base contable correcta de la app estable (`master`) y copiar únicamente las mejoras de UX, filtros y exportación de la app oscura, sin heredar sus errores de cálculo.

## Principio rector
- La lógica contable de `master` es la fuente de verdad.
- La app oscura se toma solo como referencia visual y funcional.
- Ninguna mejora de UI puede romper costo base, cantidades actuales, P/L realizado o P/L no realizado.

## Qué conservar de la app clara
1. Modelo de movimientos: `buy`, `sell`, `transferIn`, `transferOut`.
2. Lógica de cálculo por moneda:
   - cantidad actual
   - costo base actual
   - P/L realizado
   - P/L no realizado
   - break even bruto y neto
3. Validación para no permitir posiciones negativas.
4. Importación/exportación JSON.
5. Configuración de comisión de salida.

## Qué copiar de la app oscura
1. Dashboard más limpio y visual.
2. Historial de movimientos más potente.
3. Filtros más útiles.
4. Exportación CSV y PDF.
5. Tarjetas/resumen más compactos.
6. Mejor jerarquía visual para portafolio, historial y análisis.

## Fase 1 - Motor confiable con interfaz mejorada
Objetivo: mejorar UX sin tocar la lógica central.

### Tareas
- Rediseñar `SummaryTab` con layout más limpio y compacto.
- Rediseñar `MovementsTab` con chips visuales por tipo de movimiento.
- Mejorar `CoinsTab` para mostrar métricas clave sin tanto texto corrido.
- Añadir colores por estado:
  - verde = arriba de break even neto
  - rojo = abajo de break even neto
  - gris = sin posición abierta
- Mejorar estados vacíos.

### Criterio de salida
Los números deben coincidir exactamente con `master` antes y después del rediseño.

## Fase 2 - Historial y filtros tipo V2
Objetivo: traer lo mejor de la app oscura sin tocar el motor contable.

### Tareas
- Historial con columnas y filtros más completos:
  - moneda
  - tipo
  - rango de fechas
  - texto libre en notas
- Etiquetas/acciones visibles:
  - BUY
  - SELL
  - TRANSFER_IN
  - TRANSFER_OUT
- Preparar estructura para origen/cartera/red aunque inicialmente sea opcional.

### Criterio de salida
Filtrar no debe alterar ninguna cifra de resumen; solo la vista.

## Fase 3 - Exportaciones útiles
Objetivo: sacar información sin romper integridad.

### Tareas
- Exportar historial a CSV desde los movimientos reales.
- Exportar resumen por moneda a CSV.
- Preparar exportación PDF simple del resumen.

### Criterio de salida
Los archivos exportados deben reconstruir exactamente el historial o el resumen mostrado.

## Fase 4 - Simuladores de decisión
Objetivo: que la app deje de ser solo registro y se vuelva herramienta.

### Tareas
- Simulador de compra:
  - monto MXN
  - moneda
  - comisión
  - impacto en promedio
  - nuevo break even
- Simulador de venta:
  - cantidad o monto
  - precio estimado
  - comisión
  - P/L realizado esperado
  - cantidad restante
  - costo base restante

### Criterio de salida
Los simuladores no modifican cartera real; solo proyectan.

## Regla de trabajo
- Todo desarrollo V2 ocurre en `experimental`.
- Solo pasa a `master` lo que ya haya sido validado contra los números de la app estable.

## Próxima implementación recomendada
Primero atacar Fase 1:
1. rediseño de `SummaryTab`
2. rediseño de `CoinsTab`
3. chips visuales en `MovementsTab`
4. estados vacíos

Esa combinación da sensación de V2 sin tocar el corazón contable.
