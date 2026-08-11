import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trips every wallet and image field', () {
    final wallet = Wallet(
      id: 'wallet-1',
      name: 'Mi Mercado Pago',
      provider: 'Mercado Pago',
      status: WalletStatus.active,
      imageRef: const WalletImageRef(
        id: 'image-1',
        fileName: 'wallet.png',
        mimeType: 'image/png',
        sha256: 'abc',
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
