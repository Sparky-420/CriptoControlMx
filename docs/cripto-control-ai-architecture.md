# CriptoControl AI — arquitectura y plan de implementación

## Objetivo

Agregar un copiloto de inteligencia financiera centrado exclusivamente en la cartera del usuario. Debe explicar posiciones, rendimiento, costo promedio, comisiones, concentración y escenarios hipotéticos utilizando datos reales de la aplicación.

La IA no es una fuente de verdad contable. Los cálculos y las simulaciones pertenecen al motor determinista de CriptoControlMx; el modelo solo interpreta resultados estructurados y los explica.

## Límites de seguridad y producción

- Trabajo aislado en `feat/cripto-control-ai-portfolio`.
- No modificar `master`, `stable`, `fenix`, `release-candidate-fenix-20261104`, Beta 14 publicada ni artefactos firmados.
- No fusionar ni publicar sin autorización expresa.
- El punto de partida inspeccionado es `work/roadmap-producto-notificaciones-20261108`. Su `pubspec.yaml` declara `1.0.0-beta.13+14`; no debe presentarse como el código ni como evidencia de la Beta 14 publicada.
- En esta rama existen Flutter, Firebase Auth, Firestore y SharedPreferences. No se encontró una carpeta `functions/` ni un backend desplegable en Firebase en el punto inspeccionado.
- La contabilidad canónica tiene un `AccountingRepository`; el asistente no debe escribir en él ni mutar movimientos, billeteras o saldos.
- Los precios tienen caché y modo manual/automático. Toda respuesta que use precios debe incluir su fecha de actualización y advertir si están desactualizados.

## Arquitectura objetivo

1. **Flutter — presentación**
   - Pantalla conversacional `CriptoControl AI`, estados de carga/error y tarjetas de explicación.
   - Contexto de cartera generado por un adaptador de solo lectura.
   - Consentimiento explícito antes de enviar datos financieros a un proveedor externo.
   - Indicador visible de plan, uso restante y antigüedad de precios.

2. **Dominio local — contexto y cálculos**
   - `PortfolioSnapshotProvider`: construye un DTO mínimo y versionado a partir de los modelos/repositorios reales.
   - `PortfolioAnalytics`: cálculos deterministas reutilizando reglas financieras existentes; no duplicar fórmulas en prompts.
   - `PortfolioScenarioEngine`: simulaciones puras (por ejemplo, compra hipotética o venta parcial), sin persistir cambios.
   - Pruebas unitarias con datos sintéticos, casos de cero, comisiones y posiciones sin precio válido.

3. **Firebase — AI Gateway**
   - Incorporar Cloud Functions (Callable HTTPS) como único intermediario con el proveedor.
   - Verificar Firebase Auth, App Check, consentimiento, plan y cuota en servidor.
   - Guardar la clave del proveedor en Secret Manager; nunca incluirla en Dart, assets, Remote Config ni APK.
   - Aplicar límites de entrada/salida, timeout, rate limit, presupuesto por usuario y registros sin contenido financiero sensible.
   - Devolver errores tipados y trazabilidad por request, sin exponer prompts internos.

4. **Proveedor de IA**
   - Usar la API de OpenAI desde el servidor, con modelo configurable y salida estructurada.
   - La entrada contiene pregunta, idioma y snapshot mínimo autorizado; no enviar identificadores personales, tokens, credenciales ni historial completo por defecto.
   - La IA puede solicitar únicamente herramientas de lectura/simulación declaradas. Las herramientas calculan en código confiable y devuelven resultados tipados.
   - No permitir acciones de compra/venta, cambios de saldos, edición de movimientos ni escritura en repositorios contables.

## Contrato de datos propuesto

`PortfolioContextV1`:
- `currency` (MXN inicialmente).
- `generatedAt` y `pricesUpdatedAt`.
- `positions[]`: símbolo, cantidad, capital invertido, valor actual, costo promedio y P/L calculado por el dominio.
- `totals`: capital, valor actual, P/L y porcentaje de rendimiento.
- `fees`: tasas aplicables y procedencia.
- `dataWarnings[]`: precios faltantes/antiguos, posiciones incompletas o datos no disponibles.

