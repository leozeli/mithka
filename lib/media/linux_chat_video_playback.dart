import 'package:flutter/foundation.dart';

/// Software decoders MDK can use without borrowing Flutter's display connection.
///
/// Linux FVP otherwise prefers VAAPI, then CUDA, then VDPAU. The plugin
/// publishes the GTK display (`X11Display` / `wl_display*`) to MDK, and VAAPI
/// uses that connection from a decoder thread while GTK still owns it on the
/// main thread. The display is not safe to share that way, so starting a chat
/// video stops the main loop and the whole window stops taking input. FFmpeg
/// and dav1d decode without that connection. HAP stays in the list because the
/// Linux default places it ahead of FFmpeg for that codec.
const List<String> linuxSoftwareVideoDecoders = ['hap', 'FFmpeg', 'dav1d'];

/// Decoder override passed to FVP. Empty means FVP's own per-platform default.
List<String> fvpVideoDecodersFor(TargetPlatform platform) =>
    platform == TargetPlatform.linux ? linuxSoftwareVideoDecoders : const [];

/// Whether a tapped chat video should open another native window.
///
/// Linux stays in the primary window. A detached player is a second GTK
/// Flutter view, and `multi_window_manager` installs a client-side header bar
/// on Wayland (and on GNOME X11). The video host then resizes that view
/// without clearing client-side decoration shadow extents, so the compositor
/// reports a smaller frame than Flutter asked for. The Linux embedder waits
/// for the missing size on the shared GTK thread — the same race the primary
/// window avoids by never installing a header bar — and every window stops
/// responding. Playback uses the in-window player instead.
bool chatVideoOpensDetachedWindow({
  required bool desktopWindowsSupported,
  required TargetPlatform platform,
}) {
  if (platform == TargetPlatform.linux) return false;
  return desktopWindowsSupported;
}
