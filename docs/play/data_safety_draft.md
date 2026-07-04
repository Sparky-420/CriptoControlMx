# Data Safety de Google Play — borrador preliminar

**Versión revisada:** CriptoControlMx 1.0.0-beta.1+2

**Fecha del borrador:** 4 de julio de 2026

Este documento es una guía de captura para Play Console, no la declaración
final. Debe compararse con el AAB publicado, la configuración de Firebase y las
definiciones vigentes de “recopilado” y “compartido” de Google Play antes de
enviarse.

## Respuestas generales propuestas

- La aplicación puede recopilar o transmitir datos cuando el usuario inicia
  sesión, sube/restaura manualmente información cloud o autoriza telemetría.
- No vende datos.
- No utiliza datos para publicidad.
- La sincronización Firebase y el backup de Drive son manuales.
- Analytics y Crashlytics están desactivados salvo consentimiento del usuario.
- Los datos cloud se transmiten cifrados en tránsito mediante servicios de
  Google.
- Las solicitudes de eliminación pueden enviarse a
  **criptocontrolmx@gmail.com**.

## Tipos de datos

| Categoría de Play | Dato | Declaración preliminar | Condición y propósito |
| --- | --- | --- | --- |
| Información personal | Dirección de correo | Sí | Google Sign-In/Firebase Authentication; funcionalidad y administración de cuenta. |
| Información personal | Nombre | Posible | Sólo si Google Sign-In lo proporciona; identificación visible de la cuenta. |
| Información financiera | Historial de compras o transacciones | Sí | Movimientos cripto registrados por el usuario; funcionalidad y respaldo cloud manual. |
| Información financiera | Otra información financiera | Sí | Montos, cantidades, precios, posiciones, comisiones e instantáneas; funcionalidad y respaldo cloud manual. |
| Fotos y videos | Fotos | Tratamiento local; revisar definición de Play | Sólo la captura que el usuario selecciona para OCR. Se procesa localmente y no se sube automáticamente. Si nunca sale del dispositivo, normalmente no se declara como “recopilada” bajo Data Safety. |
| Archivos y documentos | Archivos y documentos | Condicional | Importaciones, exportaciones y backups elegidos por el usuario. La copia se transmite sólo cuando el usuario solicita Google Drive o comparte un archivo. |
| Actividad en la app | Interacciones con la app | Condicional | Eventos técnicos permitidos y sin datos financieros, sólo si el usuario activa Analytics; propósito analítico. |
| Contenido generado por usuarios | Otro contenido | Posible | Movimientos y notas si se incluyen en el estado cloud o backup solicitado por el usuario. |
| Información y rendimiento de la app | Registros de fallos | Condicional | Sólo si el usuario activa Crashlytics; diagnóstico y estabilidad. |
| Información y rendimiento de la app | Diagnósticos | Condicional | Códigos técnicos permitidos, sólo con Crashlytics; diagnóstico. |
| Dispositivo u otros identificadores | Dispositivo u otros IDs | Sí o condicional | Identificadores técnicos usados por Firebase/Google y el identificador local de dispositivo para estado cloud; funcionalidad, seguridad y diagnóstico. |

## Propósitos que pueden aplicar

- Funcionalidad de la aplicación.
- Administración de cuentas.
- Analítica, únicamente con consentimiento.
- Prevención de fraude, seguridad y cumplimiento, sólo cuando corresponda a
  autenticación y servicios de Google.
- Comunicaciones del desarrollador únicamente si el usuario contacta soporte;
  no existe marketing automático declarado.

## Recopilación frente a compartición

- No se venden datos ni se comparten con redes publicitarias.
- Google Sign-In, Firebase, Firestore, Drive, Analytics y Crashlytics actúan
  como proveedores necesarios para las funciones elegidas.
- Antes de contestar “datos compartidos” en Play Console, comprobar si cada
  transferencia a Google entra en la excepción de proveedor de servicio de la
  definición vigente de Data Safety.
- No declarar que la aplicación “no recopila datos”: cuenta, estado financiero
  cloud y telemetría opcional pueden transmitirse.

## Seguridad y eliminación

- **Cifrado en tránsito:** sí para comunicaciones con servicios cloud de
  Google.
- **Cuenta opcional:** sí; las funciones locales principales pueden usarse sin
  iniciar sesión.
- **Solicitud de eliminación:** criptocontrolmx@gmail.com.
- **Eliminación local:** mediante controles locales, borrado de datos de la app
  o desinstalación.
- **Firebase/Drive:** revisar y documentar el procedimiento operativo de
  eliminación antes de publicar el formulario.

## Verificaciones obligatorias antes de enviar

- Revisar la configuración efectiva de Analytics y Crashlytics del AAB.
- Confirmar que OCR continúa siendo local y que las imágenes no se incluyen en
  Analytics, Crashlytics, Firebase ni Drive.
- Revisar el contenido exacto del backup y del documento Firestore.
- Confirmar las prácticas de todos los SDK incluidos en el AAB.
- Confirmar las definiciones y excepciones vigentes de Google Play.
- No marcar categorías o propósitos que la implementación real no utilice.
