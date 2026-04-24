/*
 * Copyright (c) 2026, Qualcomm Innovation Center, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause-Clear
 */

#include "AutoGen.h"
#include "BootLinux.h"
#include "LinuxLoaderLib.h"
#include <FastbootLib/FastbootMain.h>
#include <Library/DeviceInfo.h>
#include <Library/HypervisorMvCalls.h>
#include <Library/PartitionTableUpdate.h>
#include <Library/StackCanary.h>
#include "Library/ThreadStack.h"

#define DEFAULT_STACK_CHK_GUARD 0xc0c0c0c0

#ifndef PROBE_REBOOT_STAGE_ID
#define PROBE_REBOOT_STAGE_ID 0
#endif

BccParams_t BccParamsRecvdFromAVB = {{0}};
STATIC BOOLEAN BootIntoFastboot = FALSE;
STATIC BOOLEAN BootIntoRecovery = FALSE;
STATIC UINT32 BootDeviceType = EFI_MAX_FLASH_TYPE;

STATIC
VOID
RenderStageBanner (
  IN CONST CHAR8  *StageLabel,
  IN UINT32       BgColor
  )
{
  MENU_MSG_INFO MenuMsg;
  CHAR8         EmptyMsg[] = "";
  CHAR8         Title[MAX_MSG_SIZE];
  CHAR8         Subtitle[MAX_MSG_SIZE];
  UINT32        FgColor;
  UINT32        Locations[] = {80, 120, 160, 200, 240, 280};
  UINTN         Index;

  if (!IsEnableDisplayMenuFlagSupported ()) {
    return;
  }

  FgColor = (BgColor == BGR_BLUE || BgColor == BGR_RED) ? BGR_WHITE : BGR_BLACK;
  DrawMenuInit ();

  for (Index = 0; Index < ARRAY_SIZE (Locations); ++Index) {
    SetMenuMsgInfo (&MenuMsg, EmptyMsg, COMMON_FACTOR, FgColor, BgColor,
                    OPTION_ITEM, Locations[Index], NOACTION);
    DrawMenu (&MenuMsg, NULL);
  }

  AsciiStrnCpyS (Title, sizeof (Title), "SM8650 DUALSTAGE",
                 AsciiStrLen ("SM8650 DUALSTAGE"));
  SetMenuMsgInfo (&MenuMsg, Title, COMMON_FACTOR, FgColor, BgColor,
                  ALIGN_LEFT, 136, NOACTION);
  DrawMenu (&MenuMsg, NULL);

  AsciiStrnCpyS (Subtitle, sizeof (Subtitle), (CHAR8 *)StageLabel,
                 AsciiStrLen (StageLabel));
  SetMenuMsgInfo (&MenuMsg, Subtitle, COMMON_FACTOR, FgColor, BgColor,
                  ALIGN_LEFT, 184, NOACTION);
  DrawMenu (&MenuMsg, NULL);
}

STATIC
VOID
ProbeRebootIf (
  IN UINT32       ProbeId,
  IN CONST CHAR8  *ProbeName
  )
{
  if (PROBE_REBOOT_STAGE_ID != ProbeId) {
    return;
  }

  DEBUG ((EFI_D_ERROR, "UEFI reboot probe %u hit at %a\n", ProbeId, ProbeName));
  RebootDevice (NORMAL_MODE);
  CpuDeadLoop ();
}

BOOLEAN
IsABRetryCountUpdateRequired (VOID)
{
  BOOLEAN BatteryStatus;

  TargetPauseForBatteryCharge (&BatteryStatus);

  if ((BatteryStatus && IsChargingScreenEnable ()) ||
      BootIntoFastboot ||
      BootIntoRecovery) {
    return FALSE;
  }
  return TRUE;
}

