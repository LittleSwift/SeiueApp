#ifndef RUNNER_DESKTOP_SERVICES_H_
#define RUNNER_DESKTOP_SERVICES_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <filesystem>
#include <memory>

// Shared Dart channel; secrets are protected for the current Windows user.
class DesktopServices {
 public:
  DesktopServices(flutter::BinaryMessenger* messenger, HWND window);

 private:
  void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  HWND window_;
  std::filesystem::path support_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_DESKTOP_SERVICES_H_
