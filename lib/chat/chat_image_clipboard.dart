import '../platform/clipboard_image.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';

typedef ChatPhotoPathResolver = Future<String?> Function(TdFileRef image);

/// Copies a chat photo to the clipboard, downloading the file when it is not
/// local yet. Non-photos are refused so a video or file save path is unchanged.
Future<ClipboardImageCopyResult> copyChatPhotoToClipboard(
  ChatMessage message, {
  ChatPhotoPathResolver? resolvePath,
}) async {
  if (!message.isPhoto) return ClipboardImageCopyResult.unsupported;
  final image = message.image;
  if (image == null) return ClipboardImageCopyResult.missing;
  final path = await (resolvePath ?? TdFileCenter.shared.pathFor)(image);
  return copyImageFileToClipboard(path);
}
