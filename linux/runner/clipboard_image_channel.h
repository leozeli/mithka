#ifndef MITHKA_CLIPBOARD_IMAGE_CHANNEL_H_
#define MITHKA_CLIPBOARD_IMAGE_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

// Registers mithka/clipboard writeImage on this engine. Child preview windows
// use the same registrar callback as the primary window, so both can copy.
void mithka_clipboard_image_channel_register(FlPluginRegistry* registry);

#endif  // MITHKA_CLIPBOARD_IMAGE_CHANNEL_H_
