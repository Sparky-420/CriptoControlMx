# Arquitectura de carteras contables de CriptoControlMx

Fecha: 2026-08-10

Estado: diseño conceptual aprobado

Rama de trabajo: `feature/carteras-contables`

HEAD base: `eb87a4ce6b371547690f8825feb8384ba5b610b1`

## 1. Contexto e inspección

CriptoControlMx conserva actualmente estado, persistencia, importación,
exportación, sincronización, formularios, navegación y cálculo financiero en
`lib/cripto_control_app.dart`, que tiene 25,716 líneas en el HEAD base. El modelo
`Movement` contiene nombres de plataforma y el motor considera una transferencia
estructurada como propia cuando origen y destino tienen texto. Esa condición no
demuestra propiedad y hace que una transferencia a un tercero pueda acreditar
un destino interno y reducir el saldo global únicamente por la comisión.

La persistencia local usa `SharedPreferences`; los respaldos locales, Google
Drive y Firebase comparten el JSON generado por la aplicación. El respaldo v2
no contiene carteras ni imágenes. Los saldos por plataforma también se derivan
de nombres, por lo que no distinguen varias cuentas del mismo proveedor.

El motor vigente calcula el costo conocido por promedio ponderado:
`average = costBase / quantity`. Este método se conserva. La nueva arquitectura
no introduce FIFO, LIFO ni selección de lotes.

La baseline de calidad está documentada en
`docs/superpowers/baselines/2026-08-10-wallets-baseline.md`: 43 pruebas
aprobadas, 30 diagnósticos preexistentes de `flutter analyze` y
`git diff --check` limpio. La implementación no puede introducir diagnósticos
nuevos.

## 2. Objetivos

- Representar cada cartera propia mediante un ID estable independiente del
  proveedor y del nombre visible.
- Permitir varias carteras del mismo proveedor.
- Distinguir inequívocamente transferencias internas y externas.
- Reconstruir determinísticamente custodia, rendimiento y conciliación desde
  movimientos, sin persistir saldos derivados.
- Mantener separado el saldo realmente observado de la posición con costo
  conocido.
- Preservar movimientos y respaldos históricos sin inventar propiedad.
- Mantener compatibilidad con JSON, CSV y XLSX anteriores.
- Copiar, normalizar, respaldar y restaurar imágenes en almacenamiento privado.
- Mantener `cripto_control_app.dart` como coordinador temporal, sin añadirle
  lógica contable nueva.

## 3. Fuera de alcance

- Publicar beta.11 build 12 o incrementar la versión.
- Generar APK o AAB.
- Cambiar el método de costo promedio ponderado.
- Reemplazar toda la persistencia por SQLite o por un libro mayor event-sourced.
- Refactorizar de forma general el monolito o limpiar sus 30 diagnósticos
  preexistentes.
- Inferir titularidad mediante proveedor, nombre, texto OCR o plataforma.
- Convertir ajustes de saldo en compras, ventas o transferencias ficticias.

## 4. Decisiones arquitectónicas

Se adopta un núcleo modular con adaptadores. El núcleo recibe modelos de dominio
y produce proyecciones puras. Los adaptadores traducen el modelo histórico,
persisten el documento versionado y alimentan la interfaz existente.

Las dos proyecciones principales son independientes:

- `CustodyProjection`: cuánto existe realmente, en qué cartera y activo.
- `PerformanceProjection`: qué cantidad tiene costo conocido, su costo promedio,
  capital invertido y P&L.

`AccountingLedgerEngine` combina ambas sin duplicar fórmulas y genera
`LedgerProjection`. Crear, editar, eliminar, importar, asignar o reclasificar un
movimiento reconstruye toda la proyección desde entradas inmutables ordenadas.

El orden canónico es:

1. fecha y hora completa ascendente;
2. ID estable del movimiento ascendente como desempate.

No se persisten saldos, promedios, P&L ni diferencias de conciliación como fuente
de verdad.

## 5. Cantidades y fechas

### 5.1 `AccountingAmount`

Los cálculos del dominio usan una representación decimal exacta, normalizada y
comparable. Los adaptadores aceptan números y strings históricos, pero el JSON
v3 escribe strings decimales canónicos. La conversión a `double` queda limitada
a APIs de presentación o librerías que la exijan.

La tolerancia de importes se define en un solo lugar del dominio. La ecuación
del caso real debe ser exacta en la escala persistida:

```text
1 + 0.00167532 = 1.00167532
```

### 5.2 Fecha y hora

`occurredAt` conserva fecha y hora completas en ISO-8601. Ningún adaptador puede
pasar el valor por una función equivalente a `dateOnly`. La lista, detalle,
edición y exportadores consumen el mismo valor.

