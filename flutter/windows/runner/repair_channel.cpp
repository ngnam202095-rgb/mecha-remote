#include "repair_channel.h"

#include <commctrl.h>
#include <endpointvolume.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <memory>
#include <string>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

using Time = std::chrono::steady_clock;

template <typename T>
const T* Field(const EncodableMap& map, const char* name) {
  const auto it = map.find(EncodableValue(name));
  return it == map.end() ? nullptr : std::get_if<T>(&it->second);
}

bool IsLocalConsole() {
  OSVERSIONINFOEXW version{};
  version.dwOSVersionInfoSize = sizeof(version);
  version.dwBuildNumber = 22000;
  if (!VerifyVersionInfoW(&version, VER_BUILDNUMBER,
                          VerSetConditionMask(0, VER_BUILDNUMBER, VER_GREATER_EQUAL))) {
    return false;
  }
  DWORD current_session = 0;
  if (!ProcessIdToSessionId(GetCurrentProcessId(), &current_session) ||
      current_session != WTSGetActiveConsoleSessionId() ||
      GetSystemMetrics(SM_REMOTESESSION)) {
    return false;
  }
  HDESK desktop = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
  if (!desktop) {
    return false;
  }
  WCHAR name[64] = {};
  const bool is_default =
      GetUserObjectInformationW(desktop, UOI_NAME, name, sizeof(name), nullptr) &&
      std::wstring(name) == L"Default";
  CloseDesktop(desktop);
  return is_default;
}

bool Foreground(HWND owner) {
  return owner && GetAncestor(GetForegroundWindow(), GA_ROOT) == owner;
}

bool HardwareInput() {
  INPUT_MESSAGE_SOURCE source{};
  return GetCurrentInputMessageSource(&source) && source.originId == IMO_HARDWARE;
}

struct ConsentState {
  HWND dialog = nullptr;
  bool hardware = false;
};

LRESULT CALLBACK ConsentButton(HWND button, UINT message, WPARAM wparam,
                               LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
  auto& state = *reinterpret_cast<ConsentState*>(data);
  if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(button, ConsentButton, id);
  }
  if (message != WM_LBUTTONUP && message != WM_KEYUP && message != WM_KEYDOWN) {
    return DefSubclassProc(button, message, wparam, lparam);
  }
  state.hardware = HardwareInput();
  const auto result = DefSubclassProc(button, message, wparam, lparam);
  state.hardware = false;
  return result;
}

HRESULT CALLBACK ConsentEvents(HWND dialog, UINT event, WPARAM value, LPARAM,
                               LONG_PTR data) {
  auto& state = *reinterpret_cast<ConsentState*>(data);
  if (event == TDN_CREATED) {
    state.dialog = dialog;
    HWND button = GetDlgItem(dialog, IDYES);
    if (button) {
      SetWindowSubclass(button, ConsentButton, 1, reinterpret_cast<DWORD_PTR>(&state));
    }
  } else if (event == TDN_DESTROYED) {
    state.dialog = nullptr;
  } else if (event == TDN_TIMER && value >= 35000) {
    SendMessageW(dialog, TDM_CLICK_BUTTON, IDNO, 0);
  } else if (event == TDN_BUTTON_CLICKED && value == IDYES &&
             (!IsLocalConsole() || (!state.hardware && !HardwareInput()))) {
    return S_FALSE;
  }
  return S_OK;
}

bool Confirm(HWND owner, const std::wstring& text, ConsentState& state) {
  if (!IsLocalConsole() || !Foreground(owner)) {
    return false;
  }
  const TASKDIALOG_BUTTON buttons[] = {
      {IDYES, L"Cho ph\u00e9p l\u1ea7n n\u00e0y"},
      {IDNO, L"T\u1eeb ch\u1ed1i v\u00e0 d\u1eebng"},
  };
  TASKDIALOGCONFIG options{};
  options.cbSize = sizeof(options);
  options.hwndParent = owner;
  options.dwFlags = TDF_ALLOW_DIALOG_CANCELLATION | TDF_CALLBACK_TIMER;
  options.pszWindowTitle = L"Mecha Remote";
  options.pszMainInstruction = L"Cho ph\u00e9p thao t\u00e1c t\u1ea1i m\u00e1y?";
  options.pszContent = text.c_str();
  options.cButtons = ARRAYSIZE(buttons);
  options.pButtons = buttons;
  options.nDefaultButton = IDNO;
  options.pfCallback = ConsentEvents;
  options.lpCallbackData = reinterpret_cast<LONG_PTR>(&state);
  int button = IDNO;
  return SUCCEEDED(TaskDialogIndirect(&options, &button, nullptr, nullptr)) &&
         button == IDYES;
}

struct Snapshot {
  std::wstring device;
  bool muted = false;
  int percent = 0;
};

