#include "clipboard_image_channel.h"

#include "clipboard_image.h"

#include <gtk/gtk.h>

namespace {

void RespondError(FlMethodCall* method_call, const char* message) {
  fl_method_call_respond_error(method_call, "clipboard_unavailable", message,
                               nullptr, nullptr);
}

void HandleWriteImage(FlMethodCall* method_call) {
  FlValue* args = fl_method_call_get_args(method_call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    RespondError(method_call, "Image bytes are required");
    return;
  }
  FlValue* data = fl_value_lookup_string(args, "data");
  if (data == nullptr || fl_value_get_type(data) != FL_VALUE_TYPE_UINT8_LIST) {
    RespondError(method_call, "Image bytes are required");
    return;
  }
  const uint8_t* bytes = fl_value_get_uint8_list(data);
  const size_t length = fl_value_get_length(data);
  std::string error;
  if (!mithka_clipboard_set_image(bytes, length, &error)) {
    RespondError(method_call,
                 error.empty() ? "Could not copy the image" : error.c_str());
    return;
  }
  fl_method_call_respond_success(method_call, fl_value_new_bool(TRUE), nullptr);
}

void HandleMethodCall(FlMethodChannel* channel,
                      FlMethodCall* method_call,
                      gpointer user_data) {
  (void)channel;
  (void)user_data;
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "writeImage") == 0) {
    HandleWriteImage(method_call);
    return;
  }
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

}  // namespace

void mithka_clipboard_image_channel_register(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry,
                                                  "MithkaClipboardImage");
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "mithka/clipboard",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, HandleMethodCall, nullptr,
                                            nullptr);
}
