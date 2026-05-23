# CriptoControlMx

Aplicación Flutter para registrar movimientos de criptomonedas, calcular costo base, break even, objetivos netos y respaldos JSON.

## Ramas de trabajo

- `master`: rama estable y principal.
- `experimental`: rama para la versión 2, pruebas de UI, importadores y funciones nuevas.
- `stable`: rama histórica sincronizada con `master` para no perder referencia anterior.

## Estado actual

La app incluye:

- registro, edición y borrado de movimientos
- cálculo de costo base y P/L
- break even bruto y neto
- objetivos netos por comisión de salida
- actualización automática y manual de precios en MXN
- filtros de movimientos por moneda, tipo, fecha y texto
- campos opcionales de origen, cartera y red por movimiento
- simulador de compra y venta
- snapshots de cartera
- exportación CSV, XLSX y PDF
- respaldo e importación JSON
- icono y nombre de app `CriptoControlMx`

## Flujo recomendado

1. todo lo confiable y validado vive en `master`
2. todo experimento o versión 2 vive en `experimental`
3. `stable` se conserva solo como rama espejo/histórica de `master`
