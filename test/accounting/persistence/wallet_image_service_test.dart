import 'dart:io';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/persistence/method_channel_wallet_image_processor.dart';
import 'package:cripto_control_mx/accounting/persistence/wallet_image_processor.dart';
import 'package:cripto_control_mx/accounting/persistence/wallet_image_store.dart';
import 'package:cripto_control_mx/accounting/support/sha256.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'private store verifies hash and never persists an absolute path',
    () async {
      final root = await Directory.systemTemp.createTemp('wallet_images_test_');
      addTearDown(() => root.delete(recursive: true));
      final bytes = Uint8List.fromList(<int>[137, 80, 78, 71]);
      final hash = sha256BytesHex(bytes);
      final image = ProcessedWalletImage(
        bytes,
        WalletImageRef.create(
          id: hash,
          fileName: '$hash.png',
          mimeType: 'image/png',
          sha256: hash,
          width: 1,
          height: 1,
          byteLength: bytes.length,
        ),
      );
      final store = PrivateWalletImageStore(
        applicationSupportDirectory: () async => root,
      );

      await store.write(image);

      expect(await store.read(image.imageRef), image.bytes);
      expect(image.imageRef.id, image.imageRef.sha256);
      expect(image.imageRef.fileName, '${image.imageRef.sha256}.png');
      expect(image.imageRef.fileName.contains('/'), isFalse);
      expect(image.imageRef.fileName.contains(r'\'), isFalse);
      expect(image.imageRef.fileName.contains(':'), isFalse);
      expect(
        File(
          '${root.path}${Platform.pathSeparator}wallet_images${Platform.pathSeparator}${image.imageRef.fileName}',
        ).existsSync(),
        isTrue,
      );
      expect(
        image.imageRef.toJson().values.whereType<String>().join(),
        isNot(contains(root.path)),
      );
    },
  );

  test(
    'private store rejects an unsupported MIME type before staging',
    () async {
      final root = await Directory.systemTemp.createTemp('wallet_images_test_');
      addTearDown(() => root.delete(recursive: true));
      final bytes = Uint8List.fromList(<int>[137, 80, 78, 71]);
      final hash = sha256BytesHex(bytes);
      final store = PrivateWalletImageStore(
        applicationSupportDirectory: () async => root,
      );
      final invalid = WalletImageRef(
        id: hash,
        fileName: '$hash.jpg',
        mimeType: 'image/gif',
        sha256: hash,
        width: 1,
        height: 1,
        byteLength: bytes.length,
      );

      expect(
        () => store.stageAll(<ProcessedWalletImage>[
          ProcessedWalletImage(bytes, invalid),
        ]),
        throwsArgumentError,
      );
      expect(
        Directory(
          '${root.path}${Platform.pathSeparator}wallet_images',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'duplicate staged images commit without orphan temporary files',
    () async {
      final root = await Directory.systemTemp.createTemp('wallet_images_test_');
      addTearDown(() => root.delete(recursive: true));
      final bytes = Uint8List.fromList(<int>[137, 80, 78, 71]);
      final hash = sha256BytesHex(bytes);
      final image = ProcessedWalletImage(
        bytes,
        WalletImageRef.create(
          id: hash,
          fileName: '$hash.png',
          mimeType: 'image/png',
          sha256: hash,
          width: 1,
          height: 1,
          byteLength: bytes.length,
        ),
      );
      final store = PrivateWalletImageStore(
        applicationSupportDirectory: () async => root,
      );

      final batch = await store.stageAll(<ProcessedWalletImage>[image, image]);
      await batch.commit();

      final files = await Directory(
        '${root.path}${Platform.pathSeparator}wallet_images',
      ).list().toList();
      expect(
        files.map((file) => file.path).where((path) => path.endsWith('.tmp')),
        isEmpty,
      );
      expect(files, hasLength(1));
      expect(await store.read(image.imageRef), image.bytes);
    },
  );

  test(
    'commit cleans a staged temporary when an equivalent target appears first',
    () async {
      final root = await Directory.systemTemp.createTemp('wallet_images_test_');
      addTearDown(() => root.delete(recursive: true));
      final bytes = Uint8List.fromList(<int>[137, 80, 78, 71]);
      final hash = sha256BytesHex(bytes);
      final image = ProcessedWalletImage(
        bytes,
        WalletImageRef.create(
          id: hash,
          fileName: '$hash.png',
          mimeType: 'image/png',
          sha256: hash,
          width: 1,
          height: 1,
          byteLength: bytes.length,
        ),
      );
      final store = PrivateWalletImageStore(
        applicationSupportDirectory: () async => root,
      );

      final first = await store.stageAll(<ProcessedWalletImage>[image]);
      final second = await store.stageAll(<ProcessedWalletImage>[image]);
      await first.commit();
      await second.commit();

      final files = await Directory(
        '${root.path}${Platform.pathSeparator}wallet_images',
      ).list().toList();
      expect(
        files.map((file) => file.path).where((path) => path.endsWith('.tmp')),
        isEmpty,
      );
      expect(files, hasLength(1));
      expect(await store.read(image.imageRef), image.bytes);
    },
  );

  test('commit rejects a corrupt target that appears after staging', () async {
    final root = await Directory.systemTemp.createTemp('wallet_images_test_');
    addTearDown(() => root.delete(recursive: true));
    final bytes = Uint8List.fromList(<int>[137, 80, 78, 71]);
    final hash = sha256BytesHex(bytes);
    final image = ProcessedWalletImage(
      bytes,
      WalletImageRef.create(
        id: hash,
        fileName: '$hash.png',
        mimeType: 'image/png',
        sha256: hash,
        width: 1,
        height: 1,
        byteLength: bytes.length,
      ),
    );
    final store = PrivateWalletImageStore(
      applicationSupportDirectory: () async => root,
    );

    final batch = await store.stageAll(<ProcessedWalletImage>[image]);
    final imageDirectory = Directory(
      '${root.path}${Platform.pathSeparator}wallet_images',
    );
    final target = File(
      '${imageDirectory.path}${Platform.pathSeparator}${image.imageRef.fileName}',
    )..writeAsBytesSync(<int>[0, 1, 2, 3], flush: true);

    await expectLater(batch.commit(), throwsStateError);
    expect(target.readAsBytesSync(), <int>[0, 1, 2, 3]);
    expect(
      imageDirectory.listSync().whereType<File>().where(
        (file) => file.path.endsWith('.tmp'),
      ),
      isEmpty,
    );
  });

  test(
    'private store rejects a corrupt pre-existing hash-path before staging',
    () async {
      final root = await Directory.systemTemp.createTemp('wallet_images_test_');
      addTearDown(() => root.delete(recursive: true));
      final bytes = Uint8List.fromList(<int>[137, 80, 78, 71]);
      final hash = sha256BytesHex(bytes);
      final image = ProcessedWalletImage(
        bytes,
        WalletImageRef.create(
          id: hash,
          fileName: '$hash.png',
          mimeType: 'image/png',
          sha256: hash,
          width: 1,
          height: 1,
          byteLength: bytes.length,
        ),
      );
      final imageDirectory = Directory(
        '${root.path}${Platform.pathSeparator}wallet_images',
      )..createSync(recursive: true);
      final target = File(
        '${imageDirectory.path}${Platform.pathSeparator}${image.imageRef.fileName}',
      )..writeAsBytesSync(<int>[0, 1, 2, 3]);
      final store = PrivateWalletImageStore(
        applicationSupportDirectory: () async => root,
      );

      await expectLater(
        store.stageAll(<ProcessedWalletImage>[image]),
        throwsStateError,
      );

      expect(target.readAsBytesSync(), <int>[0, 1, 2, 3]);
      expect(
        imageDirectory.listSync().whereType<File>().where(
          (file) => file.path.endsWith('.tmp'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'private store rejects unsafe or manipulated durable references',
    () async {
      final root = await Directory.systemTemp.createTemp('wallet_images_test_');
      addTearDown(() => root.delete(recursive: true));
      final bytes = Uint8List.fromList(<int>[137, 80, 78, 71]);
      final hash = sha256BytesHex(bytes);
      final store = PrivateWalletImageStore(
        applicationSupportDirectory: () async => root,
      );

      for (final fileName in <String>[
        '../x.png',
        'wallet_images/x.png',
        r'C:\x.png',
        '/x.png',
        r'\\server\x.png',
      ]) {
        expect(
          () => WalletImageRef.fromJson(<String, Object?>{
            'id': hash,
            'fileName': fileName,
            'mimeType': 'image/png',
            'sha256': hash,
            'width': 1,
            'height': 1,
            'byteLength': bytes.length,
          }),
          throwsArgumentError,
        );
      }
      final manipulated = WalletImageRef(
        id: hash,
        fileName: '${'a' * 64}.png',
        mimeType: 'image/png',
        sha256: hash,
        width: 1,
        height: 1,
        byteLength: bytes.length,
      );
      expect(
        () => store.write(ProcessedWalletImage(bytes, manipulated)),
        throwsArgumentError,
      );
    },
  );

  test(
    'channel processor sends normalized arguments and decodes PNG output',
    () async {
      const channel = MethodChannel('mx.criptocontrolmx.app/wallet_images');
      final output = Uint8List.fromList(<int>[137, 80, 78, 71]);
      final hash = sha256BytesHex(output);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'process');
            expect(call.arguments, <String, Object?>{
              'bytes': Uint8List.fromList(<int>[1, 2, 3]),
              'preserveAlpha': true,
              'maxLongEdge': 1024,
              'jpegQuality': 82,
            });
            return <String, Object?>{
              'bytes': output,
              'width': 1,
              'height': 1,
              'mimeType': 'image/png',
              'sha256': hash,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final image = await MethodChannelWalletImageProcessor().process(
        Uint8List.fromList(<int>[1, 2, 3]),
        preserveAlpha: true,
      );

      expect(image.bytes, output);
      expect(image.imageRef.mimeType, 'image/png');
      expect(image.imageRef.fileName, '$hash.png');
      expect(image.imageRef.width, 1);
      expect(image.imageRef.height, 1);
    },
  );

  test('channel processor surfaces corrupt image failures', () async {
    const channel = MethodChannel('mx.criptocontrolmx.app/wallet_images');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'invalid_image'),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    expect(
      () => MethodChannelWalletImageProcessor().process(
        Uint8List.fromList(<int>[0]),
        preserveAlpha: false,
      ),
      throwsA(isA<WalletImageProcessingException>()),
    );
  });

  test('native image decode planner computes bounded sample sizes', () async {
    final compileResult = await Process.run(
      r'.\gradlew.bat',
      <String>[':app:compileDebugKotlin'],
      workingDirectory: 'android',
      runInShell: true,
    );
    expect(
      compileResult.exitCode,
      0,
      reason: '${compileResult.stdout}\n${compileResult.stderr}',
    );

    final classes = Directory('build/app/tmp/kotlin-classes/debug');
    expect(classes.existsSync(), isTrue);
    final root = await Directory.systemTemp.createTemp(
      'wallet_image_decode_plan_',
    );
    addTearDown(() => root.delete(recursive: true));
    final runner = File('${root.path}/WalletImageDecodePlannerRunner.java');
    await runner.writeAsString('''
package mx.criptocontrolmx.app;

public final class WalletImageDecodePlannerRunner {
  public static void main(String[] args) {
    expect(1, WalletImageDecodePlanner.INSTANCE.inSampleSize(1024, 640, 1024));
    expect(8, WalletImageDecodePlanner.INSTANCE.inSampleSize(12000, 8000, 1024));
    expect(4, WalletImageDecodePlanner.INSTANCE.inSampleSize(3000, 8000, 1024));
    try {
      WalletImageDecodePlanner.INSTANCE.inSampleSize(0, 9000, 1024);
      throw new AssertionError("invalid bounds accepted");
    } catch (IllegalArgumentException expected) {
      expect("Image bounds must be positive", expected.getMessage());
    }
  }

  private static void expect(Object expected, Object actual) {
    if (!expected.equals(actual)) {
      throw new AssertionError("Expected " + expected + " but was " + actual);
    }
  }
}
''');

    final javacResult = await Process.run('javac', <String>[
      '-cp',
      classes.path,
      '-d',
      root.path,
      runner.path,
    ]);
    expect(
      javacResult.exitCode,
      0,
      reason: '${javacResult.stdout}\n${javacResult.stderr}',
    );
    final javaResult = await Process.run('java', <String>[
      '-cp',
      '${root.path}${Platform.isWindows ? ';' : ':'}${classes.path}',
      'mx.criptocontrolmx.app.WalletImageDecodePlannerRunner',
    ]);
    expect(
      javaResult.exitCode,
      0,
      reason: '${javaResult.stdout}\n${javaResult.stderr}',
    );
  });
}
