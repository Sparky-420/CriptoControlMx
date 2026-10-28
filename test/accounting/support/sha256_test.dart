import 'package:cripto_control_mx/accounting/support/sha256.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SHA-256 matches the standard empty-input vector', () {
    expect(sha256Hex(''), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  });

  test('canonical JSON ignores nested map insertion order', () {
    expect(
      canonicalJson(<String, Object?>{'outer': <String, Object?>{'z': 1, 'a': 2}}),
      canonicalJson(<String, Object?>{'outer': <String, Object?>{'a': 2, 'z': 1}}),
    );
  });
  test('canonical JSON has stable SHA-256 and RFC-4122 shaped UUID', () {
    final payload = <String, Object?>{
      'z': <Object?>[true, null, 2],
      'a': <String, Object?>{'b': 'texto'},
    };

    expect(canonicalJson(payload), '{"a":{"b":"texto"},"z":[true,null,2]}');
    expect(
      sha256Hex(canonicalJson(payload)),
      '79ba9c08115186873a77ee2d2dd2432415b9a71b3ee32acf3898f270c8ef973f',
    );
    expect(
      deterministicUuidFromSha256(canonicalJson(payload)),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });
}