bool LoadAudio(ComPtr<IAudioEndpointVolume>& audio, Snapshot& snapshot) {
  ComPtr<IMMDeviceEnumerator> devices;
  ComPtr<IMMDevice> device;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&devices))) ||
      FAILED(devices->GetDefaultAudioEndpoint(eRender, eConsole, &device)) ||
      FAILED(device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL,
                              nullptr, reinterpret_cast<void**>(audio.GetAddressOf())))) {
    return false;
  }
  WCHAR* id = nullptr;
  const HRESULT id_status = device->GetId(&id);
  if (FAILED(id_status) || !id) {
    CoTaskMemFree(id);
    return false;
  }
  snapshot.device.assign(id);
  CoTaskMemFree(id);
  BOOL mute = FALSE;
  float scalar = 0;
  if (FAILED(audio->GetMute(&mute)) ||
      FAILED(audio->GetMasterVolumeLevelScalar(&scalar)) ||
      !std::isfinite(scalar)) {
    return false;
  }
  snapshot.percent = std::clamp(static_cast<int>(std::lround(scalar * 100)), 0, 100);
  snapshot.muted = mute != FALSE;
  return true;
}

std::wstring Describe(const std::string& code, const EncodableMap& args) {
  if (code == "audio.read" && args.empty()) {
    return L"\u0110\u1ecdc tr\u1ea1ng th\u00e1i t\u1eaft ti\u1ebfng v\u00e0 \u00e2m l\u01b0\u1ee3ng loa. "
           L"G\u1eedi hai ch\u1ec9 s\u1ed1 n\u00e0y cho m\u00e1y ch\u1ee7 th\u1eed.";
  }
  if (code == "storage.read_system" && args.empty()) {
    return L"Ki\u1ec3m tra v\u00e0 g\u1eedi ph\u1ea7n tr\u0103m dung l\u01b0\u1ee3ng tr\u1ed1ng. Kh\u00f4ng m\u1edf t\u1ec7p.";
  }
  const auto* synthetic = Field<bool>(args, "synthetic");
  if (code == "events.read_summary" && args.size() == 1 && synthetic && *synthetic) {
    return L"\u0110\u1ecdc th\u1ed1ng k\u00ea m\u00e1y in m\u1eabu. Kh\u00f4ng m\u1edf nh\u1eadt k\u00fd th\u1eadt.";
  }
  if (code == "screen.capture_window_mock" && args.empty()) {
    return L"T\u1ea1o b\u1ea3n xem tr\u01b0\u1edbc m\u1eabu \u0111\u00e3 che. Kh\u00f4ng ch\u1ee5p m\u00e0n h\u00ecnh.";
  }
  const auto* preview = Field<std::string>(args, "preview_hash");
  if (code == "screen.share_preview_mock" && args.size() == 1 && preview && preview->size() == 64) {
    return L"G\u1eedi m\u00e3 ki\u1ec3m tra b\u1ea3n xem tr\u01b0\u1edbc m\u1eabu \u0111\u00e3 che. Kh\u00f4ng g\u1eedi \u1ea3nh.";
  }
  if (args.size() != 5 || !Field<std::string>(args, "target_ref") ||
      !Field<std::string>(args, "state_rev")) {
    return {};
  }
  const auto* previous = Field<int>(args, "old_percent");
  const auto* mute = Field<bool>(args, "old_mute");
  if (!previous || !mute || *previous < 0 || *previous > 100) {
    return {};
  }
  if (code == "audio.set_volume") {
    const auto* percent = Field<int>(args, "percent");
    if (percent && *percent >= 5 && *percent <= 50 && *percent != *previous) {
      return L"\u0110\u1eb7t \u00e2m l\u01b0\u1ee3ng loa t\u1eeb " + std::to_wstring(*previous) +
          L"% th\u00e0nh " + std::to_wstring(*percent) +
          L"%. C\u00f3 th\u1ec3 kh\u00f4i ph\u1ee5c th\u1ee7 c\u00f4ng trong C\u00e0i \u0111\u1eb7t.";
    }
  }
  if (code == "audio.set_mute") {
    const auto* target_mute = Field<bool>(args, "muted");
    if (target_mute && !*target_mute && *mute && *previous <= 50) {
      return L"B\u1eadt ti\u1ebfng loa \u0111ang d\u00f9ng \u1edf m\u1ee9c " + std::to_wstring(*previous) +
          L"%. C\u00f3 th\u1ec3 t\u1eaft ti\u1ebfng l\u1ea1i th\u1ee7 c\u00f4ng.";
    }
  }
  return {};
}

class RepairChannel {
 public:
  explicit RepairChannel(HWND owner) : owner_(owner) {}

