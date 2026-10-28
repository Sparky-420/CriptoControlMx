# Recuperación controlada del historial PR #30–#36

Fecha de auditoría: 2026-10-24.

## Objetivo
Ordenar la integración de Fase 4.7, los cambios visuales y la arquitectura contable sin sobrescribir `master`, la rama `fase-2.1-tech-debt` ni reconstrucciones históricas.

## Referencias verificadas
- Baseline visual: `d2e821938b30f8b316457d5ecd2a165d2cabb16f`.
- Rama `fase-3-visual-premium`: `9d6cedfeda10d0e8afb18982533c76ab03910d95`.
- Rama `fase-2.1-tech-debt`: `c80295d5882d60624b4cc101db5d40a826936ecd`.
- Merge PR #36: `59814de0ba6dfb214e5050d53af41253ec12845a`.
- Rama de alertas Fase 4.7: `codex/implementar-fase-4.7-en-criptocontrolmx` en `fa855fed5ec4753778521b9712797d2c6dcf5c4a`.
- Rama de baseline fix: `codex/fase-4-7-baseline-fix` en `d2e821938b30f8b316457d5ecd2a165d2cabb16f`.
- Rama consolidada: `codex/fase-4-consolidated` en `ecb7347148beaeb4bc68ef79b096a250cef02dac`.

## Hallazgos

1. PR #31 apuntaba a `master` y su diff era de gran tamaño. La descripción de PR #32 indica que esa base era incorrecta.
2. PR #32 integra el trabajo visual sobre `fase-2.1-tech-debt`.
3. PR #33 y PR #35 implementan cambios de Fase 4.7 en `lib/cripto_control_app.dart`, respectivamente con +94/-8 y +82/-1. Son variantes con solapamiento funcional; no se deben aplicar ambas sin comparar semántica.
4. Issue #34 fija el baseline `d2e8219` y pide no arrastrar fases 4.1–4.6 ni alterar lógica financiera, movimientos, Drive, importación/exportación, temas o servicios.
5. PR #36 cambia Gradle Wrapper 8.12→8.14, Android Gradle Plugin 8.9.1→8.11.1 y Kotlin 2.1.0→2.2.20. El alcance real excede el título del PR.
6. `fase-2.1-tech-debt` contiene una arquitectura contable extensa añadida después de `fase-3-visual-premium`: adaptadores legacy, dominio de movimientos/billeteras, repositorio, migración, proyecciones y pruebas. Estos archivos deben preservarse.
7. `fase-2.8E-codex` no es un sustituto seguro: su `pubspec.yaml` declara `1.0.0+1` y su `lib/main.dart` no inicializa Firebase; `fase-2.1-tech-debt` declara `1.0.0-beta.7+8` e incluye inicialización/consentimiento de Firebase. No reemplazar el proyecto completo con esa rama.
8. El reporte local previo identificó un commit local `a1b498a` por delante de `origin/fase-2.1-tech-debt`, con cambios en `lib/cripto_control_app.dart` y un archivo de auditoría sin seguimiento. Ese estado local debe conservarse y revisarse en la máquina del desarrollador; no es accesible ni debe sobrescribirse desde esta rama remota.

## Orden de trabajo

1. Mantener intactos `master`, `fase-2.1-tech-debt`, `fase-3-visual-premium` y ramas históricas.
2. Usar esta rama aislada como expediente de recuperación.
3. Comparar los parches de PR #33 y #35 y elegir una sola implementación canónica de Fase 4.7.
4. Aplicar únicamente ese parche sobre el baseline visual apropiado, revisando que las restricciones del Issue #34 se cumplan.
5. Reconciliar el parche con la arquitectura contable presente en `fase-2.1-tech-debt`; no reemplazar `lib/cripto_control_app.dart` completo por una versión histórica.
6. Revisar los cambios de toolchain del PR #36 por compatibilidad y ejecutar pruebas/build en un entorno Flutter real.
7. Resolver la versión de publicación contra el AAB histórico beta.13+14 y el estado local antes de cambiar el número de versión.
8. Abrir un PR de recuperación con diff revisable; no fusionar hasta que las pruebas y la revisión del diff estén completas.

## Estado
- Rama de recuperación creada desde `fase-2.1-tech-debt`.
- Este documento es solo el registro de auditoría y plan; no restaura código ni modifica ramas de publicación.
- Pendiente: ejecutar pruebas y validar el AAB desde el entorno Flutter local.
