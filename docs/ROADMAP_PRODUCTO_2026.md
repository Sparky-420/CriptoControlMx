# CriptoControlMx — hoja de ruta del producto

**Fecha:** 2026-11-08  
**Rama de trabajo:** `work/roadmap-producto-notificaciones-20261108`  
**Base técnica:** HEAD de Fase 4.7, commit `31a2bbe180ccfdae3c291778cf8f7ab793d41753`  
**Objetivo:** consolidar una base de desarrollo estable. Este documento no representa una decisión de publicación ni autoriza fusionar PRs.

## Principios

1. Preservar los datos financieros y la compatibilidad con los registros existentes.
2. Separar cambios funcionales en PRs pequeños y verificables.
3. No considerar terminada una función solo porque CI esté verde: exigir pruebas automatizadas y validación en dispositivo.
4. No introducir servicios, costos recurrentes ni dependencias de terceros sin documentar su propósito, privacidad y alternativa.
5. Mantener la app útil sin conexión para las funciones que ya son locales.

## Estado observado en el repositorio

- Aplicación Flutter Android, identificador `mx.criptocontrolmx.app`.
- Persistencia local con SharedPreferences y un repositorio contable canónico con adaptadores de compatibilidad.
- Firebase Core, Auth, Firestore, Analytics y Crashlytics están declarados; Analytics y Crashlytics respetan consentimiento local.
- Exportación PDF/XLSX, respaldo JSON, Google Drive y lectura OCR están presentes en dependencias/código.
- Existe un canal nativo Android para alertas y un `AlertWorker` con WorkManager.
- No se encontró dependencia de Google Play Billing ni de compras dentro de la app en el manifiesto de dependencias revisado.
- No se encontró integración de IA en las dependencias revisadas.
- El `pubspec.yaml` leído en la rama base declara `1.0.0-beta.13+14`; el versionado debe reconciliarse antes de generar artefactos nuevos.

## Fases y criterios de salida

### F0 — Base reproducible y control de cambios
- [ ] Mantener Fase 4.7 como punto de partida sin fusionar automáticamente PR #42.
- [ ] Establecer una rama de trabajo independiente y PRs por tema.
- [ ] Registrar versión, commit, workflow y artefacto de cada candidato.
- [ ] Confirmar que los datos existentes sobreviven actualización, cierre forzado y reapertura.
- **Salida:** CI completo y regresión de datos aprobada en dispositivo.

### F1 — Notificaciones fiables en segundo plano
- [ ] Auditar el ciclo completo: preferencias Flutter, canal MethodChannel, WorkManager, worker, red, permisos y canales Android.
- [ ] Verificar programación al habilitar, persistencia tras reinicio, reprogramación al actualizar intervalo y cancelación al deshabilitar.
- [ ] Diferenciar restricciones normales de WorkManager, Doze, ahorro de batería y cierre forzado del usuario/fabricante.
- [ ] Registrar estados diagnósticos sin almacenar claves, saldos ni datos sensibles.
- [ ] Probar en Android 13+ y en el Motorola Edge 50 Pro del usuario.
- **Salida:** pruebas de campo reproducibles con la app en segundo plano y pantalla apagada; documentar límites de Android. No prometer entrega exacta por minuto: WorkManager es diferido.

### F2 — Edición gratuita y CriptoControlMx Pro
- [ ] Inventariar funciones actuales y costos operativos antes de definir límites.
- [ ] Diseñar matriz Free/Pro con beneficios comprensibles, sin bloquear acceso a datos ya creados.
- [ ] Implementar una capa de capacidades/entitlements independiente de la interfaz.
- [ ] Evaluar Google Play Billing para compras/suscripciones y validar compras, restauración, cancelación, expiración y modo sin conexión.
- [ ] Mantener verificación de compra segura; nunca confiar únicamente en un booleano local para conceder Pro.
- [ ] No fijar precios hasta modelar costos y propuesta de valor.
- **Salida:** matriz aprobada, pruebas de ciclo de vida de compra y recuperación de derechos.

### F3 — Identidad y descripción
- [ ] Redactar propuesta de valor basada en funciones comprobadas.
- [ ] Preparar descripción corta y larga en español mexicano.
- [ ] Separar claramente funciones disponibles, experimentales y planeadas.
- [ ] Preparar textos de privacidad, riesgos y limitaciones; no prometer rendimientos ni asesoría financiera.
- **Salida:** ficha de producto coherente con la app real.

### F4 — Asistente de IA
- [ ] Definir casos de uso: explicar P/L, costo promedio, concentración, break-even y escenarios.
- [ ] Diseñar una capa de contexto que entregue a la IA datos agregados y explícitamente autorizados.
- [ ] No exponer claves API dentro del APK.
- [ ] Evaluar backend/proxy, autenticación, cuotas, costos, consentimiento y retención de datos.
- [ ] Restringir la IA a análisis explicativo; no ejecutar operaciones ni inventar precios.
- [ ] Probar respuestas con datos incompletos, históricos y contradictorios.
- **Salida:** prototipo con costos controlados, privacidad definida y evaluaciones de exactitud.

### F5 — Calidad y escalabilidad
- [ ] Separar lógica financiera, servicios, persistencia y UI gradualmente.
- [ ] Mantener migraciones versionadas y respaldos compatibles.
- [ ] Añadir pruebas de integración y regresión por módulo.
- [ ] Revisar observabilidad, privacidad y gestión de errores.
- **Salida:** arquitectura documentada y capacidad de incorporar módulos sin alterar cálculos existentes.

## Orden de prioridad

1. Base reproducible y datos.
2. Diagnóstico y corrección de notificaciones.
3. Matriz Free/Pro y diseño de entitlements.
4. Descripción e identidad del producto.
5. Diseño técnico y prototipo de IA.
6. Refactor incremental y escalabilidad.

## Fuera de alcance por ahora

- Publicación en producción.
- Generación de AAB firmado o cambios en claves de firma.
- Fijar precios o activar cobros reales.
- Enviar datos financieros a un proveedor de IA.
- Fusionar PR #42 automáticamente.
