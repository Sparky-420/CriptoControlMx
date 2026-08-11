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
