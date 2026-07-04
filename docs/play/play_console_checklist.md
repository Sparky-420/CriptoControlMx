# Checklist de Play Console

Ejecutar cuando Google termine la verificación de identidad.

## Aplicación y ficha

- [ ] Crear la aplicación CriptoControlMx en Play Console.
- [ ] Confirmar package name: `mx.criptocontrolmx.app`.
- [ ] Completar ficha, categoría, correo de soporte y declaraciones requeridas.
- [ ] Publicar la política de privacidad en una URL pública, estable y sin
      autenticación.
- [ ] Completar Data Safety después de contrastarlo con el AAB real.
- [ ] Cargar screenshots sin datos sensibles.

## Firma y artefacto

- [ ] Activar Play App Signing.
- [ ] Conservar de forma segura la upload key actual.
- [ ] Subir `app-release.aab` versión `1.0.0-beta.1+2`.
- [ ] Confirmar que Play muestra `versionCode 2` y `versionName 1.0.0-beta.1`.
- [ ] Agregar las notas de la release interna.
- [ ] No reutilizar `versionCode 2` en una carga posterior.

## Internal Testing

- [ ] Crear el track Internal Testing.
- [ ] Crear o seleccionar la lista de testers.
- [ ] Agregar los correos autorizados.
- [ ] Compartir el enlace de opt-in.
- [ ] Esperar a que el release aparezca disponible para los testers.

## SHA y servicios Google

- [ ] Obtener SHA-1 y SHA-256 del certificado de **Play App Signing**, no sólo
      de la upload key.
- [ ] Registrar ambas huellas de Play App Signing en la app Android de Firebase.
- [ ] Verificar o crear el cliente OAuth Android con package
      `mx.criptocontrolmx.app` y SHA-1 de Play.
- [ ] Confirmar que las APIs y la pantalla de consentimiento necesarias para
      Google Sign-In y Google Drive están configuradas.
- [ ] Si OAuth continúa en Testing, agregar todos los testers como test users.
- [ ] Descargar `google-services.json` únicamente si Firebase exige una
      configuración actualizada; revisar el cambio antes de reemplazarlo.

## Smoke test instalado desde Play

- [ ] Instalar desde el enlace de Internal Testing.
- [ ] Confirmar versión y ausencia de pantalla roja.
- [ ] Probar Google Sign-In con la firma de Play.
- [ ] Probar subida y descarga manual de Firebase.
- [ ] Probar conexión, creación y restauración de Google Drive.
- [ ] Confirmar movimientos esperados.
- [ ] Confirmar instantáneas esperadas.
- [ ] Navegar por Resumen, Monedas, Historial, Alertas y Más.
- [ ] Probar OCR sin autosave y revisar datos antes de guardar.
- [ ] Probar una alerta local controlada y restaurar su estado seguro.
- [ ] Confirmar que no hay cierres, duplicados excesivos ni pantalla roja.

## Cierre

- [ ] Registrar dispositivo, Android, versión probada y resultado.
- [ ] Guardar evidencia sin información sensible.
- [ ] Revisar feedback de testers antes de promover a otro track.
- [ ] Incrementar siempre el `versionCode` para el siguiente AAB.