UINT32
GetBootDeviceType (VOID)
{
  UINTN      DataSize;
  EFI_STATUS Status;

  DataSize = sizeof (BootDeviceType);
  Status = EFI_SUCCESS;

  if (BootDeviceType == EFI_MAX_FLASH_TYPE) {
    Status = gRT->GetVariable (
                    L"SharedImemBootCfgVal",
                    &gQcomTokenSpaceGuid,
                    NULL,
                    &DataSize,
                    &BootDeviceType
                    );
    if (Status != EFI_SUCCESS) {
      DEBUG ((EFI_D_ERROR, "Failed to get boot device type, %r\n", Status));
    }
  }

  return BootDeviceType;
}

STATIC
EFI_STATUS
BootAndroidFromCurrentSlot (VOID)
{
  EFI_STATUS Status;
  BOOLEAN    MultiSlotBoot;
  BootInfo   Info;

  MultiSlotBoot = FALSE;
  ZeroMem (&Info, sizeof (Info));
  BootIntoFastboot = FALSE;
  BootIntoRecovery = FALSE;

  Status = DeviceInfoInit ();
  if (EFI_ERROR (Status)) {
    DEBUG ((EFI_D_ERROR, "DualStageLoader: DeviceInfoInit failed: %r\n",
            Status));
    return Status;
  }

  Status = EnumeratePartitions ();
  if (EFI_ERROR (Status)) {
    DEBUG ((EFI_D_ERROR,
            "DualStageLoader: EnumeratePartitions failed: %r\n",
            Status));
    return Status;
  }

  UpdatePartitionEntries ();
  MultiSlotBoot = PartitionHasMultiSlot ((CONST CHAR16 *)L"boot");
  if (MultiSlotBoot) {
    FindPtnActiveSlot ();
  }

  Status = BoardInit ();
  if (EFI_ERROR (Status)) {
    DEBUG ((EFI_D_ERROR, "DualStageLoader: BoardInit failed: %r\n", Status));
    return Status;
  }

  if (!GetVmData ()) {
    DEBUG ((EFI_D_ERROR, "DualStageLoader: VM Hyp calls not present\n"));
  }
  RenderStageBanner ("BOARD INIT", BGR_CYAN);
  ProbeRebootIf (12, "DualStageLoaderAfterBoardInit");

  Info.MultiSlotBoot = MultiSlotBoot;
  Info.SilentBootMode = NON_SILENT_MODE;

  RenderStageBanner ("LOAD IMAGE", BGR_YELLOW);
  ProbeRebootIf (13, "DualStageLoaderBeforeLoadImageAndAuth");
  Status = LoadImageAndAuth (&Info, FALSE, FALSE
#ifndef USE_DUMMY_BCC
                             , &BccParamsRecvdFromAVB
#endif
                            );
  if (EFI_ERROR (Status)) {
    DEBUG ((EFI_D_ERROR, "DualStageLoader: LoadImageAndAuth failed: %r\n",
            Status));
    return Status;
  }

  RenderStageBanner ("BOOT LINUX", BGR_GREEN);
  ProbeRebootIf (14, "DualStageLoaderBeforeBootLinux");
  return BootLinux (&Info);
}

EFI_STATUS
EFIAPI
__attribute__ ( (no_sanitize ("safe-stack")))
DualStageLoaderEntry (IN EFI_HANDLE ImageHandle, IN EFI_SYSTEM_TABLE *SystemTable)
{
  EFI_STATUS Status;

  (VOID)ImageHandle;
  (VOID)SystemTable;

  DEBUG ((EFI_D_INFO, "DualStageLoader starting\n"));

  Status = InitThreadUnsafeStack ();
  if (EFI_ERROR (Status)) {
    DEBUG ((EFI_D_ERROR,
            "DualStageLoader: failed to init unsafe stack: %r\n",
            Status));
    return Status;
  }

  StackGuardChkSetup ();
  RenderStageBanner ("ENTRY", BGR_BLUE);
  ProbeRebootIf (11, "DualStageLoaderEntry");
  Status = BootAndroidFromCurrentSlot ();

  __stack_chk_guard = DEFAULT_STACK_CHK_GUARD;
  DeInitThreadUnsafeStack ();
  return Status;
}