El defecto `20:54 -> 00:00` permanece como investigación TDD independiente. No
se atribuye una causa en esta especificación porque la inspección estática muestra
que constructor, `copyWith`, JSON y renderizado admiten hora completa. Primero se
debe ejecutar una prueba integral que atraviese formulario, modelo, persistencia,
reinicio, lista, detalle, edición y respaldo. Si no falla, se documentarán los
escenarios exactos probados sin hacer una corrección especulativa.

## 6. Modelos de dominio

### 6.1 `Wallet`

| Campo | Tipo | Regla y valor por defecto |
| --- | --- | --- |
| `id` | `String` | Obligatorio, UUID, inmutable |
| `name` | `String` | Obligatorio, recortado y no vacío |
| `provider` | `String` | Obligatorio, catálogo o texto manual |
| `imageRef` | `WalletImageRef?` | Opcional; `null` usa icono visual por defecto |
| `colorArgb` | `int?` | Opcional; sin efecto contable |
| `note` | `String?` | Opcional; vacío se normaliza a `null` |
| `status` | `WalletStatus` | `active` |
| `createdAt` | `DateTime` | Obligatorio e inmutable |
| `updatedAt` | `DateTime` | Obligatorio; cambia al editar |
| `schemaVersion` | `int` | `1` |

`WalletStatus` contiene `active` y `archived`.

El proveedor y el nombre no participan en igualdad ni propiedad. Varias carteras
pueden compartir proveedor o nombre. Un nombre duplicado produce una advertencia
no bloqueante y la UI desambigua con proveedor e ID corto.

Una cartera archivada conserva saldos e historial, no puede elegirse en
movimientos nuevos y puede restaurarse. Una cartera sin historial puede
eliminarse. Una cartera referenciada sólo puede eliminarse mediante una operación
explícita de reasignación que actualice todas las referencias en una sola
transacción lógica y reconstruya las proyecciones.

### 6.2 `WalletImageRef`

| Campo | Tipo | Regla |
| --- | --- | --- |
| `id` | `String` | Obligatorio y estable |
| `fileName` | `String` | Nombre relativo seguro, no ruta absoluta |
| `mimeType` | `String` | `image/jpeg` o `image/png` |
| `sha256` | `String` | Hash de los bytes privados normalizados |
| `width` | `int` | Mayor que cero |
| `height` | `int` | Mayor que cero |
| `byteLength` | `int` | Mayor que cero |

### 6.3 `MovementType`

El enum persistido contiene exactamente:

- `buy`
- `sell`
- `transferIn`
- `transferOut`
- `balanceAdjustment`

`transferOut` representa una salida iniciada desde una cartera propia. Tanto una
transferencia interna como una externa se guardan como un único movimiento
`transferOut`. `destinationType` determina el destino. Una transferencia interna
no crea un segundo `transferIn`; el normalizador genera dos piernas de custodia
desde el mismo ID. Esto evita duplicar movimientos, saldos e historial.

`transferIn` queda reservado para una entrada desde fuera del patrimonio propio
o para el registro histórico equivalente. No es la contrapartida persistida de
una transferencia interna.

### 6.4 Enums auxiliares

`DestinationType`:

- `ownWallet`
- `external`

`WalletAssignmentStatus`:

- `assigned`
- `partiallyAssigned`
- `pending`
- `legacyUnassigned`

`AccountingCompleteness`:

- `complete`
- `partiallyKnown`
- `pendingAssignment`
- `unassignedLegacy`

`FiatFeeTreatment`:

- `none`
- `valuationOfCryptoFee`
- `paidSeparately`
- `combined`

`SaleCostConsumptionPolicy`:

- `knownFirst`

`TransferCostAllocationPolicy`:

- `proportional`

`LegacyAccountingPolicy`:

- `preservePreviousGlobal`

Las políticas se entregan explícitamente al motor. No quedan ocultas en ramas o
fórmulas privadas.

### 6.5 `AccountingMovement`

Los campos históricos `id`, `type`, `coin`, `date`, `quantity`, `unitPrice`,
`fee`, `source`, `wallet`, `network`, `note`, `createdAt`, `updatedAt`,
`deletedAt`, `deviceId` y `schemaVersion` se conservan mediante el adaptador.

El modelo canónico usa:

