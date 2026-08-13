import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('H1-09 creates three same-provider wallets with distinct UUIDs', () {
    final createdAt = DateTime.utc(2026, 8, 11);
    final wallets = <Wallet>[
      Wallet.create(
        id: '11111111-1111-4111-8111-111111111111',
        name: ' Cuenta principal ',
        provider: ' Bitso ',
        note: '   ',
        createdAt: createdAt,
      ),
      Wallet.create(
        id: '22222222-2222-4222-8222-222222222222',
        name: 'Trading',
        provider: 'Bitso',
        createdAt: createdAt,
      ),
      Wallet.create(
        id: '33333333-3333-4333-8333-333333333333',
        name: 'Ahorro',
        provider: 'Bitso',
        createdAt: createdAt,
      ),
    ];

    expect(wallets.map((wallet) => wallet.id).toSet(), hasLength(3));
    expect(wallets.map((wallet) => wallet.provider).toSet(), <String>{'Bitso'});
    expect(wallets.first.name, 'Cuenta principal');
    expect(wallets.first.note, isNull);
    expect(
      wallets.every((wallet) => wallet.status == WalletStatus.active),
      isTrue,
    );
  });

  test('H1-09 creation rejects invalid wallet identity and text', () {
    final createdAt = DateTime.utc(2026, 8, 11);

    expect(
      () => Wallet.create(
        id: 'not-a-uuid',
        name: 'Wallet',
        provider: 'Bitso',
        createdAt: createdAt,
      ),
      throwsArgumentError,
    );
    expect(
      () => Wallet.create(
        id: '11111111-1111-4111-8111-111111111111',
        name: '   ',
        provider: 'Bitso',
        createdAt: createdAt,
      ),
      throwsArgumentError,
    );
    expect(
      () => Wallet.create(
        id: '11111111-1111-4111-8111-111111111111',
        name: 'Wallet',
        provider: '   ',
        createdAt: createdAt,
      ),
      throwsArgumentError,
    );
  });

  test('H1-09 image creation validates and normalizes private metadata', () {
    const upperHash =
        'ABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABAB';
    const lowerHash =
        'abababababababababababababababababababababababababababababababab';
    final image = WalletImageRef.create(
      id: ' image-1 ',
      fileName: ' wallet.png ',
      mimeType: ' IMAGE/PNG ',
      sha256: upperHash,
      width: 24,
      height: 12,
      byteLength: 128,
    );

    expect(image.id, 'image-1');
    expect(image.fileName, 'wallet.png');
    expect(image.mimeType, 'image/png');
    expect(image.sha256, lowerHash);
    for (final invalid in <WalletImageRef Function()>[
      () => WalletImageRef.create(
        id: 'image',
        fileName: '../wallet.png',
        mimeType: 'image/png',
        sha256: lowerHash,
        width: 1,
        height: 1,
        byteLength: 1,
      ),
      () => WalletImageRef.create(
        id: 'image',
        fileName: 'wallet.gif',
        mimeType: 'image/gif',
        sha256: lowerHash,
        width: 1,
        height: 1,
        byteLength: 1,
      ),
      () => WalletImageRef.create(
        id: 'image',
        fileName: 'wallet.png',
        mimeType: 'image/png',
        sha256: 'invalid',
        width: 0,
        height: 1,
        byteLength: 1,
      ),
    ]) {
      expect(invalid, throwsArgumentError);
    }
  });

  test('round trips every wallet and image field', () {
    const hash =
        'abababababababababababababababababababababababababababababababab';
    final wallet = Wallet(
      id: 'wallet-1',
      name: 'Mi Mercado Pago',
      provider: 'Mercado Pago',
      status: WalletStatus.active,
      imageRef: const WalletImageRef(
        id: hash,
        fileName: '$hash.png',
        mimeType: 'image/png',
        sha256: hash,
        width: 24,
        height: 24,
        byteLength: 3,
      ),
      colorArgb: 0xff00ff00,
      note: 'Nota',
      createdAt: DateTime.parse('2026-07-30T20:54:00-06:00'),
      updatedAt: DateTime.parse('2026-07-31T20:54:00-06:00'),
    );
    final json = wallet.toJson();
    expect(json.keys, <String>[
      'id',
      'name',
      'provider',
      'imageRef',
      'colorArgb',
      'note',
      'status',
      'createdAt',
      'updatedAt',
      'schemaVersion',
    ]);
    expect(Wallet.fromJson(json).toJson(), json);
  });
}
