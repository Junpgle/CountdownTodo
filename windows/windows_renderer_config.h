#ifndef WINDOWS_RENDERER_CONFIG_H_
#define WINDOWS_RENDERER_CONFIG_H_

#include <windows.h>

#include <cwchar>
#include <string>

namespace windows_renderer_config {

enum class Renderer { kSkia, kImpeller };

inline constexpr wchar_t kRegistryPath[] =
    L"Software\\Junpgle\\CountDownTodo";
inline constexpr wchar_t kRegistryValueName[] = L"WindowsRenderer";

inline Renderer ReadRenderer() {
  wchar_t value[16] = {};
  DWORD value_size = static_cast<DWORD>(sizeof(value));
  const LSTATUS status = ::RegGetValueW(
      HKEY_CURRENT_USER, kRegistryPath, kRegistryValueName, RRF_RT_REG_SZ,
      nullptr, value, &value_size);
  if (status == ERROR_SUCCESS && std::wcscmp(value, L"impeller") == 0) {
    return Renderer::kImpeller;
  }
  return Renderer::kSkia;
}

inline bool WriteRenderer(Renderer renderer) {
  HKEY key = nullptr;
  const LSTATUS create_status = ::RegCreateKeyExW(
      HKEY_CURRENT_USER, kRegistryPath, 0, nullptr, 0, KEY_SET_VALUE, nullptr,
      &key, nullptr);
  if (create_status != ERROR_SUCCESS) {
    return false;
  }

  const wchar_t* value =
      renderer == Renderer::kImpeller ? L"impeller" : L"skia";
  const DWORD value_size =
      static_cast<DWORD>((std::wcslen(value) + 1) * sizeof(wchar_t));
  const LSTATUS write_status = ::RegSetValueExW(
      key, kRegistryValueName, 0, REG_SZ,
      reinterpret_cast<const BYTE*>(value), value_size);
  ::RegCloseKey(key);
  return write_status == ERROR_SUCCESS;
}

inline std::string RendererName(Renderer renderer) {
  return renderer == Renderer::kImpeller ? "impeller" : "skia";
}

}  // namespace windows_renderer_config

#endif  // WINDOWS_RENDERER_CONFIG_H_