| Campo | Tipo | Regla y valor por defecto |
| --- | --- | --- |
| `id` | `String` | Obligatorio y estable |
| `type` | `MovementType` | Obligatorio |
| `asset` | `String` | Obligatorio, mayúsculas |
| `occurredAt` | `DateTime` | Obligatorio, conserva hora |
| `quantity` | `AccountingAmount?` | Compra, venta y entrada; `null` en ajuste |
| `unitPriceFiat` | `AccountingAmount?` | Requerido donde exista costo o venta |
| `fiatFeeAmount` | `AccountingAmount` | Comisión fiat realmente pagada; cero por defecto |
| `sourceWalletId` | `String?` | Requerido para venta y `transferOut` nuevo |
| `destinationWalletId` | `String?` | Requerido para compra, `transferIn` e interno |
| `destinationType` | `DestinationType?` | Requerido sólo en `transferOut` nuevo |
| `externalRecipientName` | `String?` | Sólo destino externo |
| `externalDestinationPlatform` | `String?` | Sólo destino externo |
| `walletAssignmentStatus` | `WalletAssignmentStatus` | `assigned` en movimientos nuevos válidos |
| `receivedAmount` | `AccountingAmount?` | Canónico para `transferOut` |
| `cryptoFeeAmount` | `AccountingAmount` | Cero por defecto |
| `cryptoFeeAsset` | `String?` | Requerido cuando la comisión cripto es mayor que cero |
| `totalDebitedAmount` | `AccountingAmount?` | Requerido para `transferOut` |
| `feeFiatValue` | `AccountingAmount?` | Valor informativo MXN de la comisión cripto |
| `fiatFeeTreatment` | `FiatFeeTreatment` | `none` |
| `network` | `String?` | Opcional |
| `note` | `String?` | Opcional |
| `adjustmentWalletId` | `String?` | Requerido sólo en ajuste |
| `adjustmentQuantity` | `AccountingAmount?` | Firmado y distinto de cero sólo en ajuste |
| `observedBalance` | `AccountingAmount?` | No negativo y requerido en ajuste |
| `adjustmentReason` | `String?` | No vacío y requerido en ajuste |
| `reconciliationLinks` | `List<ReconciliationLink>` | Vacía por defecto |
| `createdAt` | `DateTime` | Obligatorio |
| `updatedAt` | `DateTime` | Obligatorio |
| `schemaVersion` | `int` | `3` |

En JSON v3, `receivedAmount` es la fuente canónica de cantidad transferida. El
adaptador puede emitir también `quantity` para consumidores históricos, pero
ambos valores deben coincidir. Una diferencia es un error de validación, no una
oportunidad para elegir silenciosamente uno.

### 6.6 Roles de cartera por tipo

| Tipo | Cartera origen | Cartera destino | `destinationType` |
| --- | --- | --- | --- |
| Compra | `null` | Obligatoria | `null` |
| Venta | Obligatoria | `null` | `null` |
| Entrada externa | `null` | Obligatoria | `null` |
| Transferencia interna | Obligatoria | Obligatoria y diferente | `ownWallet` |
| Transferencia externa | Obligatoria | `null` | `external` |
| Ajuste | `adjustmentWalletId` | No aplica | `null` |

Los campos `sourcePlatform` y `destinationPlatform` históricos permanecen como
metadatos y ayuda de migración; nunca satisfacen un rol de cartera.

### 6.7 `ReconciliationLink`

| Campo | Tipo | Regla |
| --- | --- | --- |
| `adjustmentMovementId` | `String` | Debe señalar un ajuste existente |
| `quantityResolved` | `AccountingAmount` | Positiva y no mayor que la diferencia pendiente |

El movimiento real y el ajuste deben coincidir en cartera, activo y dirección
de custodia. El vínculo conserva el ajuste original en el historial y evita
duplicar la tenencia cuando una diferencia se justifica posteriormente.

## 7. Normalización y validación

`MovementNormalizer` es puro. Traduce cada movimiento persistido a piernas de
custodia, instrucciones de rendimiento y problemas estructurados. No consulta
widgets, `SharedPreferences` ni precios remotos.

### 7.1 Errores bloqueantes para movimientos nuevos

- ID, activo y fecha/hora válidos.
- Cartera requerida existente y activa.
- Origen y destino propios diferentes.
- `ownWallet` exige `destinationWalletId`.
- `external` exige `destinationWalletId == null`.
- Metadatos de destinatario externo sólo se aceptan en destino externo.
- Cantidades de compra, venta y transferencia mayores que cero.
- Ajuste firmado distinto de cero, saldo observado no negativo y motivo no vacío.
- Comisión cripto no negativa y con activo cuando es mayor que cero.
- `totalDebitedAmount`, principal y comisión deben cuadrar.
- `feeFiatValue` exige tratamiento fiat explícito.
- `valuationOfCryptoFee` no crea una segunda comisión.
- Los vínculos de conciliación deben apuntar a ajustes compatibles y no resueltos.
- Un movimiento nuevo no puede producir custodia insuficiente.

### 7.2 Históricos incompatibles

Un movimiento histórico o importado incompatible no se descarta. Se conserva
visible y auditable, produce `ProjectionIssue` y sólo aplica hasta la custodia
disponible. El resultado contiene `requestedQuantity`, `appliedQuantity` y
`unappliedQuantity`; nunca fabrica un saldo negativo ni oculta la diferencia.

