# Baseline previa a carteras contables

Fecha: 2026-08-10
Rama: `feature/carteras-contables`
HEAD: `eb87a4ce6b371547690f8825feb8384ba5b610b1`

## Comandos y resultados

| Comando | Resultado |
| --- | --- |
| `flutter test` | Exit 0; 43/43 pruebas aprobadas |
| `flutter analyze` | Exit 1; 30 diagnósticos preexistentes: 11 warnings y 19 infos |
| `git diff --check` | Exit 0; limpio |

`flutter analyze --no-pub` se repitió para capturar la huella completa. La
comparación posterior debe usar archivo, severidad, regla y mensaje. La línea
puede cambiar al extraer código y no identifica por sí sola un diagnóstico
nuevo.

## Diagnósticos autorizados como deuda preexistente

Todos pertenecen a `lib/cripto_control_app.dart`.

| # | Severidad | Línea:columna | Regla | Mensaje |
| ---: | --- | --- | --- | --- |
| 1 | info | 16:8 | `depend_on_referenced_packages` | The imported package `_discoveryapis_commons` isn't a dependency of the importing package. Try adding a dependency for `_discoveryapis_commons` in the `pubspec.yaml` file. |
| 2 | warning | 363:10 | `unused_element_parameter` | A value for optional parameter `errors` isn't ever given. Try removing the unused parameter. |
| 3 | warning | 528:11 | `unused_field` | The value of the field `_googleDriveBackupAccountEmail` isn't used. Try removing the field, or using it. |
| 4 | warning | 3193:8 | `unused_element` | The declaration `_openSimulationMode` isn't referenced. Try removing the declaration. |
| 5 | info | 3347:28 | `use_build_context_synchronously` | Don't use `BuildContext`s across async gaps, guarded by an unrelated `mounted` check. Guard a `State.context` use with a `mounted` check on the State, and other BuildContext use with a `mounted` check on the BuildContext. |
| 6 | info | 3913:31 | `use_build_context_synchronously` | Don't use `BuildContext`s across async gaps. Try rewriting the code to not use the `BuildContext`, or guard the use with a `mounted` check. |
| 7 | info | 3924:31 | `use_build_context_synchronously` | Don't use `BuildContext`s across async gaps. Try rewriting the code to not use the `BuildContext`, or guard the use with a `mounted` check. |
| 8 | info | 3977:40 | `use_build_context_synchronously` | Don't use `BuildContext`s across async gaps. Try rewriting the code to not use the `BuildContext`, or guard the use with a `mounted` check. |
| 9 | info | 8246:31 | `library_private_types_in_public_api` | Invalid use of a private type in a public API. Try making the private type public, or making the API that uses the private type also be private. |
| 10 | info | 8486:7 | `curly_braces_in_flow_control_structures` | Statements in an `if` should be enclosed in a block. Try wrapping the statement in a block. |
| 11 | info | 8488:7 | `curly_braces_in_flow_control_structures` | Statements in an `if` should be enclosed in a block. Try wrapping the statement in a block. |
| 12 | warning | 8673:22 | `unnecessary_non_null_assertion` | The `!` will have no effect because the receiver can't be null. Try removing the `!` operator. |
| 13 | warning | 8678:47 | `unnecessary_non_null_assertion` | The `!` will have no effect because the receiver can't be null. Try removing the `!` operator. |
| 14 | warning | 8693:39 | `unnecessary_non_null_assertion` | The `!` will have no effect because the receiver can't be null. Try removing the `!` operator. |
| 15 | warning | 8699:33 | `unnecessary_non_null_assertion` | The `!` will have no effect because the receiver can't be null. Try removing the `!` operator. |
| 16 | warning | 8699:46 | `unnecessary_non_null_assertion` | The `!` will have no effect because the receiver can't be null. Try removing the `!` operator. |
| 17 | info | 8706:7 | `curly_braces_in_flow_control_structures` | Statements in an `if` should be enclosed in a block. Try wrapping the statement in a block. |
| 18 | warning | 8731:76 | `unnecessary_non_null_assertion` | The `!` will have no effect because the receiver can't be null. Try removing the `!` operator. |
| 19 | warning | 8732:76 | `unnecessary_non_null_assertion` | The `!` will have no effect because the receiver can't be null. Try removing the `!` operator. |
| 20 | warning | 9431:8 | `unused_element` | The declaration `_showDetectedOcrText` isn't referenced. Try removing the declaration. |
| 21 | info | 19838:27 | `deprecated_member_use` | `groupValue` is deprecated and shouldn't be used. Use a `RadioGroup` ancestor to manage group value instead. |
| 22 | info | 19840:27 | `deprecated_member_use` | `onChanged` is deprecated and shouldn't be used. Use `RadioGroup` to handle value change instead. |
| 23 | info | 21299:7 | `curly_braces_in_flow_control_structures` | Statements in an `if` should be enclosed in a block. Try wrapping the statement in a block. |
| 24 | info | 21301:7 | `curly_braces_in_flow_control_structures` | Statements in an `if` should be enclosed in a block. Try wrapping the statement in a block. |
| 25 | info | 21992:27 | `deprecated_member_use` | `groupValue` is deprecated and shouldn't be used. Use a `RadioGroup` ancestor to manage group value instead. |
| 26 | info | 21994:27 | `deprecated_member_use` | `onChanged` is deprecated and shouldn't be used. Use `RadioGroup` to handle value change instead. |
| 27 | info | 22077:27 | `deprecated_member_use` | `groupValue` is deprecated and shouldn't be used. Use a `RadioGroup` ancestor to manage group value instead. |
| 28 | info | 22079:27 | `deprecated_member_use` | `onChanged` is deprecated and shouldn't be used. Use `RadioGroup` to handle value change instead. |
| 29 | info | 22081:31 | `curly_braces_in_flow_control_structures` | Statements in an `if` should be enclosed in a block. Try wrapping the statement in a block. |
| 30 | info | 22808:5 | `curly_braces_in_flow_control_structures` | Statements in an `if` should be enclosed in a block. Try wrapping the statement in a block. |

