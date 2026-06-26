ROADMAP — Integración nueva CriptoControlMx
Actualización: 2026-06-26  
Motivo: pruebas reales posteriores a Google/Firebase/Drive y nueva captura Bitso XRP.  
Archivo sugerido en repo: `docs/ROADMAP.md`  
Rama sugerida: `fase-2.1-tech-debt`
---
Integración nueva dentro del roadmap
Esta integración no reemplaza el roadmap anterior. Se inserta como ampliación técnica entre OCR, nube y release.
---
FASE 2.2B — OCR Bitso compras/ventas
Estado: NUEVA / PENDIENTE ⏳  
Prioridad: ALTA  
Motivo: el OCR actual está orientado principalmente a Mercado Pago y falla con capturas Bitso.
Problema detectado
En una compra Bitso de XRP, la captura real decía:
```text
Buy
4.120444 XRP
Monto gastado
75.03 MXN
Comisión
0.032139 XRP
Tipo de cambio
1 XRP = 18.20 MXN
Date
25 jun 2026 3:36:34 p. m.
```
Pero la app detectó incorrectamente:
```text
Tipo: No detectado
Moneda: XRP
Cantidad: 4120444.00000000
Monto MXN: $75.03
Precio unitario MXN: $0.00
Comisión MXN: $18.20
Plataforma: no detectada
```
Errores específicos
El parser perdió el punto decimal:
Correcto: `4.120444 XRP`
Incorrecto: `4120444 XRP`
Confundió el tipo de cambio con comisión:
Correcto: `1 XRP = 18.20 MXN` es precio unitario.
Incorrecto: `$18.20` como comisión MXN.
No detectó el tipo:
`Buy` debe mapearse como compra.
No detectó la plataforma:
Captura con labels de Bitso debe marcarse como `Bitso`.
No entiende comisión en cripto:
`0.032139 XRP` no debe tratarse como MXN.
Objetivo
Agregar soporte OCR específico para Bitso sin romper Mercado Pago.
Reglas de interpretación Bitso
Tipo
```text
Buy        -> compra
Sell       -> venta
Deposit    -> entrada / transferIn
Receive    -> entrada / transferIn
Withdrawal -> salida / transferOut
Send       -> salida / transferOut
```
Monto
```text
Monto gastado 75.03 MXN -> amountMxn = 75.03
Monto recibido X MXN -> amountMxn = X
```
Cantidad
Preservar decimales aunque OCR separe o adelgace el punto.
```text
4.120444 XRP -> quantity = 4.120444
```
No convertir a:
```text
4120444
```
Tipo de cambio
```text
1 XRP = 18.20 MXN -> unitPriceMxn = 18.20
```
No debe entrar como comisión.
Comisión cripto
```text
Comisión 0.032139 XRP -> feeCryptoAmount = 0.032139
feeCryptoCoin = XRP
```
No debe convertirse automáticamente en comisión MXN si el movimiento no soporta comisión cripto.
Cálculo recomendado para cartera actual
Mientras el motor no soporte comisión en cripto de forma nativa, usar cantidad neta:
```text
cantidad_neta = cantidad_bruta - comisión_cripto
```
Ejemplo:
```text
4.120444 XRP - 0.032139 XRP = 4.088305 XRP
```
Movimiento recomendado:
```text
Tipo: Compra
Plataforma: Bitso
Moneda: XRP
Cantidad: 4.088305 XRP
Monto MXN: $75.03
Comisión MXN: $0.00
Fecha: 25/06/2026 15:36:34
Nota: Comisión Bitso 0.032139 XRP descontada en cripto.
```
Precio efectivo:
```text
75.03 / 4.088305 = 18.3523 MXN/XRP
```
UI requerida
En la vista OCR debe mostrar:
```text
Plataforma: Bitso
Tipo: Compra
Cantidad bruta: 4.120444 XRP
Comisión cripto: 0.032139 XRP
Cantidad neta sugerida: 4.088305 XRP
Monto MXN: $75.03
Tipo de cambio: $18.20 MXN/XRP
Precio efectivo: $18.3523 MXN/XRP
```
Advertencias requeridas
```text
Comisión detectada en cripto; revisa si deseas guardar cantidad bruta o neta.
Tipo de cambio detectado; no se registró como comisión MXN.
Nada se guardará hasta confirmar en formulario.
```
Archivos probables a tocar
```text
lib/cripto_control_app.dart
```
Si después se separa parser:
```text
lib/services/ocr_parser_service.dart
lib/models/ocr_movement_draft.dart
```
No tocar
```text
Motor financiero principal
Fórmulas P&L
Cost base
Backup local
Firebase sync
Google Drive
PriceMode
Reset financiero
```
Criterios de cierre
```text
IMPLEMENTADA:
- Parser reconoce Bitso Buy/Sell.
- Preserva decimales.
- Distingue comisión cripto de tipo de cambio.
- Prellena formulario.

VALIDADA:
- Probada con captura XRP real.
- Probada con al menos otra compra Bitso.
- No rompe OCR Mercado Pago.

CERRADA:
- Build OK.
- Prueba real OK.
- Commit/push.
```
---
FASE 2.2C — OCR multi-plataforma seguro
Estado: FUTURA / DESPUÉS DE 2.2B ⏳  
Prioridad: MEDIA
Objetivo
Evitar que cada plataforma contamine el parser general. Separar detección por plataforma.
Plataformas
```text
Mercado Pago
Bitso
Binance
Manual / desconocida
```
Arquitectura sugerida
```text
OcrRawText
  -> PlatformDetector
  -> MercadoPagoParser
  -> BitsoParser
  -> BinanceParser futuro
  -> OcrMovementDraft
  -> Formulario editable
```
Beneficio
Menos falsos positivos.
Mejor mantenimiento.
Cada plataforma puede tener reglas propias.
No rompe Mercado Pago al arreglar Bitso.
---
FASE 2.5I — Validación Google/Firebase multi-dispositivo
Estado: NUEVA / PENDIENTE PARCIAL ⏳  
Prioridad: ALTA  
Motivo: Google funciona en el G60, pero se reporta fallo en el celular de otro usuario.
Problema
Google Sign-In ya funciona en el dispositivo principal, pero no en el celular de tu primo.
Hipótesis principales
```text
1. APK vieja instalada.
2. APK generada con firma distinta.
3. APK de GitHub Actions firmada con otra SHA debug.
4. OAuth consent screen en Testing y correo de tu primo no agregado.
5. Google Play Services desactualizado.
6. Google provider correcto, pero cuenta no autorizada como tester.
```
Objetivo
Validar que login y nube funcionen fuera del celular principal.
Checklist
En celular secundario
```text
- Desinstalar app vieja.
- Instalar APK nueva posterior al fix OAuth.
- Confirmar conexión a internet.
- Confirmar cuenta Google activa.
- Confirmar Google Play Services actualizado.
- Probar login.
```
En Firebase / Google Cloud
```text
- Confirmar proyecto: control-cripto-mx.
- Confirmar package: mx.criptocontrolmx.app.
- Confirmar SHA debug local.
- Confirmar OAuth web client client_type: 3.
- Si OAuth está en Testing: agregar correo del primo como test user.
```
Si se usa APK de GitHub Actions
```text
- No confiar en SHA debug de la laptop.
- La firma puede ser distinta.
- Solución recomendada: pasar a release firmado.
```
Criterios de cierre
```text
VALIDADA:
- Login funciona en G60.
- Login funciona en celular secundario.
- Subir estado a Firebase funciona en ambos.
- Descargar estado desde Firebase funciona en ambos.
- Google Drive no rompe por cuenta secundaria.

CERRADA:
- Evidencia de prueba.
- Commit/push si hubo cambio.
```
---
FASE 2.7 — Release Android firmado / AAB
Estado: SIGUIENTE ESTRATÉGICA ⏳  
Prioridad: MUY ALTA  
Motivo: reduce problemas de firma entre dispositivos y prepara Play Store.
Cambio de prioridad
Antes 2.7 era siguiente natural. Ahora queda reforzada por el fallo en celular secundario.
Razón
Mientras se instalen APK debug de distintos orígenes, Google Sign-In puede fallar por SHA diferente.
Release firmado permite:
```text
- Misma firma para todos los testers.
- SHA release estable en Firebase.
- AAB para Play Console.
- Beta cerrada real.
```
Subfases
2.7A — Auditoría release firmado
```text
- build.gradle.kts
- applicationId
- namespace
- versionCode
- versionName
- signingConfigs
- .gitignore
- key.properties
- keystore
```
2.7B — Crear keystore
```text
- Generar upload key.
- Crear key.properties local.
- No subir .jks.
- No subir contraseñas.
```
2.7C — Configurar signing release
```text
- signingConfig release.
- Validación temprana si falta key.properties.
- Debug intacto.
```
2.7D — Agregar SHA release en Firebase
```text
- Obtener SHA-1 release.
- Obtener SHA-256 release.
- Agregar ambas a Firebase.
- Descargar google-services.json actualizado si aplica.
```
2.7E — Build release
```text
flutter build apk --release
flutter build appbundle --release
```
2.7F — Prueba release real
```text
- Instalar APK release en G60.
- Instalar APK release en celular secundario.
- Probar Google Sign-In.
- Probar Firebase upload/download.
- Probar Google Drive.
```
Criterios de cierre
```text
VALIDADA:
- APK release funciona en dos dispositivos.
- Login funciona con firma release.
- Firebase y Drive funcionan.

CERRADA:
- AAB generado.
- SHA release agregada a Firebase.
- Commit/push sin secretos.
```
---
Ajuste al resumen ejecutivo
```text
FASE 0      CERRADA
FASE 0.5    CERRADA
FASE 1      CERRADA
FASE 2.0    CERRADA
FASE 2.1    CERRADA
FASE 2.2    VALIDADA PARCIAL REAL
FASE 2.2B   NUEVA / OCR BITSO PENDIENTE
FASE 2.2C   FUTURA / OCR MULTI-PLATAFORMA
FASE 2.3    CERRADA
FASE 2.4    VALIDADA REAL
FASE 2.5    VALIDADA REAL EN MODO MANUAL
FASE 2.5I   NUEVA / VALIDACIÓN MULTI-DISPOSITIVO
FASE 2.6    IMPLEMENTADA / FALTA VALIDACIÓN COMPLETA DE MONITOREO
FASE 2.7    SIGUIENTE ESTRATÉGICA / RELEASE FIRMADO
FASE 2.8    PENDIENTE / PLAY BETA
FASE 2.9    PENDIENTE / PRODUCCIÓN
FASE 3.0+   FUTURO
```
---
Orden recomendado desde aquí
```text
1. Cerrar commit del fix OAuth si aún no quedó.
2. Crear docs/ROADMAP.md con roadmap actualizado.
3. FASE 2.2B — OCR Bitso compras/ventas.
4. FASE 2.5I — Validación Google multi-dispositivo.
5. FASE 2.7 — Release firmado / AAB.
6. FASE 2.8 — Play Console beta cerrada.
```