## 8. Contratos de las proyecciones

### 8.1 Entrada del coordinador

```text
LedgerInput
  wallets: List<Wallet>
  movements: List<AccountingMovement>
  currentPrices: Map<Asset, AccountingAmount>
  saleCostConsumptionPolicy: knownFirst
  transferCostAllocationPolicy: proportional
  legacyAccountingPolicy: preservePreviousGlobal
```

### 8.2 `CustodyProjection`

Por cartera y activo entrega:

- `reconciledQuantity`;
- créditos y débitos aplicados;
- ajustes firmados y porción resuelta;
- último saldo observado;
- cantidades solicitadas pero no aplicadas;
- IDs de movimientos contribuyentes;
- estado y causas.

Incluye un agrupador virtual con ID reservado `virtual:unassigned`. Este grupo no
se persiste como `Wallet`, no puede seleccionarse y no tiene proveedor real.

### 8.3 `PerformanceProjection`

Por cartera y activo entrega:

- `knownQuantity`;
- `knownCostBasis`;
- `averageCost`;
- `investedCapital`;
- `realizedPnlKnown`;
- `unrealizedPnlKnown`;
- `pendingPnlQuantity`;
- movimientos y causas que impiden un resultado definitivo.

Los ajustes de saldo no producen ninguna instrucción de rendimiento.

### 8.4 `LedgerProjection`

Combina ambas proyecciones y entrega:

- posiciones por cartera y activo;
- totales globales;
- `MovementEffect` por ID;
- estados contables tipados;
- `ProjectionIssue`;
- progreso de migración;
- diferencias de conciliación.

También distingue `custodyMarketValue`, calculado con la tenencia conciliada, y
`knownPositionMarketValue`, calculado sólo con cantidad conocida. El P&L no
realizado usa exclusivamente el segundo.

Para cada cartera y activo:

```text
reconciliationDifference =
    custody.reconciledQuantity
  - performance.knownQuantity
```

Los pools utilizables por salidas se derivan sin inventar cantidades negativas:

```text
knownAvailable = min(performance.knownQuantity, custody.reconciledQuantity)
unknownAvailable = max(custody.reconciledQuantity - knownAvailable, 0)
custodyDeficit = max(performance.knownQuantity - custody.reconciledQuantity, 0)
```

Una diferencia positiva alimenta `unknownAvailable`. Una diferencia negativa se
expone como `custodyDeficit`; no se modela como segmento desconocido negativo.

`AccountingCompletenessResult` no es una etiqueta. Contiene:

- estado;
- cantidad total;
- cantidad con costo conocido;
- cantidad con costo desconocido;
- causa tipada;
- IDs de movimientos causantes cuando se conocen.

## 9. Efectos por tipo de movimiento

| Movimiento | Custodia | Rendimiento | P&L |
| --- | --- | --- | --- |
| Compra | Acredita destino | Añade cantidad y costo | Sin realizado |
| Venta | Debita origen validado | Consume conocido primero | Sólo porción conocida |
| Entrada externa | Acredita destino | Añade costo si se documenta; de otro modo queda desconocido | Sin realizado |
| Transferencia interna | Debita origen y acredita recibido | Mueve segmentos proporcionalmente | Sin realizado |
| Transferencia externa | Debita origen; no acredita destino propio | Retira segmentos proporcionalmente | Sin realizado |
| Ajuste positivo | Aumenta custodia | Sin efecto | Sin efecto |
| Ajuste negativo | Reduce custodia | Sin efecto | Sin efecto |

## 10. Transferencias

### 10.1 Interna

Un único movimiento `transferOut` con `destinationType == ownWallet` genera:

```text
origen.activoPrincipal -= totalDebitedAmount
destino.activoPrincipal += receivedAmount
```

El principal mueve al destino la misma proporción de segmentos con costo conocido
y desconocido que existía en el origen. El costo base conocido del principal se
conserva. La comisión retira únicamente su costo proporcional. El delta global
del principal es cero y no existe P&L realizado.

La proporción usa el estado inmediatamente anterior al movimiento:

```text
knownShare = knownAvailable / reconciledQuantity
unknownShare = unknownAvailable / reconciledQuantity
```

Principal y comisión en el mismo activo usan esas participaciones. El costo del
principal conocido se mueve al destino; el costo conocido de la comisión se
retira. Si la comisión usa otro activo, se calculan participaciones independientes
con el estado previo de ese activo. Custodia insuficiente produce un problema y
no genera una pierna negativa oculta.

### 10.2 Externa

Un único movimiento `transferOut` con `destinationType == external` exige
`destinationWalletId == null` y genera:

```text
origen.activoPrincipal -= totalDebitedAmount
destinoPropio += 0
```