  void Handle(const flutter::MethodCall<>& call, std::unique_ptr<flutter::MethodResult<>> result) {
    if (call.method_name() == "eligible") {
      const bool has_focus = Foreground(owner_) || Foreground(consent_.dialog);
      result->Success(EncodableValue(
          IsLocalConsole() && IsWindowVisible(owner_) && !IsIconic(owner_) && has_focus));
      return;
    }
    if (call.method_name() == "cancel") {
      grant_.clear();
      if (consent_.dialog) {
        SendMessageW(consent_.dialog, TDM_CLICK_BUTTON, IDNO, 0);
      }
      result->Success();
      return;
    }
    const auto* fields = call.arguments() ? std::get_if<EncodableMap>(call.arguments()) : nullptr;
    const auto* code = fields ? Field<std::string>(*fields, "code") : nullptr;
    const auto* args = fields ? Field<EncodableMap>(*fields, "args") : nullptr;
    const auto* hash = fields ? Field<std::string>(*fields, "hash") : nullptr;
    if (!code || !args || !hash || hash->size() != 64 || Describe(*code, *args).empty()) {
      result->Error("blocked");
      return;
    }
    if (call.method_name() == "approve") {
      if (consent_.dialog) {
        result->Error("blocked");
        return;
      }
      grant_.clear();
      const bool accepted = Confirm(owner_, Describe(*code, *args), consent_);
      if (accepted) {
        grant_ = *hash;
        code_ = *code;
        args_ = *args;
        deadline_ = Time::now() + std::chrono::seconds(12);
      }
      result->Success(EncodableValue(accepted));
      return;
    }
    if (call.method_name() != "execute") {
      result->NotImplemented();
      return;
    }
    const bool allowed = grant_ == *hash && code_ == *code && args_ == *args &&
        Time::now() < deadline_ && IsLocalConsole() && Foreground(owner_);
    grant_.clear();
    if (!allowed) {
      result->Error("blocked");
      return;
    }
    if (*code == "events.read_summary" || *code == "screen.capture_window_mock" ||
        *code == "screen.share_preview_mock") {
      result->Success(EncodableValue(EncodableMap{}));
      return;
    }
    if (*code == "storage.read_system") {
      WCHAR system_path[MAX_PATH] = {}, volume[MAX_PATH] = {};
      ULARGE_INTEGER available{}, total{}, free{};
      const UINT system_length = GetWindowsDirectoryW(system_path, MAX_PATH);
      if (!system_length || system_length >= MAX_PATH ||
          !GetVolumePathNameW(system_path, volume, MAX_PATH) ||
          !GetDiskFreeSpaceExW(volume, &available, &total, &free) || !total.QuadPart) {
        result->Error("unknown");
        return;
      }
      const auto percent = static_cast<int>(
          100.0 * static_cast<double>(free.QuadPart) / static_cast<double>(total.QuadPart));
      result->Success(EncodableValue(EncodableMap{
        {EncodableValue("free_percent"), EncodableValue(std::clamp(percent, 0, 100))},
      }));
      return;
    }
    ComPtr<IAudioEndpointVolume> audio;
    Snapshot snapshot;
    if (!LoadAudio(audio, snapshot)) {
      result->Error("unknown");
      return;
    }
    UpdateSnapshot(snapshot);
    const bool writing = *code != "audio.read";
    if (writing) {
      if (*Field<std::string>(*args, "target_ref") != Target() ||
          *Field<std::string>(*args, "state_rev") != Revision() ||
          *Field<int>(*args, "old_percent") != snapshot.percent ||
          *Field<bool>(*args, "old_mute") != snapshot.muted || !IsLocalConsole()) {
        result->Error("blocked");
        return;
      }
      const HRESULT outcome = *code == "audio.set_volume"
          ? audio->SetMasterVolumeLevelScalar(*Field<int>(*args, "percent") / 100.0f, nullptr)
          : audio->SetMute(FALSE, nullptr);
      ComPtr<IAudioEndpointVolume> reread;
      Snapshot after;
      if (FAILED(outcome) || !LoadAudio(reread, after) || after.device != snapshot.device) {
        result->Error("unknown");
        return;
      }
      UpdateSnapshot(after);
    }
    EncodableMap response = {
      {EncodableValue("target_ref"), EncodableValue(Target())},
      {EncodableValue("state_rev"), EncodableValue(Revision())},
      {EncodableValue("muted"), EncodableValue(last_.muted)},
      {EncodableValue("percent"), EncodableValue(last_.percent)},
    };
    if (writing) {
      response[EncodableValue("changed")] = EncodableValue(
          last_.muted != snapshot.muted || last_.percent != snapshot.percent);
    }
    result->Success(EncodableValue(response));
  }

 private:
  void UpdateSnapshot(const Snapshot& snapshot) {
    if (snapshot.device != last_.device) {
      ++target_;
    }
    if (snapshot.device != last_.device || snapshot.muted != last_.muted ||
        snapshot.percent != last_.percent) {
      ++revision_;
    }
    last_ = snapshot;
  }

  std::string Target() const { return "speaker-" + std::to_string(target_); }
  std::string Revision() const { return "rev-" + std::to_string(revision_); }

  HWND owner_;
  std::string grant_, code_;
  EncodableMap args_;
  ConsentState consent_;
  Time::time_point deadline_{};
  Snapshot last_;
  unsigned target_ = 0, revision_ = 0;
};
}  // namespace

void RegisterRepairChannel(flutter::BinaryMessenger* messenger, HWND owner) {
  flutter::MethodChannel<> channel(messenger, "mecha/repair",
                                   &flutter::StandardMethodCodec::GetInstance());
  auto state = std::make_shared<RepairChannel>(owner);
  channel.SetMethodCallHandler(
      [state](const flutter::MethodCall<>& call, std::unique_ptr<flutter::MethodResult<>> result) {
        state->Handle(call, std::move(result));
      });
}