## Regla de no regresión

- Ninguna etapa puede añadir una huella `(archivo, severidad, regla, mensaje)`
  que no figure arriba.
- El total final debe ser menor o igual a 30.
- Si un diagnóstico cambia de archivo por una extracción, debe documentarse
  como trasladado y no puede originarse en código nuevo evitable.
- Un diagnóstico preexistente sólo se corrige cuando su código está directamente
  dentro del alcance de carteras, la corrección es necesaria para implementar
  con seguridad y queda cubierta por pruebas.
- Cada etapa se detiene ante cualquier diagnóstico nuevo hasta corregirlo.

## Actualización controlada de toolchain (2026-08-11)

Esta sección amplía el registro anterior; no lo sustituye. La huella histórica
precedente permanece íntegra para conservar la evidencia de la transición.

### Toolchain y ejecución

- Flutter: `3.44.0`, canal `stable`, revisión de framework `559ffa3f75`.
- Dart: `3.12.0`.
- DevTools: `2.57.0`.
- Comando, ejecutado dos veces en el worktree aislado:
  `flutter analyze --no-pub`.
- Resultado de ambas ejecuciones: 30 diagnósticos, compuestos por 11 warnings y
  19 infos.
- Las 30 líneas diagnósticas fueron idénticas byte por byte entre ejecuciones.
  La única diferencia en la salida completa fue el tiempo informativo final
  (`2.8s` frente a `2.4s`), que no forma parte de la huella del diagnóstico.

### Salida textual actual