El principal y la comisión salen del patrimonio. La cantidad conocida y la
desconocida se retiran proporcionalmente. Una porción sin costo produce estado
`partiallyKnown` o `pendingAssignment`, pero nunca una venta o P&L realizado.

La salida externa usa las mismas participaciones previas que la transferencia
interna. La porción de costo conocido se retira del costo base sin convertirse en
costo vendido; la porción desconocida permanece identificada como costo pendiente.

### 10.3 Caso real de Mercado Pago

```text
cartera: Mi Mercado Pago
activo: UNI
fecha y hora: 30/07/2026 20:54
receivedAmount: 1
cryptoFeeAmount: 0.00167532
totalDebitedAmount: 1.00167532
destinationType: external
destinationWalletId: null
```

Resultado:

```text
Mi Mercado Pago: -1.00167532 UNI
carteras propias destino: +0 UNI
saldo global propio: -1.00167532 UNI
P&L realizado: 0 MXN
```

El saldo observado `127.75883985 UNI` sólo se usa como dato de prueba y
conciliación; no se hardcodea ni se transforma en compra.

## 11. Comisiones

| Modalidad | Custodia | Rendimiento y reporte |
| --- | --- | --- |
| Cripto en el mismo activo | Se incluye una vez en el débito principal | Retira costo proporcional de la comisión |
| Cripto en otro activo | Debita una vez ese activo en origen | Retira su costo proporcional |
| Fiat como valoración | No debita cripto ni fiat adicional | Sólo valor informativo de la comisión cripto |
| Fiat pagada separadamente | No debita cripto | Registra gasto fiat separado, sin P&L de venta |
| Combinada | Aplica una vez la comisión cripto y una vez la fiat real | La valoración MXN no constituye un tercer pago |
| Sin comisión | No existe débito de comisión | Sin efecto adicional |

Para comisión en el mismo activo:

```text
totalDebitedAmount = receivedAmount + cryptoFeeAmount
```

Para comisión en otro activo:

```text
totalDebitedAmount = receivedAmount
origen.cryptoFeeAsset -= cryptoFeeAmount
```

`none` exige comisión fiat real cero y valoración nula. `valuationOfCryptoFee`
exige comisión cripto, comisión fiat real cero y permite `feeFiatValue`.
`paidSeparately` exige `fiatFeeAmount > 0` y valoración nula. `combined` exige
comisión cripto y `fiatFeeAmount > 0`, y permite además `feeFiatValue` como
valoración. Así una combinación aplica una sola vez cada pago real.

## 12. Costo conocido y desconocido

Cada posición mantiene segmentos de procedencia:

- cantidad con costo conocido y costo base;
- cantidad con costo desconocido y causa;
- movimiento de origen.

La cantidad desconocida nunca adquiere costo cero. Los segmentos permiten mover
o retirar proporciones sin perder trazabilidad, mientras el costo conocido sigue
usando promedio ponderado.

### 12.1 Política de ventas

La política explícita es `SaleCostConsumptionPolicy.knownFirst` y se aplica sólo
a `sell`.

Antes de procesar se valida `CustodyProjection` para la cartera y activo.

- Venta menor que la posición conocida: consume sólo conocido, retira costo al
  promedio ponderado vigente y calcula P&L completo.
- Venta exactamente igual a la posición conocida: consume todo el conocido,
  conserva cualquier diferencia positiva de custodia y calcula P&L completo.
- Venta superior a la posición conocida pero dentro de custodia: consume primero
  lo conocido y después lo desconocido necesario. El resultado es
  `partiallyKnown`.
- Venta superior a custodia: produce `insufficientCustody`, aplica como máximo la
  cantidad disponible en históricos y no fabrica saldo negativo.

Una venta parcial registra:

- cantidad vendida total;
- cantidad vendida con costo conocido;
- costo base demostrado;
- ingresos y comisión asignados a la porción conocida;
- P&L conocido;
- cantidad con costo pendiente.

Los ingresos y la comisión fiat de una venta parcialmente conocida se asignan
por cantidad al mismo precio unitario. El P&L conocido no se presenta como total
definitivo y la porción desconocida nunca usa costo cero.

### 12.2 Política de transferencias

`TransferCostAllocationPolicy.proportional` se aplica a internas y externas.
Nunca usan `knownFirst`. Se trasladan o retiran segmentos conocidos y desconocidos
en proporción a la custodia origen anterior al movimiento.

## 13. Ajustes y conciliación

`balanceAdjustment` pertenece exclusivamente a custodia.

Modifica:

- tenencia real visible;
- saldo conciliado;
- diferencia de conciliación;
- historial auditable.

No modifica:

- cantidad contable de inversión;
- segmentos de adquisición;
- costo promedio;
- capital invertido;
- compras o ventas;
- P&L realizado o no realizado.

