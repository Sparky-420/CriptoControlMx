# Siguiente corte seguro: conectar MainNavigationBar

## Objetivo

Reemplazar la `NavigationBar` inline de `lib/cripto_control_app.dart` por el componente extraido:

- `lib/ui/navigation/main_navigation_bar.dart`

## Riesgo

Bajo.

No toca:

- calculos financieros
- movimientos
- JSON
- snapshots
- import/export
- comisiones
- break-even

## Precondicion

Antes de aplicar este corte deben pasar:

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --debug
```

## Cambio previsto

Agregar import:

```dart
import 'package:cripto_control_mx/ui/navigation/main_navigation_bar.dart';
```

Reemplazar el bloque inline:

```dart
bottomNavigationBar: NavigationBar(
  selectedIndex: _currentIndex,
  onDestinationSelected: (int index) {
    setState(() => _currentIndex = index);
  },
  destinations: const <NavigationDestination>[
    ...
  ],
),
```

por:

```dart
bottomNavigationBar: MainNavigationBar(
  selectedIndex: _currentIndex,
  onDestinationSelected: (int index) {
    setState(() => _currentIndex = index);
  },
),
```

## Validacion posterior

Despues del cambio:

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --debug
```

## Rollback

Si falla, revertir solo el commit que conecte `MainNavigationBar`.
