#ifndef RUNNER_REPAIR_CHANNEL_H_
#define RUNNER_REPAIR_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

void RegisterRepairChannel(flutter::BinaryMessenger* messenger, HWND owner);

#endif  // RUNNER_REPAIR_CHANNEL_H_
