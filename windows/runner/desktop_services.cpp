#include "desktop_services.h"

#include <flutter/standard_method_codec.h>
#include <dpapi.h>
#include <shlobj.h>
#include <shellapi.h>
#include <wincrypt.h>

#include <fstream>
#include <iterator>
#include <string>
#include <system_error>
#include <utility>
#include <variant>
#include <vector>

#include "utils.h"

namespace {
using Value = flutter::EncodableValue;

std::wstring Wide(const std::string& value) {
  const int length = static_cast<int>(value.size());
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                       value.data(), length, nullptr, 0);
  if (count <= 0) return {};
  std::wstring result(count, L'\0');
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), length,
                          result.data(), count)) return {};
  return result;
}
}  // namespace

DesktopServices::DesktopServices(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window) {
  PWSTR root = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE,
                                    nullptr, &root))) {
    support_ = std::filesystem::path(root) / L"Seiue";
    CoTaskMemFree(root);
  }
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "com.littleswift.seiue/native",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    Handle(call, std::move(result));
  });
}

void DesktopServices::Handle(
    const flutter::MethodCall<Value>& call,
    std::unique_ptr<flutter::MethodResult<Value>> result) {
  const auto& method = call.method_name();
  if (method == "openUrl") {
    const auto* url = call.arguments()
        ? std::get_if<std::string>(call.arguments()) : nullptr;
    // No command interpreter; only http(s) URLs may reach ShellExecute.
    if (!url || url->find('\0') != std::string::npos ||
        (url->rfind("https://", 0) != 0 && url->rfind("http://", 0) != 0)) {
      result->Error("url", "Invalid web URL");
      return;
    }
    const auto wide = Wide(*url);
    const auto status = reinterpret_cast<INT_PTR>(ShellExecuteW(
        window_, L"open", wide.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
    if (status <= 32) result->Error("url", "Cannot open the default browser");
    else result->Success();
    return;
  }
  if (method == "activateWindow") {
    ShowWindow(window_, IsIconic(window_) ? SW_RESTORE : SW_SHOW);
    SetForegroundWindow(window_);
    result->Success();
    return;
  }
  if (method == "openNotificationSettings") {
    const auto status = reinterpret_cast<INT_PTR>(ShellExecuteW(
        window_, L"open", L"ms-settings:notifications", nullptr, nullptr, SW_SHOWNORMAL));
    if (status <= 32) result->Error("settings", "Cannot open notification settings");
    else result->Success();
    return;
  }
  if (support_.empty()) {
    result->Error("storage", "Local application data is unavailable");
    return;
  }
  std::error_code error;
  std::filesystem::create_directories(support_, error);
  if (error) {
    result->Error("storage", "Cannot create application data directory");
    return;
  }
  if (method == "applicationSupportPath") {
    result->Success(Value(Utf8FromUtf16(support_.c_str())));
    return;
  }
  const auto path = support_ / L"session.dpapi";
  const auto pending = support_ / L"session.dpapi.pending";
  if (method == "clearSession") {
    std::filesystem::remove(path, error);
    if (!error) std::filesystem::remove(pending, error);
    if (error) result->Error("storage", "Cannot clear saved session");
    else result->Success();
    return;
  }
  if (method == "saveSession") {
    const auto* json = call.arguments()
        ? std::get_if<std::string>(call.arguments()) : nullptr;
    if (!json || json->empty() || json->size() > 1024 * 1024) {
      result->Error("storage", "Invalid session");
      return;
    }
    DATA_BLOB input{static_cast<DWORD>(json->size()),
                    reinterpret_cast<BYTE*>(const_cast<char*>(json->data()))};
    DATA_BLOB encrypted{};
    // No CRYPTPROTECT_LOCAL_MACHINE: another Windows user cannot decrypt it.
    if (!CryptProtectData(&input, L"Seiue session", nullptr, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &encrypted)) {
      result->Error("storage", "Cannot encrypt session");
      return;
    }
    std::ofstream stream(pending, std::ios::binary | std::ios::trunc);
    stream.write(reinterpret_cast<const char*>(encrypted.pbData),
                 static_cast<std::streamsize>(encrypted.cbData));
    stream.close();
    LocalFree(encrypted.pbData);
    if (!stream || !MoveFileExW(pending.c_str(), path.c_str(),
                                MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
      std::filesystem::remove(pending, error);
      result->Error("storage", "Cannot save encrypted session");
      return;
    }
    result->Success();
    return;
  }
  if (method == "readSession") {
    const bool exists = std::filesystem::exists(path, error);
    if (error) {
      result->Error("storage", "Cannot read saved session");
      return;
    }
    if (!exists) {
      result->Success();
      return;
    }
    const auto size = std::filesystem::file_size(path, error);
    if (error || size > 2 * 1024 * 1024) {
      result->Error("storage", "Invalid encrypted session file");
      return;
    }
    std::ifstream stream(path, std::ios::binary);
    std::vector<BYTE> bytes((std::istreambuf_iterator<char>(stream)),
                            std::istreambuf_iterator<char>());
    if (stream.bad() || bytes.empty()) {
      result->Error("storage", "Cannot read encrypted session");
      return;
    }
    DATA_BLOB input{static_cast<DWORD>(bytes.size()), bytes.data()};
    DATA_BLOB decrypted{};
    if (!CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr,
                            CRYPTPROTECT_UI_FORBIDDEN, &decrypted)) {
      result->Error("storage", "Saved session could not be decrypted; sign in again");
      return;
    }
    std::string json(reinterpret_cast<const char*>(decrypted.pbData),
                     decrypted.cbData);
    SecureZeroMemory(decrypted.pbData, decrypted.cbData);
    LocalFree(decrypted.pbData);
    result->Success(Value(json));
    SecureZeroMemory(json.data(), json.size());
    return;
  }
  result->NotImplemented();
}