Un ajuste positivo crea diferencia con costo desconocido. Un ajuste negativo
reduce custodia sin fingir disposición. Editar o eliminar un ajuste reconstruye
sólo los resultados de custodia y conciliación; `PerformanceProjection` debe ser
idéntica antes y después.

El ajuste guarda cantidad firmada, saldo observado, motivo, fecha, cartera,
activo y notas. En creación se valida:

```text
custodiaAnterior + adjustmentQuantity = observedBalance
```

Si una edición histórica posterior rompe esa igualdad, el ajuste se conserva y
se emite `observedBalanceMismatch`; no se cambia silenciosamente su cantidad.

### 13.1 Resolución posterior

Un movimiento real puede justificar una diferencia mediante
`ReconciliationLink`. Para una cantidad resuelta:

1. el movimiento real produce su efecto de rendimiento;
2. el ajuste conserva valor original e historial;
3. la parte resuelta deja de contribuir al ajuste efectivo;
4. el movimiento real aporta la misma pierna de custodia;
5. la custodia neta no cambia y la diferencia disminuye.

Eliminar o editar un ajuste enlazado exige eliminar, reducir o reasignar sus
vínculos en la misma transacción lógica.

## 14. Errores y estados incompletos

`ProjectionIssue` contiene:

- código estable;
- severidad;
- causa tipada;
- cartera y activo;
- cantidades solicitada, aplicada, conocida y desconocida;
- IDs de movimientos relacionados;
- mensaje de interfaz.

Causas iniciales:

- `missingWalletAssignment`
- `missingDestinationClassification`
- `unknownCostBasis`
- `insufficientCustody`
- `insufficientKnownPosition`
- `transferAmountMismatch`
- `sameSourceAndDestination`
- `unknownWallet`
- `invalidFeeTreatment`
- `invalidReconciliationLink`
- `unresolvedAdjustment`
- `observedBalanceMismatch`
- `legacyAccountingSemantics`

Los estados `complete`, `partiallyKnown`, `pendingAssignment` y
`unassignedLegacy` forman parte de la salida tipada. Ningún problema provoca que
el motor descarte silenciosamente un movimiento.

## 15. Migración legacy

Los movimientos antiguos no crean carteras. `LegacyMovementAdapter` conserva
los campos originales y asigna `legacyUnassigned` cuando no hay IDs de cartera
confirmados.

`virtual:unassigned` conserva el efecto global anterior bajo
`LegacyAccountingPolicy.preservePreviousGlobal`. En particular, una transferencia
estructurada que antes se trataba como propia mantiene su total global mientras
está pendiente, pero no acredita una cartera real.

La asignación posterior actualiza el mismo movimiento por ID. No añade una copia.
Reclasificar el destino reconstruye el total según la semántica confirmada.

La asignación masiva por plataforma:

- muestra los movimientos afectados;
- exige confirmación;
- sólo asigna el lado seleccionado;
- no deduce que el destino sea propio;
- puede dejar una transferencia `partiallyAssigned`;
- permite omitir y continuar después.

El progreso se calcula por IDs únicos asignables. La migración usa versión e ID,
transforma en lugar de anexar y es idempotente.

## 16. Persistencia, respaldo e imágenes

### 16.1 Documento local

`AccountingRepository` persiste un sobre `AccountingDocument` v3 con carteras,
movimientos y metadatos de migración. Las proyecciones no forman parte del sobre.
El adaptador lee `movements_json` histórico cuando no existe v3 y sólo escribe el
nuevo documento después de validar la migración completa.

Las escrituras reemplazan el documento lógico completo. Una importación se
valida y prepara antes de modificar el estado activo.

### 16.2 Imágenes privadas

`WalletImageStore` recibe bytes del selector, no conserva la URI temporal y:

1. decodifica la imagen;
2. limita su lado mayor a 1024 píxeles;
3. conserva PNG cuando hay transparencia;
4. usa JPEG con calidad 82 cuando no hay transparencia;
5. calcula SHA-256;
6. escribe en el directorio privado de soporte de la aplicación;
7. devuelve una referencia relativa estable.

Al reemplazar una imagen, el archivo anterior sólo se elimina después de una
escritura exitosa y si ninguna cartera lo referencia.

### 16.3 JSON v3

El respaldo contiene:

- `schemaVersion: 3`;
- `wallets`;
- `walletImages` con MIME, hash y Base64;
- `movements`;
- `snapshots`;
- `currentPrices`;
- `settings`;
- metadatos de migración.

La restauración valida esquema, IDs, hashes, referencias, importes y movimientos;
prepara imágenes en un directorio temporal y sólo después sustituye el documento
activo. Un fallo deja estado e imágenes anteriores intactos.

