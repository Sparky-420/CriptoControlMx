# CriptoControl AI — integración en CriptoControlMx

Esta integración agrega un chat de análisis conversacional a la aplicación. El cliente construye el contexto desde el documento contable canónico y el `AccountingLedgerEngine`; el backend autenticado entrega el contexto completo de cartera e historial al modelo. La IA no escribe movimientos ni modifica la contabilidad.

## Alcance

- Chat accesible desde el icono de destellos en la barra superior.
- Contexto con todas las operaciones canónicas, posiciones por cartera/activo, cantidades conocidas y desconocidas, costos, P&L realizado/no realizado, comisiones, transferencias, conciliación, incidencias, precios y modo manual/automático.
- Los identificadores internos de carteras y destinatarios externos no se envían al proveedor. Se conservan nombres de cartera y proveedor para que las preguntas sobre dónde está cada activo puedan responderse.
- Firebase Auth protege la callable function.
- Clave del proveedor únicamente en Secret Manager.
- Cuota diaria por usuario y plan derivado de claims firmados por Firebase. No se confía en un plan enviado por el cliente.
- Las consultas y el contexto no se guardan como historial. Los contadores técnicos usan documentos privados con expiración de 30 días.

## Configuración requerida antes de desplegar

1. Instalar Firebase CLI y autenticar el proyecto correcto `control-cripto-mx`.
2. Desde la raíz del repositorio ejecutar `firebase functions:secrets:set OPENAI_API_KEY --project control-cripto-mx`.
3. Configurar el parámetro `CRYPTO_AI_MODEL` con un modelo habilitado para la cuenta del proyecto (valor inicial: `gpt-6-astra`).
4. Ejecutar `cd functions && npm install && npm run build`.
5. Ejecutar `firebase deploy --only functions:analyzePortfolio --project control-cripto-mx`.

No se incluye ninguna API key en el repositorio. No se ha desplegado ninguna función ni modificado Firebase en producción.

## Límites actuales que deben resolverse antes de producción

- La función está fijada en `us-central1`; confirmar que coincide con la región de Firebase del proyecto.
- El claim `plan` o `subscription` debe ser asignado por el sistema de billing de confianza. Si no existe, se aplica Free.
- Los límites iniciales Free 8 / Pro 100 consultas por día son provisionales y deben alinearse con la configuración comercial real.
- La política TTL de Firestore debe configurarse para el campo `expiresAt` en las colecciones `ai_private_quotas` y `ai_private_requests`.
- El contexto completo se transmite en cada pregunta. Para historiales que superen 1.8 MB / 12,000 movimientos, el backend rechaza la petición en vez de truncar silenciosamente el historial.
- Las proyecciones se recalculan localmente con el motor contable real al abrir el chat. No se crea una copia contable paralela.

## Seguridad y privacidad

Las reglas actuales de Firestore niegan por defecto colecciones no declaradas; el cliente no recibe permisos directos de lectura/escritura sobre los contadores. Admin SDK opera sólo desde la función. El proveedor recibe pregunta e información financiera necesaria para responder, sin UID, correos, IDs internos de billeteras ni nombres de destinatarios externos. El uso del proveedor implica transmisión del contexto de cartera para procesar cada pregunta.
