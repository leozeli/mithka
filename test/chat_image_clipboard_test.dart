import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_image_clipboard.dart';
import 'package:mithka/platform/clipboard_image.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ClipboardImageBytesWriter previous;
  late List<(Uint8List, String)> writes;

  setUp(() {
    previous = clipboardImageBytesWriter;
    writes = [];
    clipboardImageBytesWriter = (bytes, mimeType) async {
      writes.add((bytes, mimeType));
      return ClipboardImageCopyResult.copied;
    };
  });

  tearDown(() {
    clipboardImageBytesWriter = previous;
  });

  ChatMessage photo({TdFileRef? image}) => ChatMessage(
    id: 7,
    isOutgoing: false,
    text: '',
    date: 1,
    contentType: 'messagePhoto',
    image: image,
  );

  test(
    'downloads a chat photo that is not local yet, then copies it',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'mithka-chat-photo-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/photo.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
      var downloads = 0;

      final result = await copyChatPhotoToClipboard(
        photo(image: TdFileRef(id: 11)),
        resolvePath: (image) async {
          downloads++;
          expect(image.id, 11);
          return file.path;
        },
      );

      expect(result, ClipboardImageCopyResult.copied);
      expect(downloads, 1);
      expect(writes.single.$2, 'image/jpeg');
      expect(writes.single.$1, file.readAsBytesSync());
    },
  );

  test('a photo that never arrives reports that it is not ready', () async {
    final result = await copyChatPhotoToClipboard(
      photo(image: TdFileRef(id: 12)),
      resolvePath: (_) async => null,
    );

    expect(result, ClipboardImageCopyResult.missing);
    expect(clipboardImageCopyFeedbackKey(result), 'chatCopyImageNotReady');
    expect(writes, isEmpty);
  });

  test('videos and caption text stay off the image clipboard path', () async {
    final result = await copyChatPhotoToClipboard(
      ChatMessage(
        id: 8,
        isOutgoing: false,
        text: 'hello',
        date: 1,
        contentType: 'messageVideo',
        image: TdFileRef(id: 1),
        video: TdFileRef(id: 2),
      ),
      resolvePath: (_) async => throw StateError('should not download'),
    );

    expect(result, ClipboardImageCopyResult.unsupported);
    expect(writes, isEmpty);
  });
}
