#ifndef RUNNER_CLIPBOARD_IMAGE_H_
#define RUNNER_CLIPBOARD_IMAGE_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>

#include <memory>

// Owns the mithka/clipboard channel for one window, including image previews.
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateClipboardImageChannel(flutter::BinaryMessenger* messenger, HWND owner);

#endif  // RUNNER_CLIPBOARD_IMAGE_H_