```text
Analyzing carteras-contables...

   info - The imported package '_discoveryapis_commons' isn't a dependency of the importing package. Try adding a dependency for '_discoveryapis_commons' in the 'pubspec.yaml' file - lib\cripto_control_app.dart:16:8 - depend_on_referenced_packages
warning - A value for optional parameter 'errors' isn't ever given. Try removing the unused parameter - lib\cripto_control_app.dart:363:10 - unused_element_parameter
warning - The value of the field '_googleDriveBackupAccountEmail' isn't used. Try removing the field, or using it - lib\cripto_control_app.dart:528:11 - unused_field
warning - The declaration '_openSimulationMode' isn't referenced. Try removing the declaration of '_openSimulationMode' - lib\cripto_control_app.dart:3193:8 - unused_element
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check. Guard a 'State.context' use with a 'mounted' check on the State, and other BuildContext use with a 'mounted' check on the BuildContext - lib\cripto_control_app.dart:3347:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check - lib\cripto_control_app.dart:3913:31 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check - lib\cripto_control_app.dart:3924:31 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check - lib\cripto_control_app.dart:3977:40 - use_build_context_synchronously
   info - Invalid use of a private type in a public API. Try making the private type public, or making the API that uses the private type also be private - lib\cripto_control_app.dart:8246:31 - library_private_types_in_public_api
   info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\cripto_control_app.dart:8486:7 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\cripto_control_app.dart:8488:7 - curly_braces_in_flow_control_structures
warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib\cripto_control_app.dart:8673:22 - unnecessary_non_null_assertion
warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib\cripto_control_app.dart:8678:47 - unnecessary_non_null_assertion
warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib\cripto_control_app.dart:8693:39 - unnecessary_non_null_assertion
warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib\cripto_control_app.dart:8699:33 - unnecessary_non_null_assertion
warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib\cripto_control_app.dart:8699:46 - unnecessary_non_null_assertion
   info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\cripto_control_app.dart:8706:7 - curly_braces_in_flow_control_structures
warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib\cripto_control_app.dart:8731:76 - unnecessary_non_null_assertion
warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib\cripto_control_app.dart:8732:76 - unnecessary_non_null_assertion
warning - The declaration '_showDetectedOcrText' isn't referenced. Try removing the declaration of '_showDetectedOcrText' - lib\cripto_control_app.dart:9431:8 - unused_element
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre. Try replacing the use of the deprecated member with the replacement - lib\cripto_control_app.dart:19838:27 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre. Try replacing the use of the deprecated member with the replacement - lib\cripto_control_app.dart:19840:27 - deprecated_member_use
   info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\cripto_control_app.dart:21299:7 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\cripto_control_app.dart:21301:7 - curly_braces_in_flow_control_structures
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre. Try replacing the use of the deprecated member with the replacement - lib\cripto_control_app.dart:21992:27 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre. Try replacing the use of the deprecated member with the replacement - lib\cripto_control_app.dart:21994:27 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre. Try replacing the use of the deprecated member with the replacement - lib\cripto_control_app.dart:22077:27 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre. Try replacing the use of the deprecated member with the replacement - lib\cripto_control_app.dart:22079:27 - deprecated_member_use
   info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\cripto_control_app.dart:22081:31 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\cripto_control_app.dart:22808:5 - curly_braces_in_flow_control_structures

30 issues found. (ran in 2.8s)
```

### Comparación de las 12 redacciones

Los 30 diagnósticos se agrupan en estas 12 redacciones. La multiplicidad, la
regla, la severidad, el archivo y las anclas de cada grupo permanecen iguales.