No enviar el libro mayor completo salvo que una función futura, consentida y justificada, lo requiera. El contexto se genera bajo demanda y no se persiste como nueva fuente contable.

## API interna propuesta

Callable `askPortfolioAssistant`:
- Entrada: `message`, `contextVersion`, `portfolioContext`, `conversationId` opcional.
- Servidor: autentica, valida tamaño, verifica consentimiento/plan/cuota, valida esquema y límites numéricos, invoca el modelo.
- Salida: `answer`, `usedContextAt`, `warnings[]`, `usage`, `requestId`.
- La función no acepta instrucciones para ejecutar operaciones ni escrituras contables.

Callable `getAiUsage`:
- Devuelve plan, límite y consumo del periodo.
- La decisión de acceso y cuota siempre se toma en servidor, nunca confiando en el estado local de Flutter.

## Monetización freemium

La política debe configurarse en servidor, no quedar codificada en el APK:
- **Free:** acceso introductorio con cuota limitada y respuestas enfocadas en conceptos básicos de la cartera.
- **Pro:** cuota superior, análisis más detallado y escenarios/simulaciones conversacionales.
- La cuota exacta, periodo y precio se definirán junto al sistema de Billing existente. No duplicar ni reemplazar la implementación de compras.
- Si Billing todavía no tiene validación de recibos en servidor, el backend no debe otorgar Pro por una bandera local.

## Privacidad y seguridad

- Consentimiento informado y revocable para enviar snapshot de cartera al proveedor.
- Minimización de datos y redacción de logs.
- App Check + Firebase Auth; cuotas y plan validados en servidor.
- Reglas Firestore para que cada usuario solo acceda a su propio uso/conversaciones.
- No entrenar ni ajustar modelos con datos del usuario desde esta integración.
- Respuestas educativas, no promesas de rendimiento ni instrucciones de inversión garantizadas.
- Indicar claramente que la IA puede equivocarse y mostrar los datos/fecha usados.

## Fases de implementación

### Fase 0 — protección y descubrimiento
- Confirmar baseline y ramas; preservar producción.
- Mapear los modelos reales de movimiento, posiciones, comisiones, precios y servicios Billing.
- Documentar qué fórmulas existentes se reutilizan.

### Fase 1 — dominio de cartera (sin IA)
- Implementar DTO versionado y adaptador de solo lectura.
- Implementar cálculos/simulaciones puras o reutilizar los existentes.
- Añadir pruebas unitarias de reconciliación contra la pantalla/resumen actual.

### Fase 2 — backend seguro
- Crear Cloud Functions, validación de Auth/App Check, secretos, cuota y contrato.
- Añadir pruebas de autorización, límites, cuota y errores.
- No desplegar automáticamente.

### Fase 3 — conversación Flutter
- Pantalla y estados, consentimiento, contexto mínimo, respuestas y avisos.
- Pruebas de widgets y manejo de red.
- Sin tocar el flujo de persistencia contable.

### Fase 4 — freemium y Billing
- Conectar el estado Pro verificado en servidor con la fuente de Billing ya existente.
- Definir cuotas y telemetría de costo.
- Probar Free, Pro, restauración y expiración/revocación.

### Fase 5 — validación y entrega
- `flutter analyze`, `flutter test`, pruebas backend y build debug.
- Revisar diff, permisos, secretos y datos transmitidos.
- Entregar PR aislado; no fusionar ni publicar sin autorización.

## Criterios de aceptación

- La app funciona igual si el proveedor de IA está caído o el usuario no consiente.
- Ningún secreto del proveedor aparece en el APK o repositorio cliente.
- Respuestas con cifras coinciden con cálculos deterministas y muestran fecha/fuente de precios.
- No se modifica ninguna operación, saldo, billetera o registro contable.
- El servidor impone plan y cuota; cambiar valores locales no desbloquea Pro.
- Los tests demuestran aislamiento de producción y compatibilidad con datos históricos.