Firebase no puede asumir que todas las imágenes caben en un único documento.
El adaptador cloud guarda el manifiesto en `cloudState/current` y divide los
bytes de imágenes en documentos de una subcolección, con hash y orden de fragmento.
Al descargar recompone el JSON canónico antes de importarlo. Google Drive y el
respaldo local mantienen el JSON v3 autocontenido.

### 16.4 Compatibilidad v1/v2

- Acepta nombres históricos de campos, números y strings.
- Mantiene columnas y semántica histórica.
- Conserva fecha/hora ISO completa.
- Normaliza IDs faltantes o duplicados una sola vez.
- Marca asignación legacy sin inventar carteras.
- No requiere imágenes ni carteras en respaldos antiguos.

## 17. Exportación CSV y XLSX

Los encabezados históricos mantienen orden y nombre. Las columnas nuevas se
anexan después de las existentes:

- `source_wallet_id`
- `destination_wallet_id`
- `destination_type`
- `external_recipient_name`
- `external_destination_platform`
- `wallet_assignment_status`
- `adjustment_wallet_id`
- `adjustment_quantity`
- `observed_balance`
- `adjustment_reason`
- `accounting_completeness`
- `known_quantity`
- `unknown_cost_quantity`

Los exportadores reciben `LedgerProjection`; no recalculan saldos ni P&L. El JSON
de movimientos conserva campos históricos y anexa los campos v3.

## 18. Interfaz

La navegación inferior no cambia. `Más` incorpora “Carteras” y abre una página
dedicada mediante el patrón de navegación secundario existente.

La interfaz incluye:

- resumen de carteras en `Resumen`;
- listado activo y archivado;
- alta y edición con imagen, nombre, proveedor, color y nota;
- detalle con tenencia conciliada, posición con costo conocido, diferencia e
  historial exclusivo;
- archivo y restauración;
- asistente de migración individual y masiva;
- selector de cartera reutilizable;
- advertencia visible cuando custodia y rendimiento difieren.

El formulario de transferencia exige cartera origen y usa un control vigente
como `SegmentedButton` para elegir:

- “Otra de mis carteras”;
- “Persona o cuenta externa”.

No se usarán los patrones obsoletos `Radio.groupValue` ni `Radio.onChanged`.

La vista previa de impacto consume `MovementEffect` calculado por el motor y
muestra:

- débito del origen;
- crédito del destino propio, si existe;
- cambio global por activo;
- comisiones;
- cantidad conocida y desconocida afectada;
- advertencias e inconsistencias.

La UI no reproduce fórmulas del motor.

## 19. Invariantes verificables

1. Las mismas entradas producen la misma salida.
2. El orden físico de almacenamiento no cambia el orden canónico.
3. Ningún saldo derivado es fuente de verdad persistida.
4. Sumar carteras reales y `virtual:unassigned` concilia con el global.
5. `reconciliationDifference` siempre es custodia menos cantidad conocida.
6. El principal interno tiene delta global cero.
7. Una transferencia externa nunca acredita una cartera propia.
8. Cada comisión se debita una sola vez.
9. Un ajuste no cambia ningún campo de `PerformanceProjection`.
10. Venta usa `knownFirst`; transferencias usan `proportional`.
11. P&L realizado sólo se produce por ventas y sólo sobre costo demostrado.
12. Editar y revertir un movimiento restaura la proyección original.
13. Eliminar equivale a reconstruir sin el movimiento.
14. Migrar dos veces produce el mismo JSON lógico y las mismas proyecciones.
15. Nombre y proveedor nunca prueban propiedad.
16. Importar y exportar conserva IDs, hora, ajustes, vínculos e imágenes.
17. Un histórico incompatible permanece visible y no crea saldo negativo oculto.

## 20. Descomposición en archivos

```text
lib/accounting/domain/
  accounting_amount.dart
  accounting_movement.dart
  accounting_status.dart
  projection_issue.dart
  reconciliation_link.dart
  wallet.dart
  wallet_image.dart

lib/accounting/ledger/
  accounting_ledger_engine.dart
  custody_projection.dart
  movement_normalizer.dart
  performance_projection.dart
  projection_models.dart

lib/accounting/migration/
  legacy_movement_adapter.dart
  wallet_migration_service.dart

lib/accounting/persistence/
  accounting_backup_codec.dart
  accounting_repository.dart
  wallet_image_store.dart

lib/accounting/export/
  accounting_csv_exporter.dart
  accounting_xlsx_exporter.dart

lib/features/wallets/
  destination_selector.dart
  migration_wizard.dart
  transfer_impact_preview.dart
  wallet_detail_page.dart
  wallet_form_page.dart
  wallet_picker.dart
  wallet_summary.dart
  wallets_page.dart
```

`cripto_control_app.dart` importa adaptadores, conserva estado de alto nivel y
navegación temporal, y delega dominio, persistencia y exportación. No se realiza
una refactorización general no relacionada.

