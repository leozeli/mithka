import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

enum ClipboardImageCopyResult { copied, missing, failed, unsupported }

typedef ClipboardImageBytesWriter =
    Future<ClipboardImageCopyResult> Function(Uint8List bytes, String mimeType);

/// Linux, macOS, Windows, and iOS can place an image on the system clipboard.
/// Android's clipboard needs a content provider Mithka does not register.
bool clipboardImageCopyIsSupported([TargetPlatform? platform]) {
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.iOS => true,
    TargetPlatform.android || TargetPlatform.fuchsia => false,
  };
}

/// Test hook. Production calls [writeClipboardImageOnPlatform].
@visibleForTesting
ClipboardImageBytesWriter clipboardImageBytesWriter =
    writeClipboardImageOnPlatform;

const _channel = MethodChannel('mithka/clipboard');

Future<ClipboardImageCopyResult> writeClipboardImageOnPlatform(
  Uint8List bytes,
  String mimeType,
) async {
  try {
    final copied = await _channel.invokeMethod<bool>('writeImage', {
      'data': bytes,
      'mimeType': mimeType,
    });
    return copied == true
        ? ClipboardImageCopyResult.copied
        : ClipboardImageCopyResult.failed;
  } on MissingPluginException {
    return ClipboardImageCopyResult.unsupported;
  } on PlatformException {
    return ClipboardImageCopyResult.failed;
  }
}

/// Copies the image file at [path] onto the system clipboard.
///
/// A missing path means the photo is not on disk yet. Callers that can
/// download it should do that before calling, then surface [missing] when the
/// download does not produce a file.
Future<ClipboardImageCopyResult> copyImageFileToClipboard(String? path) async {
  final trimmed = path?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return ClipboardImageCopyResult.missing;
  }
  final file = File(trimmed);
  Uint8List bytes;
  try {
    if (!await file.exists()) return ClipboardImageCopyResult.missing;
    bytes = await file.readAsBytes();
  } on FileSystemException {
    return ClipboardImageCopyResult.failed;
  }
  if (bytes.isEmpty) return ClipboardImageCopyResult.failed;
  final mimeType = imageMimeTypeForClipboard(bytes, path: trimmed);
  if (mimeType == null) return ClipboardImageCopyResult.failed;
  return clipboardImageBytesWriter(bytes, mimeType);
}

/// Recognizes the image types the desktop clipboard writers can decode.
/// Magic bytes win over the file extension so a mislabeled cache file still
/// pastes as the picture it actually is.
String? imageMimeTypeForClipboard(Uint8List bytes, {String? path}) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return 'image/png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 6) {
    final header = String.fromCharCodes(bytes.take(6));
    if (header == 'GIF87a' || header == 'GIF89a') return 'image/gif';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
    return 'image/webp';
  }
  if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
    return 'image/bmp';
  }
  return switch (_extension(path)) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    _ => null,
  };
}

String clipboardImageCopyFeedbackKey(ClipboardImageCopyResult result) {
  return switch (result) {
    ClipboardImageCopyResult.copied => AppStringKeys.topicPostContentCopied,
    ClipboardImageCopyResult.missing => AppStringKeys.chatCopyImageNotReady,
    ClipboardImageCopyResult.failed ||
    ClipboardImageCopyResult.unsupported => AppStringKeys.chatCopyImageFailed,
  };
}

String? _extension(String? path) {
  if (path == null || path.isEmpty) return null;
  final base = path.split(RegExp(r'[/\\]')).last;
  final dot = base.lastIndexOf('.');
  if (dot <= 0 || dot == base.length - 1) return null;
  return base.substring(dot + 1).toLowerCase();
}
