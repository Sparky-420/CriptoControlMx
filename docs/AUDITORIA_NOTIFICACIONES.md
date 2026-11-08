# Auditoría inicial — notificaciones de CriptoControlMx

**Fecha:** 2026-11-08  
**Rama inspeccionada:** `release-candidate-fenix-20261104`  
**Código de referencia:** `31a2bbe180ccfdae3c291778cf8f7ab793d41753` (Fase 4.7)

## Arquitectura encontrada

1. Flutter usa `PriceAlertService` en `lib/services/price_alert_service.dart`.
2. Flutter invoca el canal `mx.criptocontrolmx.app/price_alerts`.
3. `MainActivity.kt` implementa:
   - `initialize`
   - `areNotificationsAllowed`
   - `requestNotificationPermission`
   - `configureAutomaticAlerts`
   - `runAutomaticAlertCheckNow`
   - `showPriceAlert`
4. La programación periódica usa `PeriodicWorkRequestBuilder<AlertWorker>` y trabajo único `cripto_alerts_periodic`.
5. La comprobación inmediata usa `OneTimeWorkRequestBuilder<AlertWorker>`.
6. `AlertWorker.kt` consulta CoinGecko, lee preferencias Flutter (`FlutterSharedPreferences`, prefijo `flutter.`), calcula alertas de mercado/recuperación y publica notificaciones Android.
7. El manifiesto declara INTERNET y POST_NOTIFICATIONS. La dependencia Android declara WorkManager `2.9.1`.

## Hallazgos verificables

- El sistema de trabajo en segundo plano ya existe; no es correcto asumir que la app carece de WorkManager.
- El intervalo mínimo aplicado en Android es 15 minutos. Aunque Flutter ofrece 15, 30, 60, 360 y 1440 minutos, WorkManager no garantiza ejecución exacta en esos horarios.
- Al activar alertas automáticas, Flutter solicita permiso si hace falta, persiste la preferencia, programa el trabajo y solicita una comprobación inmediata.
- Al cargar datos de la app, Flutter vuelve a cargar la configuración y llama a `configureAutomaticAlerts`, lo que debería reconciliar la programación al abrir la app.
- El Worker devuelve éxito si la opción automática está apagada, o si tanto alertas de precio como de recuperación están apagadas.
- Si falla la consulta de precios o no hay precios, devuelve `Result.retry()`.
- La lógica nativa de notificaciones comprueba permiso POST_NOTIFICATIONS en Android 13+ y el estado general de notificaciones.
- El código no muestra una solicitud de exención de optimización de batería ni un diagnóstico de restricciones específicas del fabricante.
- La programación y el Worker no constituyen una garantía de ejecución tras un cierre forzado del paquete por el usuario; Android detiene trabajos hasta que el usuario vuelve a iniciar la app. Las políticas de batería del fabricante también pueden retrasar trabajo.

## Riesgos que requieren comprobación

1. **Restricciones de batería del dispositivo:** comprobar optimización de batería y administración automática en Motorola Edge 50 Pro. No pedir exenciones indiscriminadamente; primero medir.
2. **Estado de programación:** consultar WorkManager (estado de trabajo único/periódico, próxima ejecución, fallos y backoff) desde una pantalla diagnóstica temporal o logs seguros.
3. **Permisos/canal:** revisar permiso POST_NOTIFICATIONS y que el canal `cripto_alerts` no esté silenciado.
4. **Conectividad/API:** el Worker depende de CoinGecko y devuelve retry si no obtiene precios. Revisar respuesta HTTP, límites y backoff.
5. **Datos leídos por Worker:** confirmar que los nombres y formatos de movimientos/preferencias coinciden con la persistencia actual y que los cálculos nativos coinciden con Dart.
6. **Pruebas de ciclo de vida:** separar app en segundo plano, proceso eliminado por Android, dispositivo reiniciado y app detenida forzosamente por el usuario. Son escenarios distintos.

## Diagnóstico provisional

La implementación contiene los componentes básicos para alertas locales en segundo plano. El síntoma «las notificaciones llegan hasta que abro la aplicación» no permite concluir por sí solo cuál es la causa. Abrir la app puede reactivar procesos, actualizar precios, reconciliar WorkManager o salir de restricciones del fabricante. No debe cambiarse la lógica financiera ni reemplazarse el Worker antes de obtener evidencia del estado de la tarea y de la política de batería.

## Plan de pruebas de campo

| Escenario | Procedimiento | Evidencia |
|---|---|---|
| App en primer plano | Habilitar alertas y provocar umbral de prueba | Notificación recibida |
| App en segundo plano | Salir con Inicio y esperar más de un intervalo | Hora de ejecución y notificación |
| Pantalla apagada | Repetir con pantalla apagada | Ejecución/notificación |
| Reinicio | Reiniciar dispositivo sin abrir app | Si WorkManager retoma programación |
| Cierre forzado | Forzar detención desde Ajustes | Documentar que Android puede detener tareas |
| Ahorro de batería | Repetir con ahorro activado/desactivado | Diferencia de ejecución |
| Sin red / API limitada | Desconectar red o simular error | Retry/backoff sin pérdida de configuración |
| Permiso/canal | Revocar permiso o silenciar canal | Estado detectado y mensaje al usuario |

## Criterio para aceptar una corrección

- No perder preferencias, referencias de precios ni movimientos.
- No duplicar trabajos periódicos.
- Deshabilitar alertas cancela el trabajo periódico.
- Cambiar intervalo actualiza el trabajo existente.
- Los errores de red se reintentan sin bloquear la app.
- Pruebas automatizadas para la lógica que pueda extraerse/testearse.
- Validación en el dispositivo real y documentación de límites de Android.

## No modificado en esta auditoría

No se modificaron Worker, MainActivity, fórmulas financieras, persistencia, permisos, Firebase ni claves de firma. Este documento registra el estado observado y evita una corrección especulativa.