| ID | Multiplicidad | Redacción anterior | Redacción actual | Diferencia |
| --- | ---: | --- | --- | --- |
| M1 | 1 | The imported package `_discoveryapis_commons` isn't a dependency of the importing package. Try adding a dependency for `_discoveryapis_commons` in the `pubspec.yaml` file. | The imported package '_discoveryapis_commons' isn't a dependency of the importing package. Try adding a dependency for '_discoveryapis_commons' in the 'pubspec.yaml' file | Representación de código y punto final. |
| M2 | 1 | A value for optional parameter `errors` isn't ever given. Try removing the unused parameter. | A value for optional parameter 'errors' isn't ever given. Try removing the unused parameter | Representación de código y punto final. |
| M3 | 1 | The value of the field `_googleDriveBackupAccountEmail` isn't used. Try removing the field, or using it. | The value of the field '_googleDriveBackupAccountEmail' isn't used. Try removing the field, or using it | Representación de código y punto final. |
| M4 | 1 | The declaration `_openSimulationMode` isn't referenced. Try removing the declaration. | The declaration '_openSimulationMode' isn't referenced. Try removing the declaration of '_openSimulationMode' | El mensaje nuevo explicita el símbolo en la recomendación. |
| M5 | 1 | Don't use `BuildContext`s across async gaps, guarded by an unrelated `mounted` check. Guard a `State.context` use with a `mounted` check on the State, and other BuildContext use with a `mounted` check on the BuildContext. | Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check. Guard a 'State.context' use with a 'mounted' check on the State, and other BuildContext use with a 'mounted' check on the BuildContext | Representación de código y punto final. |
| M6 | 3 | Don't use `BuildContext`s across async gaps. Try rewriting the code to not use the `BuildContext`, or guard the use with a `mounted` check. | Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check | Representación de código y punto final. |
| M7 | 1 | Invalid use of a private type in a public API. Try making the private type public, or making the API that uses the private type also be private. | Invalid use of a private type in a public API. Try making the private type public, or making the API that uses the private type also be private | Punto final. |
| M8 | 7 | Statements in an `if` should be enclosed in a block. Try wrapping the statement in a block. | Statements in an if should be enclosed in a block. Try wrapping the statement in a block | Representación de código y punto final. |
| M9 | 7 | The `!` will have no effect because the receiver can't be null. Try removing the `!` operator. | The '!' will have no effect because the receiver can't be null. Try removing the '!' operator | Representación de código y punto final. |
| M10 | 1 | The declaration `_showDetectedOcrText` isn't referenced. Try removing the declaration. | The declaration '_showDetectedOcrText' isn't referenced. Try removing the declaration of '_showDetectedOcrText' | El mensaje nuevo explicita el símbolo en la recomendación. |
| M11 | 3 | `groupValue` is deprecated and shouldn't be used. Use a `RadioGroup` ancestor to manage group value instead. | 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre. Try replacing the use of the deprecated member with the replacement | Añade versión de deprecación y recomendación genérica. |
| M12 | 3 | `onChanged` is deprecated and shouldn't be used. Use `RadioGroup` to handle value change instead. | 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre. Try replacing the use of the deprecated member with the replacement | Añade versión de deprecación y recomendación genérica. |

### Huella con anclas verificables

Todos los diagnósticos siguen perteneciendo a
`lib/cripto_control_app.dart`. La posición se registra para comprobación, pero
el ancla fuente es la identidad estable frente a desplazamientos de línea. En
las dos incidencias de la línea 8699, la columna distingue cada operador.