## 21. Descomposición por fases de arquitectura

1. Modelos, cantidades exactas, normalización y validación.
2. Proyección de custodia.
3. Proyección de rendimiento, costo promedio y P&L parcial.
4. Coordinador, adaptador legacy y migración idempotente.
5. Persistencia, imágenes y respaldo JSON v3.
6. Adaptación de CSV, XLSX, Google Drive y Firebase.
7. Adaptación del estado existente al núcleo nuevo.
8. Pantallas de carteras, migración y transferencia.
9. Investigación TDD independiente de fecha/hora.
10. Revisión y verificación integral.

Cada fase produce software comprobable, compara `flutter analyze` por archivo,
regla y mensaje contra la baseline y se detiene ante un diagnóstico nuevo.

## 22. Casos de prueba derivados

### 22.1 Carteras e imágenes

- Tres carteras Bitso obtienen IDs distintos.
- Nombre, proveedor, color, nota e imagen sobreviven guardar y cargar.
- Exportar e importar conserva bytes y hash de imagen.
- Imagen corrupta o hash incorrecto no reemplaza el estado activo.
- Archivar conserva saldos e historial.
- Restaurar permite seleccionar de nuevo.
- Eliminar con historial queda bloqueado.
- Reasignar y eliminar conserva totales.

### 22.2 Transferencias y comisiones

- Interna debita origen y acredita recibido al destino.
- Interna cambia el global sólo por comisión.
- Externa debita principal y comisión sin acreditar destino propio.
- Cambiar interna a externa reconstruye origen, destino y global.
- Cambiar externa a interna reconstruye todo sin residuos.
- Comisión en mismo activo, otro activo, sólo fiat y sin comisión.
- `valuationOfCryptoFee` no duplica la comisión.
- Transferencia completa de un saldo.
- Transferencias mueven o retiran proporcionalmente conocido y desconocido.
- Transferencias nunca usan `SaleCostConsumptionPolicy.knownFirst`.
- Caso Mercado Pago usa 1, 0.00167532 y 1.00167532.
- Caso interno equivalente demuestra el comportamiento distinto.

### 22.3 Ventas y costo parcial

- Venta menor que posición conocida consume sólo conocido.
- Venta exactamente igual a posición conocida.
- Venta superior a posición conocida produce `partiallyKnown`.
- P&L conocido usa costo promedio ponderado vigente.
- Porción desconocida nunca recibe costo cero.
- Venta con custodia insuficiente produce `insufficientCustody`.
- Diferencia positiva permanece cuando una venta cabe en conocido.
- Diferencia negativa queda advertida y no fabrica P&L.

### 22.4 Ajustes y resolución

- Ajuste positivo modifica sólo custodia.
- Ajuste negativo modifica sólo custodia.
- El ejemplo 127 + 0.75883985 produce 127.75883985 de custodia.
- Editar o eliminar ajuste deja `PerformanceProjection` idéntica.
- Saldo observado inconsistente produce `observedBalanceMismatch`.
- Vínculo válido reduce diferencia sin duplicar custodia.
- Vínculo inválido por cartera, activo, signo o cantidad se rechaza.
- Eliminar ajuste enlazado exige resolver sus vínculos.

### 22.5 Migración y compatibilidad

- JSON antiguo crea cero carteras reales.
- Movimientos legacy permanecen en el total global y grupo virtual.
- Migración repetida es un no-op lógico.
- Asignación individual no duplica movimiento.
- Asignación masiva modifica sólo IDs confirmados.
- Plataforma destino no se interpreta como propia.
- JSON v1, v2 y v3 conservan fecha/hora y campos históricos.
- CSV y XLSX mantienen columnas históricas y anexan las nuevas.

### 22.6 Reconstrucción, UI y calidad

- Orden determinista con fecha igual e IDs distintos.
- Editar, eliminar y revertir restauran exactamente las proyecciones.
- Lista, detalle y edición muestran valores idénticos.
- Selector de destino exige propia o externa inequívocamente.
- Vista previa coincide con `MovementEffect` guardado.
- Widgets nuevos no usan APIs `Radio` obsoletas.
- El flujo 30/07/2026 20:54 se prueba de extremo a extremo antes de corregir.
- Cada etapa produce cero huellas nuevas de `flutter analyze`.

## 23. Criterio de aceptación

La arquitectura no se considera integrada hasta que funcione el ciclo completo:

```text
crear cartera
-> asignar movimiento
-> guardar
-> persistir
-> reconstruir proyecciones
-> mostrar
-> editar o eliminar
-> exportar
-> importar
-> conciliar
```

El resultado debe conservar compatibilidad histórica, cero diagnósticos nuevos,
un total de análisis igual o menor que 30 y ninguna inferencia de propiedad por
nombre o proveedor.
