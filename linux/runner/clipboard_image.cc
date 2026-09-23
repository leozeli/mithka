#include "clipboard_image.h"

#include <gtk/gtk.h>

namespace {

void SetError(std::string* error, const char* message) {
  if (error != nullptr) {
    *error = message == nullptr ? "Could not copy the image" : message;
  }
}

}  // namespace

bool mithka_clipboard_set_image(const uint8_t* data,
                                size_t length,
                                std::string* error) {
  if (data == nullptr || length == 0) {
    SetError(error, "Image data is empty");
    return false;
  }

  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr) {
    SetError(error, "Clipboard is unavailable");
    return false;
  }

  g_autoptr(GError) decode_error = nullptr;
  g_autoptr(GdkPixbufLoader) loader = gdk_pixbuf_loader_new();
  if (!gdk_pixbuf_loader_write(loader, data, length, &decode_error) ||
      !gdk_pixbuf_loader_close(loader, &decode_error)) {
    SetError(error, decode_error != nullptr ? decode_error->message
                                            : "Could not decode image");
    return false;
  }

  GdkPixbuf* loaded = gdk_pixbuf_loader_get_pixbuf(loader);
  if (loaded == nullptr) {
    SetError(error, "Could not decode image");
    return false;
  }

  // The loader owns [loaded]. Copy it so the clipboard can keep the pixels
  // after this function drops the loader.
  GdkPixbuf* pixels = gdk_pixbuf_copy(loaded);
  if (pixels == nullptr) {
    SetError(error, "Could not decode image");
    return false;
  }

  // Same clipboard screen_capturer reads, so a copied photo can be pasted
  // back into Mithka and into other apps.
  GtkClipboard* clipboard = gtk_clipboard_get_default(display);
  if (clipboard == nullptr) {
    g_object_unref(pixels);
    SetError(error, "Clipboard is unavailable");
    return false;
  }

  // gtk_clipboard_set_image refs the pixbuf and serves image/png (and the
  // other image targets GdkPixbuf can encode) until the clipboard changes.
  gtk_clipboard_set_image(clipboard, pixels);
  gtk_clipboard_store(clipboard);
  g_object_unref(pixels);
  if (error != nullptr) {
    error->clear();
  }
  return true;
}
