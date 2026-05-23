# CriptoControlMx V2 Roadmap

## Estado
V2 ya fue promovida a `master` y la app principal vive en `lib/cripto_control_app.dart`.

## Completado
- Motor contable de compras, ventas, entradas y salidas.
- Costo base, cantidad actual, P/L realizado, P/L no realizado y break even neto.
- UI compacta para resumen, monedas, movimientos, simulador y ajustes.
- Movimientos con filtros por moneda, tipo, fecha y texto.
- Campos opcionales por movimiento: origen, cartera y red.
- Actualización automática de precios en MXN con cache local.
- Actualización manual de precios desde la barra superior y Ajustes.
- Respaldo/importación JSON compatible con respaldos anteriores, pegado o desde archivo.
- Exportación CSV de historial, resumen y snapshots.
- Exportación XLSX de historial, resumen y snapshots.
- Exportación PDF de reporte.
- Snapshots de cartera.
- Gráficos históricos de valor, invertido y resultados desde snapshots.
- Simulador de compra y venta.

## Criterio de cierre
- `flutter test` pasa.
- `flutter analyze --no-fatal-infos --no-fatal-warnings` pasa.
- `flutter build apk --debug` pasa.
- No quedan archivos scratch de implementación V2 en `lib/`.

## Siguientes mejoras opcionales
- Publicar build release firmado.
- Migrar Gradle, Android Gradle Plugin y Kotlin a las versiones futuras recomendadas por Flutter.
