import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/platform/clipboard_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00];

  test('recognizes image payloads by magic bytes before the extension', () {
    expect(
      imageMimeTypeForClipboard(Uint8List.fromList(png), path: 'cache.bin'),
      'image/png',
    );
    expect(
      imageMimeTypeForClipboard(
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
        path: 'photo.png',
      ),
      'image/jpeg',
    );
    expect(
      imageMimeTypeForClipboard(Uint8List.fromList('GIF89a'.codeUnits)),
      'image/gif',
    );
    expect(
      imageMimeTypeForClipboard(Uint8List.fromList('RIFF....WEBP'.codeUnits)),
      'image/webp',
    );
    expect(
      imageMimeTypeForClipboard(Uint8List.fromList([0x42, 0x4D, 0x00])),
      'image/bmp',
    );
    expect(
      imageMimeTypeForClipboard(
        Uint8List.fromList('not-an-image'.codeUnits),
        path: '/tmp/note.txt',
      ),
      isNull,
    );
    expect(
      imageMimeTypeForClipboard(
        Uint8List.fromList([0x01, 0x02]),
        path: '/tmp/photo.JPEG',
      ),
      'image/jpeg',
    );
  });

  test(
    'writeImage sends the bytes and mime type on mithka/clipboard',
    () async {
      const channel = MethodChannel('mithka/clipboard');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Map<Object?, Object?>? arguments;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'writeImage');
        arguments = call.arguments as Map<Object?, Object?>;
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final bytes = Uint8List.fromList(png);
      final result = await writeClipboardImageOnPlatform(bytes, 'image/png');

      expect(result, ClipboardImageCopyResult.copied);
      expect(arguments?['mimeType'], 'image/png');
      expect(arguments?['data'], bytes);
    },
  );

  test('a missing clipboard plugin is reported instead of throwing', () async {
    final result = await writeClipboardImageOnPlatform(
      Uint8List.fromList(png),
      'image/png',
    );
    expect(result, ClipboardImageCopyResult.unsupported);
  });

  test(
    'copyImageFileToClipboard reads the file and skips non-images',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'mithka-copy-image-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final image = File('${directory.path}/photo.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
            'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        );
      final note = File('${directory.path}/note.txt')
        ..writeAsStringSync('path');
      final previous = clipboardImageBytesWriter;
      final writes = <(Uint8List, String)>[];
      clipboardImageBytesWriter = (bytes, mimeType) async {
        writes.add((bytes, mimeType));
        return ClipboardImageCopyResult.copied;
      };
      addTearDown(() => clipboardImageBytesWriter = previous);

      expect(
        await copyImageFileToClipboard(null),
        ClipboardImageCopyResult.missing,
      );
      expect(
        await copyImageFileToClipboard('${directory.path}/missing.png'),
        ClipboardImageCopyResult.missing,
      );
      expect(
        await copyImageFileToClipboard(note.path),
        ClipboardImageCopyResult.failed,
      );
      expect(writes, isEmpty);

      expect(
        await copyImageFileToClipboard(image.path),
        ClipboardImageCopyResult.copied,
      );
      expect(writes, hasLength(1));
      expect(writes.single.$2, 'image/png');
      expect(writes.single.$1, image.readAsBytesSync());
    },
  );
}