| # | Severidad | Posición | Regla | Mensaje | Ancla fuente |
| ---: | --- | --- | --- | --- | --- |
| 1 | info | 16:8 | `depend_on_referenced_packages` | M1 | `import 'package:_discoveryapis_commons/_discoveryapis_commons.dart' as commons;` |
| 2 | warning | 363:10 | `unused_element_parameter` | M2 | `this.errors = const <String>[],` |
| 3 | warning | 528:11 | `unused_field` | M3 | `String? _googleDriveBackupAccountEmail;` |
| 4 | warning | 3193:8 | `unused_element` | M4 | `void _openSimulationMode(SimulationMode mode) {` |
| 5 | info | 3347:28 | `use_build_context_synchronously` | M5 | `Navigator.of(dialogContext).pop();` |
| 6 | info | 3913:31 | `use_build_context_synchronously` | M6 | `pageContext,` |
| 7 | info | 3924:31 | `use_build_context_synchronously` | M6 | `context: sheetContext,` |
| 8 | info | 3977:40 | `use_build_context_synchronously` | M6 | `Navigator.of(sheetContext).pop();` |
| 9 | info | 8246:31 | `library_private_types_in_public_api` | M7 | `final Future<void> Function(_OcrMovementCandidate candidate) onAddFromOcr;` |
| 10 | info | 8486:7 | `curly_braces_in_flow_control_structures` | M8 | `score++;` (primera ocurrencia consecutiva) |
| 11 | info | 8488:7 | `curly_braces_in_flow_control_structures` | M8 | `score++;` (segunda ocurrencia consecutiva) |
| 12 | warning | 8673:22 | `unnecessary_non_null_assertion` | M9 | `grossQuantity! * unitPrice > amountMxn * 2) {` |
| 13 | warning | 8678:47 | `unnecessary_non_null_assertion` | M9 | `final double candidate = grossQuantity! / divisor;` |
| 14 | warning | 8693:39 | `unnecessary_non_null_assertion` | M9 | `cryptoFee != null && cryptoFee! > 0 && cryptoFeeCoin == coin;` |
| 15 | warning | 8699:33 | `unnecessary_non_null_assertion` | M9 | `? correctedGrossQuantity! - cryptoFee!` (primer `!`) |
| 16 | warning | 8699:46 | `unnecessary_non_null_assertion` | M9 | `? correctedGrossQuantity! - cryptoFee!` (segundo `!`) |
| 17 | info | 8706:7 | `curly_braces_in_flow_control_structures` | M8 | `addWarning('Cantidad cripto no detectada.');` |
| 18 | warning | 8731:76 | `unnecessary_non_null_assertion` | M9 | `compact(cryptoFee!)` en el texto `Comisión Bitso ... descontada` |
| 19 | warning | 8732:76 | `unnecessary_non_null_assertion` | M9 | `compact(cryptoFee!)` en el texto `Comisión Bitso ... detectada` |
| 20 | warning | 9431:8 | `unused_element` | M10 | `void _showDetectedOcrText(BuildContext pageContext, String text) {` |
| 21 | info | 19838:27 | `deprecated_member_use` | M11 | `groupValue: selectedAutomation,` |
| 22 | info | 19840:27 | `deprecated_member_use` | M12 | `onChanged: (SnapshotAutomationMode? value) {` |
| 23 | info | 21299:7 | `curly_braces_in_flow_control_structures` | M8 | `return Icons.report_gmailerrorred_outlined;` |
| 24 | info | 21301:7 | `curly_braces_in_flow_control_structures` | M8 | `return Icons.dashboard_customize_outlined;` |
| 25 | info | 21992:27 | `deprecated_member_use` | M11 | `groupValue: positionSortMode,` |
| 26 | info | 21994:27 | `deprecated_member_use` | M12 | `onChanged: (PositionSortMode? value) {` |
| 27 | info | 22077:27 | `deprecated_member_use` | M11 | `groupValue: snapshotAutomationMode,` |
| 28 | info | 22079:27 | `deprecated_member_use` | M12 | `onChanged: (SnapshotAutomationMode? value) {` |
| 29 | info | 22081:31 | `curly_braces_in_flow_control_structures` | M8 | `onSnapshotAutomationModeChanged(value);` |
| 30 | info | 22808:5 | `curly_braces_in_flow_control_structures` | M8 | `return 'Arriba del equilibrio';` |

### Modos de comparación

1. **Entre toolchains diferentes.** La identidad se compara por archivo
   relativo, severidad, regla, ancla fuente verificable y multiplicidad. El
   mensaje completo siempre se conserva como evidencia, pero por sí solo no
   crea una identidad nueva durante esta transición documentada. No se aplica
   ninguna normalización general de puntuación o palabras.
2. **Implementación restante con Flutter 3.44.0 y Dart 3.12.0.** La identidad
   vuelve a exigir coincidencia exacta de archivo relativo, severidad, regla,
   ancla, multiplicidad y mensaje actual completo (M1–M12). Cualquier mensaje
   distinto es una identidad nueva.

### Conclusión de equivalencia semántica

La transición conserva exactamente los mismos 30 sitios: el mismo archivo, las
mismas severidades, reglas, anclas y multiplicidades (11 warnings y 19 infos).
Las diferencias se limitan a las 12 redacciones descritas: representación de
código, puntuación final, explicitación del símbolo en dos sugerencias y texto
adicional de deprecación en `Radio`. Por tanto, la huella nueva es semánticamente
equivalente a la histórica; no hay diagnósticos añadidos, eliminados ni
trasladados.

Desde esta actualización siguen rigiendo cero identidades nuevas, un máximo de
30 diagnósticos y la explicación obligatoria de cualquier eliminación o traslado.
El diagnóstico 31, o cualquier identidad nueva aunque el total permanezca en 30,
detiene la etapa.
