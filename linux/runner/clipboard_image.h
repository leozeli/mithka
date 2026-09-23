#ifndef MITHKA_CLIPBOARD_IMAGE_H_
#define MITHKA_CLIPBOARD_IMAGE_H_

#include <stddef.h>
#include <stdint.h>

#include <string>

// Puts image bytes on the GTK clipboard so other apps can paste a picture.
// [data] is a file payload (PNG, JPEG, GIF, or anything GdkPixbuf can decode).
// On failure, [error] receives a short reason when it is non-null.
bool mithka_clipboard_set_image(const uint8_t* data,
                                size_t length,
                                std::string* error);

#endif  // MITHKA_CLIPBOARD_IMAGE_H_
