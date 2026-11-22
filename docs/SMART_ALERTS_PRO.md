# Notificaciones inteligentes Pro — CriptoControlMx

## Estado de la auditoría

- Rama de trabajo: `fix/smart-alerts-pro-audit-20261116`.
- Base: `d6b69436f578e604fac82b2b032e90089bab5389`.
- Alcance: motor de evaluación, persistencia, supervisión, integración con WorkManager y coordinación del Worker.
- Billing, publicación, firmas y PR #43 quedan fuera de este alcance.

## 1. Arquitectura

- `lib/smart_alerts/simulation_snapshot.dart`: conserva los parámetros de la simulación original.
- `lib/smart_alerts/smart_simulation_evaluator.dart`: evalúa las simulaciones con precios actuales y contempla las comisiones.
- `lib/smart_alerts/smart_alert_store.dart`: persiste las simulaciones supervisadas y el estado de las condiciones.
- `lib/smart_alerts/smart_simulation_monitor.dart`: coordina la evaluación en primer plano.
- `android/app/src/main/kotlin/mx/criptocontrolmx/app/SmartSimulationEngine.kt`: ejecuta la evaluación en segundo plano.
- `android/app/src/main/kotlin/mx/criptocontrolmx/app/AlertWorker.kt`: obtiene cotizaciones y ejecuta las alertas gratuitas y el motor inteligente.
- `lib/entitlements/pro_entitlement.dart`: contrato de lectura del derecho Pro.

El motor inteligente evalúa simulaciones. No ejecuta operaciones de compra o venta ni sustituye al motor financiero determinista de la aplicación.

## 2. Persistencia y reconciliación

La supervisión utiliza identificadores de simulaciones guardadas. Al desactivar la supervisión o eliminar una simulación, se limpia su asociación de monitoreo y su estado correspondiente.

La reconciliación elimina identificadores supervisados que ya no corresponden a simulaciones existentes. También se ejecuta durante la carga y persistencia de las simulaciones.

La carga contempla datos ausentes o JSON inválido sin omitir la reconciliación cuando se dispone de las preferencias. Los registros antiguos que no contienen los parámetros necesarios no se convierten artificialmente en simulaciones evaluables: requieren volver a guardarse.

## 3. Validación numérica

El evaluador valida precios, parámetros y resultados intermedios para rechazar valores no finitos, precios no positivos, comisiones fuera del intervalo permitido y desbordamientos.

Los datos inválidos se tratan como información insuficiente; no deben producir una alerta favorable.

Estas validaciones no modifican el esquema de persistencia de las simulaciones ni pretenden recalcular o alterar los datos canónicos del portafolio.

## 4. Estado de las alertas y anti-duplicados

El estado de cada simulación supervisada conserva la información necesaria para determinar si la condición favorable ya fue notificada.

- Una condición favorable notificada actualiza el momento de notificación.
- Una condición que deja de ser favorable limpia el momento de notificación y permite una futura notificación si vuelve a cumplirse.
- Una notificación fallida no se registra como notificada.
- Los errores de cotización y la información insuficiente no deben borrar indebidamente el estado previo.

El identificador de notificación por simulación ayuda a reemplazar la notificación correspondiente, pero no constituye por sí solo una garantía absoluta contra duplicados ante cierres del proceso o interrupciones.

## 5. WorkManager y ciclo de vida

La programación periódica utiliza el trabajo único `cripto_alerts_periodic` con política `UPDATE`. El intervalo configurado respeta el mínimo de 15 minutos de WorkManager.

La programación conserva el trabajo cuando están habilitadas las alertas gratuitas o cuando el motor Pro está activo. Si ambas condiciones están deshabilitadas, se cancela el trabajo periódico.

El trabajo inmediato utiliza el identificador único `cripto_alerts_now` con política `REPLACE`.

El Worker comparte la consulta de cotizaciones entre las alertas gratuitas y el motor inteligente. Los precios se validan individualmente antes de utilizarlos.

La ejecución del Worker está serializada mediante un bloqueo en el proceso de la aplicación. Esto evita ejecuciones simultáneas dentro de ese mismo proceso. No es una exclusión distribuida entre procesos Android diferentes ni protege por sí sola frente a una interrupción después de mostrar una notificación y antes de persistir su estado.

WorkManager no garantiza ejecución en tiempo real. Doze, ahorro de batería, conectividad y políticas del fabricante pueden retrasar el trabajo. Android 13 y posteriores requieren permiso de notificaciones para mostrar avisos.

## 6. Entitlement Pro y dependencia de Billing

`ProEntitlementReader` consulta la clave `pro_entitlement_active_v1`. La implementación disponible es de solo lectura.

La auditoría del repositorio no encontró un flujo que conceda o revoque ese derecho mediante una compra validada. Por tanto:

- El motor y la lectura del entitlement están implementados.
- La activación comercial de Pro depende de una futura integración de Billing.
- Billing deberá validar la compra y escribir el entitlement.
- La revocación también deberá actualizarlo.
- El ciclo de vida de esa integración deberá actualizar la programación de tareas para reflejar el cambio de entitlement.

Mientras no exista ese flujo, no debe interpretarse el motor implementado como una suscripción Pro operativa. Las alertas gratuitas conservan su funcionamiento independiente.

## 7. Validación técnica ejecutada

Resultados reportados durante esta auditoría:

| Validación | Resultado |
|---|---|
| `flutter test test/smart_alerts/smart_simulation_monitor_test.dart` | 22 pruebas aprobadas |
| `flutter analyze lib/cripto_control_app.dart lib/smart_alerts test/smart_alerts` | Sin errores; advertencias e información preexistentes |
| `:app:compileDebugKotlin` | `BUILD SUCCESSFUL` |
| `git diff --check` | Sin errores de whitespace reportados |

La compilación Kotlin se ejecutó con:

`.\android\gradlew.bat -p .\android :app:compileDebugKotlin`

La compilación y las pruebas anteriores acreditan esas validaciones concretas; no equivalen a una prueba de estrés de concurrencia, una prueba de todos los ciclos de vida Android ni una validación de compras reales.

## 8. Pendientes y límites del alcance

1. Integrar Billing y la concesión/revocación validada del entitlement Pro.
2. Conectar los cambios de entitlement con la actualización de WorkManager.
3. Probar en dispositivos reales los permisos, restricciones de batería, conectividad y comportamiento en segundo plano.
4. Realizar pruebas específicas de interrupción y concurrencia si se requiere una garantía más fuerte de entrega única.

## 9. Cierre

La implementación del motor de Notificaciones Inteligentes Pro, su persistencia, evaluación y ejecución mediante WorkManager cuenta con validaciones técnicas reportadas en esta auditoría.

La integración comercial de Pro permanece pendiente de Billing. No se considera terminada ni validada por el solo hecho de que el motor esté implementado.

Este cierre documental no autoriza staging, commit, merge, deploy, publicación ni modificaciones en Billing o PR #43.
