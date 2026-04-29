# CriptoControlMx

Aplicación Flutter para registrar movimientos de criptomonedas, calcular costo base, break even, objetivos netos y respaldos JSON.

## Ramas de trabajo

- `master`: base actual publicada desde Firebase Studio.
- `stable`: rama para la versión estable y validada.
- `experimental`: rama para pruebas, cambios de UI y funciones nuevas sin romper la base.

## Estado actual

La app incluye:

- registro, edición y borrado de movimientos
- cálculo de costo base y P/L
- break even bruto y neto
- objetivos netos por comisión de salida
- respaldo e importación JSON
- icono y nombre de app `CriptoControlMx`

## Flujo recomendado

1. cambios confiables y revisados -> `stable`
2. ideas nuevas, prototipos o pruebas -> `experimental`
3. `master` se conserva como punto de origen histórico de la migración desde Firebase Studio
