import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/media/linux_chat_video_playback.dart';

void main() {
  test('Linux chat videos stay in the primary window', () {
    expect(
      chatVideoOpensDetachedWindow(
        desktopWindowsSupported: true,
        platform: TargetPlatform.linux,
      ),
      isFalse,
    );
    expect(
      chatVideoOpensDetachedWindow(
        desktopWindowsSupported: false,
        platform: TargetPlatform.linux,
      ),
      isFalse,
    );
  });

  test('macOS and Windows still open a detached chat video window', () {
    for (final platform in const [
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      expect(
        chatVideoOpensDetachedWindow(
          desktopWindowsSupported: true,
          platform: platform,
        ),
        isTrue,
      );
      expect(
        chatVideoOpensDetachedWindow(
          desktopWindowsSupported: false,
          platform: platform,
        ),
        isFalse,
      );
    }
  });

  test('Linux FVP skips display-server decoders', () {
    expect(
      fvpVideoDecodersFor(TargetPlatform.linux),
      linuxSoftwareVideoDecoders,
    );
    expect(linuxSoftwareVideoDecoders, isNot(contains('VAAPI')));
    expect(linuxSoftwareVideoDecoders, isNot(contains('VDPAU')));
    expect(linuxSoftwareVideoDecoders, isNot(contains('CUDA')));
    expect(linuxSoftwareVideoDecoders, contains('FFmpeg'));
    expect(linuxSoftwareVideoDecoders, contains('dav1d'));
    expect(fvpVideoDecodersFor(TargetPlatform.macOS), isEmpty);
    expect(fvpVideoDecodersFor(TargetPlatform.windows), isEmpty);
    expect(fvpVideoDecodersFor(TargetPlatform.iOS), isEmpty);
  });

  test('chat playback and FVP startup use the Linux policy', () {
    final chat = File('lib/chat/chat_view.dart').readAsStringSync();
    final play = chat.substring(
      chat.indexOf('void _playVideo('),
      chat.indexOf('Future<void> _openDesktopVideoWindow('),
    );
    expect(play, contains('chatVideoOpensDetachedWindow('));
    expect(play, contains('platform: defaultTargetPlatform'));
    expect(play, isNot(contains('if (supportsDesktopVideoWindows)')));

    final main = File('lib/main.dart').readAsStringSync();
    final initializer = main.substring(
      main.indexOf('void _initializeVideoBackend('),
      main.indexOf('Future<void> _initTelemetry()'),
    );
    expect(initializer, contains('fvpVideoDecodersFor(defaultTargetPlatform)'));
    expect(initializer, contains('FVideoFvpPlatform.linux'));
  });
}
