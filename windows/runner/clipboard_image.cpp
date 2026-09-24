#include "clipboard_image.h"

#include <flutter/standard_method_codec.h>

#include <wincodec.h>
#include <wrl/client.h>

#include <cstdint>
#include <cstring>
#include <vector>

namespace {

using Microsoft::WRL::ComPtr;

bool OpenClipboardWithRetry(HWND owner) {
  for (int attempt = 0; attempt < 8; ++attempt) {
    if (OpenClipboard(owner)) {
      return true;
    }
    Sleep(10);
  }
  return false;
}

bool DecodeToBgr(const uint8_t* data,
                 size_t size,
                 UINT* width,
                 UINT* height,
                 std::vector<uint8_t>* pixels,
                 UINT* stride) {
  ComPtr<IWICImagingFactory> factory;
  HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
  if (FAILED(hr)) {
    return false;
  }

  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, size);
  if (memory == nullptr) {
    return false;
  }
  void* locked = GlobalLock(memory);
  if (locked == nullptr) {
    GlobalFree(memory);
    return false;
  }
  memcpy(locked, data, size);
  GlobalUnlock(memory);

  ComPtr<IStream> stream;
  hr = CreateStreamOnHGlobal(memory, TRUE, &stream);
  if (FAILED(hr)) {
    GlobalFree(memory);
    return false;
  }

  ComPtr<IWICBitmapDecoder> decoder;
  hr = factory->CreateDecoderFromStream(stream.Get(), nullptr,
                                        WICDecodeMetadataCacheOnLoad, &decoder);
  if (FAILED(hr)) {
    return false;
  }
  ComPtr<IWICBitmapFrameDecode> frame;
  hr = decoder->GetFrame(0, &frame);
  if (FAILED(hr)) {
    return false;
  }
  hr = frame->GetSize(width, height);
  if (FAILED(hr) || *width == 0 || *height == 0) {
    return false;
  }

  ComPtr<IWICFormatConverter> converter;
  hr = factory->CreateFormatConverter(&converter);
  if (FAILED(hr)) {
    return false;
  }
  hr = converter->Initialize(frame.Get(), GUID_WICPixelFormat24bppBGR,
                             WICBitmapDitherTypeNone, nullptr, 0.0,
                             WICBitmapPaletteTypeCustom);
  if (FAILED(hr)) {
    return false;
  }

  // CF_DIB rows are DWORD-aligned and stored bottom-up.
  *stride = ((*width * 3u) + 3u) & ~3u;
  pixels->assign(static_cast<size_t>(*stride) * *height, 0);
  std::vector<uint8_t> row(*stride);
  for (UINT y = 0; y < *height; ++y) {
    const WICRect rect = {0, static_cast<INT>(y), static_cast<INT>(*width), 1};
    hr = converter->CopyPixels(&rect, *stride, *stride, row.data());
    if (FAILED(hr)) {
      return false;
    }
    const size_t destination =
        static_cast<size_t>(*height - 1 - y) * static_cast<size_t>(*stride);
    memcpy(pixels->data() + destination, row.data(), *stride);
  }
  return true;
}

bool SetDib(const std::vector<uint8_t>& pixels,
            UINT width,
            UINT height,
            UINT stride) {
  const SIZE_T total = sizeof(BITMAPINFOHEADER) + pixels.size();
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, total);
  if (memory == nullptr) {
    return false;
  }
  auto* header = static_cast<BITMAPINFOHEADER*>(GlobalLock(memory));
  if (header == nullptr) {
    GlobalFree(memory);
    return false;
  }
  ZeroMemory(header, sizeof(BITMAPINFOHEADER));
  header->biSize = sizeof(BITMAPINFOHEADER);
  header->biWidth = static_cast<LONG>(width);
  header->biHeight = static_cast<LONG>(height);
  header->biPlanes = 1;
  header->biBitCount = 24;
  header->biCompression = BI_RGB;
  header->biSizeImage = static_cast<DWORD>(pixels.size());
  memcpy(reinterpret_cast<uint8_t*>(header) + sizeof(BITMAPINFOHEADER),
         pixels.data(), pixels.size());
  GlobalUnlock(memory);
  if (SetClipboardData(CF_DIB, memory) == nullptr) {
    GlobalFree(memory);
    return false;
  }
  (void)stride;
  return true;
}

bool SetPng(const uint8_t* data, size_t size) {
  if (size < 8 || data[0] != 0x89 || data[1] != 0x50 || data[2] != 0x4E ||
      data[3] != 0x47) {
    return true;
  }
  const UINT format = RegisterClipboardFormatW(L"PNG");
  if (format == 0) {
    return false;
  }
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, size);
  if (memory == nullptr) {
    return false;
  }
  void* locked = GlobalLock(memory);
  if (locked == nullptr) {
    GlobalFree(memory);
    return false;
  }
  memcpy(locked, data, size);
  GlobalUnlock(memory);
  if (SetClipboardData(format, memory) == nullptr) {
    GlobalFree(memory);
    return false;
  }
  return true;
}

bool WriteImage(HWND owner, const uint8_t* data, size_t size) {
  UINT width = 0;
  UINT height = 0;
  UINT stride = 0;
  std::vector<uint8_t> pixels;
  if (!DecodeToBgr(data, size, &width, &height, &pixels, &stride)) {
    return false;
  }
  if (!OpenClipboardWithRetry(owner)) {
    return false;
  }
  if (!EmptyClipboard()) {
    CloseClipboard();
    return false;
  }
  const bool dib = SetDib(pixels, width, height, stride);
  const bool png = dib && SetPng(data, size);
  CloseClipboard();
  return dib && png;
}

const std::vector<uint8_t>* ImageBytes(
    const flutter::EncodableMap& args) {
  const auto found = args.find(flutter::EncodableValue("data"));
  if (found == args.end()) {
    return nullptr;
  }
  return std::get_if<std::vector<uint8_t>>(&found->second);
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateClipboardImageChannel(flutter::BinaryMessenger* messenger, HWND owner) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "mithka/clipboard",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [owner](const flutter::MethodCall<flutter::EncodableValue>& call,
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                  result) {
        if (call.method_name() != "writeImage") {
          result->NotImplemented();
          return;
        }
        const auto* arguments = call.arguments();
        const auto* args = arguments == nullptr
                               ? nullptr
                               : std::get_if<flutter::EncodableMap>(arguments);
        const auto* bytes = args == nullptr ? nullptr : ImageBytes(*args);
        if (bytes == nullptr || bytes->empty() ||
            !WriteImage(owner, bytes->data(), bytes->size())) {
          result->Error("clipboard_unavailable", "Could not copy the image");
          return;
        }
        result->Success(flutter::EncodableValue(true));
      });
  return channel;
}
