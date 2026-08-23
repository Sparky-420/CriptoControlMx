import 'dart:convert';
import 'dart:typed_data';

import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/wallets/ui/wallets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WalletsScreen', () {
    testWidgets('shows empty state when there are no wallets', (tester) async {
      await tester.pumpWidget(_WalletsTestApp(wallets: const <Wallet>[]));

      expect(find.text('Carteras'), findsOneWidget);
      expect(find.text('Aún no tienes carteras configuradas.'), findsOneWidget);
      expect(find.text('Nueva cartera'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('opens create form from new wallet button', (tester) async {
      await tester.pumpWidget(_WalletsTestApp(wallets: const <Wallet>[]));

      await tester.tap(find.text('Nueva cartera'));
      await tester.pumpAndSettle();

      expect(find.text('Crear cartera'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Nombre'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Plataforma'), findsOneWidget);
    });

    testWidgets('shows an error when creating with an empty name', (
      tester,
    ) async {
      await tester.pumpWidget(_WalletsTestApp(wallets: const <Wallet>[]));

      await tester.tap(find.text('Nueva cartera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();

      expect(find.text('Ingresa un nombre.'), findsOneWidget);
    });

    testWidgets('creates a wallet through the injected seam', (tester) async {
      final created =
          <({String name, String provider, Uint8List? imageBytes})>[];
      await tester.pumpWidget(
        _WalletsTestApp(
          wallets: const <Wallet>[],
          onCreateWallet:
              ({required name, required provider, imageBytes}) async {
                created.add((
                  name: name,
                  provider: provider,
                  imageBytes: imageBytes,
                ));
                return _wallet(name: name, provider: provider);
              },
        ),
      );

      await tester.tap(find.text('Nueva cartera'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'),
        '  Bitso  ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Plataforma'),
        '  Bitso México  ',
      );
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();

      expect(created, <({String name, String provider, Uint8List? imageBytes})>[
        (name: 'Bitso', provider: 'Bitso México', imageBytes: null),
      ]);
      expect(find.text('Bitso'), findsOneWidget);
      expect(find.text('Bitso México'), findsOneWidget);
    });

    testWidgets('renders an active wallet', (tester) async {
      await tester.pumpWidget(
        _WalletsTestApp(wallets: <Wallet>[_wallet(name: 'Mercado Pago')]),
      );

      expect(find.text('Mercado Pago'), findsOneWidget);
      expect(find.text('Activa'), findsOneWidget);
      expect(find.text('MP'), findsOneWidget);
    });

    testWidgets('renders a wallet image when imageRef is resolvable', (
      tester,
    ) async {
      await tester.pumpWidget(
        _WalletsTestApp(
          wallets: <Wallet>[_wallet(name: 'Mercado Pago', imageRef: imageRef)],
          imageResolver: (_) async => transparentPng,
        ),
      );

      await tester.pump();

      expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundImage,
        isA<MemoryImage>(),
      );
      expect(find.text('MP'), findsNothing);
    });

    testWidgets('renders an archived wallet', (tester) async {
      await tester.pumpWidget(
        _WalletsTestApp(
          wallets: <Wallet>[
            _wallet(name: 'Cold Storage', status: WalletStatus.archived),
          ],
        ),
      );

      expect(find.text('Cold Storage'), findsOneWidget);
      expect(find.text('Archivada'), findsOneWidget);
      expect(find.text('CS'), findsOneWidget);
    });

    testWidgets('edits a wallet through the injected seam', (tester) async {
      final original = _wallet(name: 'Bitso', provider: 'Bitso');
      final updates =
          <
            ({String id, String name, String provider, Uint8List? imageBytes})
          >[];
      await tester.pumpWidget(
        _WalletsTestApp(
          wallets: <Wallet>[original],
          onUpdateWallet:
              (wallet, {required name, required provider, imageBytes}) async {
                updates.add((
                  id: wallet.id,
                  name: name,
                  provider: provider,
                  imageBytes: imageBytes,
                ));
                return _wallet(name: name, provider: provider);
              },
        ),
      );

      await tester.tap(find.byTooltip('Editar Bitso'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'),
        'Bitso Principal',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Plataforma'),
        'Bitso México',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(
        updates,
        <({String id, String name, String provider, Uint8List? imageBytes})>[
          (
            id: original.id,
            name: 'Bitso Principal',
            provider: 'Bitso México',
            imageBytes: null,
          ),
        ],
      );
      expect(find.text('Bitso Principal'), findsOneWidget);
      expect(find.text('Bitso México'), findsOneWidget);
      expect(find.text('Bitso'), findsNothing);
    });

    testWidgets('changing image passes selected bytes to the save seam', (
      tester,
    ) async {
      final imageBytes = Uint8List.fromList(<int>[1, 2, 3]);
      final created = <Uint8List?>[];
      await tester.pumpWidget(
        _WalletsTestApp(
          wallets: const <Wallet>[],
          imagePicker: () async => imageBytes,
          onCreateWallet:
              ({required name, required provider, imageBytes}) async {
                created.add(imageBytes);
                return _wallet(
                  name: name,
                  provider: provider,
                  imageRef: imageRef,
                );
              },
        ),
      );

      await tester.tap(find.text('Nueva cartera'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'),
        'Bitso',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Plataforma'),
        'Bitso',
      );
      await tester.tap(find.text('Cambiar imagen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();

      expect(created.single, imageBytes);
    });

    testWidgets('image picker failure shows error and keeps existing data', (
      tester,
    ) async {
      final original = _wallet(name: 'Bitso', provider: 'Bitso');
      await tester.pumpWidget(
        _WalletsTestApp(
          wallets: <Wallet>[original],
          imagePicker: () => throw StateError('bad image'),
        ),
      );

      await tester.tap(find.byTooltip('Editar Bitso'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cambiar imagen'));
      await tester.pumpAndSettle();

      expect(find.text('No se pudo procesar la imagen.'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Nombre'), findsOneWidget);
      expect(find.text('Bitso'), findsWidgets);
    });
  });
}

class _WalletsTestApp extends StatelessWidget {
  const _WalletsTestApp({
    required this.wallets,
    this.onCreateWallet,
    this.onUpdateWallet,
    this.imageResolver,
    this.imagePicker,
  });

  final List<Wallet> wallets;
  final CreateWalletCallback? onCreateWallet;
  final UpdateWalletCallback? onUpdateWallet;
  final WalletImageResolver? imageResolver;
  final WalletImagePicker? imagePicker;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: WalletsScreen(
        wallets: wallets,
        onCreateWallet: onCreateWallet ?? _defaultCreateWallet,
        onUpdateWallet: onUpdateWallet ?? _defaultUpdateWallet,
        imageResolver: imageResolver,
        imagePicker: imagePicker,
      ),
    );
  }
}

Wallet _wallet({
  required String name,
  String provider = 'Proveedor',
  WalletStatus status = WalletStatus.active,
  WalletImageRef? imageRef,
}) {
  final now = DateTime.utc(2026, 8, 23);
  final wallet = Wallet.create(
    id: '11111111-1111-4111-8111-111111111111',
    name: name,
    provider: provider,
    imageRef: imageRef,
    createdAt: now,
  );
  if (status == WalletStatus.active) return wallet;
  return Wallet(
    id: wallet.id,
    name: wallet.name,
    provider: wallet.provider,
    status: status,
    createdAt: wallet.createdAt,
    updatedAt: wallet.updatedAt,
    imageRef: wallet.imageRef,
    colorArgb: wallet.colorArgb,
    note: wallet.note,
    schemaVersion: wallet.schemaVersion,
  );
}

Future<Wallet> _defaultCreateWallet({
  required String name,
  required String provider,
  Uint8List? imageBytes,
}) async => _wallet(name: name, provider: provider);

Future<Wallet> _defaultUpdateWallet(
  Wallet wallet, {
  required String name,
  required String provider,
  Uint8List? imageBytes,
}) async => _wallet(name: name, provider: provider);

final imageRef = WalletImageRef.create(
  id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  fileName:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png',
  mimeType: 'image/png',
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  width: 1,
  height: 1,
  byteLength: transparentPng.length,
);

final transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lK3QJwAAAABJRU5ErkJggg==',
);
