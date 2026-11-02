#ifndef _ALPHADATA_ADXDMA_H
#define _ALPHADATA_ADXDMA_H

/*
** <adxdma.h> - ADXDMA API header file (ADXDMA interface)
**
** (C) Copyright 2017 Alpha Data
**
** The integer datatypes used below that are prefixed by "_ADXDMA_", such
** as "_ADXDMA_UINT64" are defined in order to increase the portability of
** this header file but should NOT be used by application code that makes
** use of the ADXDMA API.
**
** Applications should use OS-specific types such as UINT32 (Windows) or
** uint32_t (Linux C99).
*/

#if defined(_WIN32) || defined(_MSC_VER)

/* Windows */

# include <windows.h>
# include <tchar.h>

# if defined(ADXDMA_DLL)
    /* Compiling API library into a DLL */
#   define ADXDMA_EXPORT __declspec(dllexport)
# else
    /* Importing API library from DLL */
#   define ADXDMA_EXPORT __declspec(dllimport)
# endif
# define ADXDMA_CALLING_CONVENTION __cdecl

#elif defined(__linux)

/* Linux */

# include <stdint.h>
# include <wchar.h>

# define ADXDMA_EXPORT
# define ADXDMA_CALLING_CONVENTION

#elif defined(__VXWORKS__) || defined(__vxworks)

# include <vxWorks.h>
# include <semLib.h>

# define ADXDMA_EXPORT
# define ADXDMA_CALLING_CONVENTION

#else

# error Cannot detect target operating system.

#endif

#include <adxdma/platform.h>
#include <adxdma/status.h>
#include <adxdma/types.h>
#include <adxdma/structs.h>
#include <adxdma/version.h>

/*
** Function prototypes
*/
#ifdef __cplusplus
extern "C" {
#endif

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_CancelDMA(
  ADXDMA_HDMA               hDMAEngine,
  _ADXDMA_UINT32            cancelFlags,
  ADXDMA_STATUS             completionStatus,
  _ADXDMA_UINT32*           pNumCancelled);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_CancelDMAAsync(
  ADXDMA_HDMA               hDMAEngine,
#ifdef _WIN32
  OVERLAPPED*               pOverlapped); /* Cannot be NULL */
#else
  void*                     pReserved); /* Must be NULL */
#endif

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_CancelWaitUserInt(
  ADXDMA_HUSERINT           hUserInt,
  _ADXDMA_UINT32            cancelFlags,
  ADXDMA_STATUS             completionStatus,
  _ADXDMA_UINT32*           pNumWaitCancelled);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_CancelWaitUserIntAsync(
  ADXDMA_HUSERINT           hUserInt,
#ifdef _WIN32
  OVERLAPPED*               pOverlapped); /* Cannot be NULL */
#else
  void*                     pReserved); /* Must be NULL */
#endif

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_Close(
  ADXDMA_HDEVICE            hDevice);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_CloseDMAEngine(
  ADXDMA_HDMA               hDMAEngine);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_CloseUserInt(
  ADXDMA_HUSERINT           hUserInt);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_CloseWindow(
  ADXDMA_HWINDOW            hWindow);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_ControlDMA(
  ADXDMA_HDMA               hDMAEngine,
  _ADXDMA_UINT32            flags,
  ADXDMA_DMA_CONTROL_OP     operation);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_ControlUserInt(
  ADXDMA_HUSERINT           hUserInt,
  ADXDMA_USERINT_OP         operation,
  _ADXDMA_UINT16            operand);

#ifdef _WIN32
ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_ConvertWin32Error(
  DWORD                     dwWin32Error,
  BOOL*                     pbRecognized); /* May be NULL */
#endif

#if defined(__linux) || defined(__linux__)
ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_ConvertLinuxErrno(
  int                       err,
  _ADXDMA_BOOL*             pbRecognized); /* May be NULL */
#endif

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_GetAPIInfo(
  ADXDMA_API_INFO*          pAPIInfo);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_GetDeviceCount(
  _ADXDMA_UINT32*           pDeviceCount);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_GetDeviceInfo(
  ADXDMA_HDEVICE            hDevice,
  ADXDMA_DEVICE_INFO*       pDeviceInfo);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_GetDriverInfo(
  ADXDMA_DRIVER_INFO*       pDriverInfo);

#ifdef _WIN32
ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_GetDMADebugState(
  ADXDMA_HDMA               hDMAEngine,
  ADXDMA_DMA_DEBUG_STATE*   pDebugState);
#endif

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_GetDMAEngineInfo(
  ADXDMA_HDEVICE            hDevice,
  _ADXDMA_BOOL              bH2c,
  unsigned int              engineIndex,
  ADXDMA_DMA_ENGINE_INFO*   pDMAEngineInfo);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_GetDMAQConfig(
  ADXDMA_HDMA               hDMAEngine,
  ADXDMA_DMAQ_CONFIG*       pQueueConfig);

#if defined(_UNICODE)
# define ADXDMA_GetStatusString ADXDMA_GetStatusStringW
#else
# define ADXDMA_GetStatusString ADXDMA_GetStatusStringA
#endif

ADXDMA_EXPORT const char*
ADXDMA_CALLING_CONVENTION
ADXDMA_GetStatusStringA(
  ADXDMA_STATUS             code,
  _ADXDMA_BOOL              bShort);

ADXDMA_EXPORT const wchar_t*
ADXDMA_CALLING_CONVENTION
ADXDMA_GetStatusStringW(
  ADXDMA_STATUS             code,
  _ADXDMA_BOOL              bShort);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_GetWindowInfo(
  ADXDMA_HDEVICE            hDevice,
  unsigned int              windowIndex,
  ADXDMA_WINDOW_INFO*       pWindowInfo);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_GetWindowPolicy(
  ADXDMA_HWINDOW            hWindow,
  ADXDMA_WINDOW_POLICY*     pWindowPolicy);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_JoinDMA(
  ADXDMA_HDMA               hDMAEngine,
  _ADXDMA_UINT32            flags,
  _ADXDMA_UINT32            timeoutUs,
#ifdef _WIN32
  OVERLAPPED*               pOverlapped, /* Cannot be NULL */
#else
  void*                     pReserved, /* Must be NULL */
#endif
  ADXDMA_STATUS*            pOperationStatus);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_JoinUserInt(
  ADXDMA_HUSERINT           hUserInt,
  _ADXDMA_UINT32            flags,
  _ADXDMA_UINT32            timeoutUs,
#ifdef _WIN32
  OVERLAPPED*               pOverlapped, /* Cannot be NULL */
#else
  void*                     pReserved, /* Must be NULL */
#endif
  ADXDMA_STATUS*            pOperationStatus);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_Lock(
  ADXDMA_HDEVICE            hDevice,
  const void*               pBuffer,
  size_t                    bufferSize,
  ADXDMA_HBUFFER*           phBuffer);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_MapWindow(
  ADXDMA_HWINDOW            hWindow,
  _ADXDMA_UINT64            windowOffset,
  size_t                    length,
  void**                    ppVirtualAddress);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_Open(
  unsigned int              deviceIndex,
  _ADXDMA_BOOL              bPassive,
  ADXDMA_HDEVICE*           phDevice);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_OpenDMAEngine(
  ADXDMA_HDEVICE            hParentDevice,
  unsigned int              deviceIndex,
  _ADXDMA_BOOL              bPassive,
  _ADXDMA_BOOL              bOpenH2C,
  unsigned int              engineIndex,
  ADXDMA_HDMA*              phDMAEngine);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_OpenUserInt(
  ADXDMA_HDEVICE            hParentDevice,
  unsigned int              deviceIndex,
  _ADXDMA_BOOL              bPassive,
  ADXDMA_HUSERINT*          phUserInt);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_OpenWindow(
  ADXDMA_HDEVICE            hParentDevice,
  unsigned int              deviceIndex,
  _ADXDMA_BOOL              bPassive,
  unsigned int              windowIndex,
  ADXDMA_HWINDOW*           phWindow);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_ReadDMA(
  ADXDMA_HDMA               hDMAEngine,
  _ADXDMA_UINT32            flags,
  _ADXDMA_UINT64            remoteAddress,
  void*                     pBuffer,
  size_t                    transferLength,
  ADXDMA_COMPLETION*        pCompletionInfo); /* May be NULL */

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_ReadDMAAsync(
  ADXDMA_HDMA               hDMAEngine,
  _ADXDMA_UINT32            flags,
  _ADXDMA_UINT64            remoteAddress,
  void*                     pBuffer,
  size_t                    transferLength,
#ifdef _WIN32
  OVERLAPPED*               pOverlapped, /* Cannot be NULL */
#else
  void*                     pReserved, /* Must be NULL */
#endif
  ADXDMA_COMPLETION*        pCompletionInfo); /* May be NULL */

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_ReadDMALocked(
  ADXDMA_HDMA               hDMAEngine,
  _ADXDMA_UINT32            flags,
  _ADXDMA_UINT64            remoteAddress,
  ADXDMA_HBUFFER            hBuffer,
  size_t                    bufferOffset,
  size_t                    transferLength,
  ADXDMA_COMPLETION*        pCompletionInfo); /* May be NULL */

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_ReadDMALockedAsync(
  ADXDMA_HDMA               hDMAEngine,
  _ADXDMA_UINT32            flags,
  _ADXDMA_UINT64            remoteAddress,
  ADXDMA_HBUFFER            hBuffer,
  size_t                    bufferOffset,
  size_t                    transferLength,
#ifdef _WIN32
  OVERLAPPED*               pOverlapped, /* Cannot be NULL */
#else
  void*                     pReserved, /* Must be NULL */
#endif
  ADXDMA_COMPLETION*        pCompletionInfo); /* May be NULL */

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_ReadWindow(
  ADXDMA_HWINDOW            hWindow,
  _ADXDMA_UINT32            flags,
  _ADXDMA_UINT8             preferredSize,
  _ADXDMA_UINT64            offset,
  size_t                    length,
  void*                     pBuffer,
  ADXDMA_COMPLETION*        pCompletionInfo);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_ReadWindowNative(
  ADXDMA_HWINDOW            hWindow,
  _ADXDMA_UINT64            offset,
  size_t                    length,
  void*                     pBuffer,
  size_t*                   pnTransferred);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_Reopen(
  ADXDMA_HDEVICE            hDevice,
  _ADXDMA_BOOL              bPassive,
  ADXDMA_HDEVICE*           phDeviceReopened);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_ReopenDMAEngine(
  ADXDMA_HDMA               hDMAEngine,
  _ADXDMA_BOOL              bPassive,
  ADXDMA_HDMA*              phDMAEngineReopened);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_ReopenUserInt(
  ADXDMA_HUSERINT           hUserInt,
  _ADXDMA_BOOL              bPassive,
  ADXDMA_HUSERINT*          phUserIntReopened);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_ReopenWindow(
  ADXDMA_HWINDOW            hWindow,
  _ADXDMA_BOOL              bPassive,
  ADXDMA_HWINDOW*           phWindowReopened);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_Reset(
  ADXDMA_HDEVICE            hDevice);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_SetDMAQConfig(
  ADXDMA_HDMA               hDMAEngine,
  const ADXDMA_DMAQ_CONFIG* pQueueConfig);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_SetWindowPolicy(
  ADXDMA_HWINDOW              hWindow,
  const ADXDMA_WINDOW_POLICY* pWindowPolicy);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_Unlock(
  ADXDMA_HDEVICE            hDevice,
  ADXDMA_HBUFFER            hBuffer);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_UnmapWindow(
  ADXDMA_HWINDOW            hWindow,
  void*                     pVirtualAddress);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_WaitUserInt(
  ADXDMA_HUSERINT           hUserInt,
  _ADXDMA_UINT32            flags,
  _ADXDMA_UINT16            sensitivity,
  _ADXDMA_UINT32            timeoutUs,
  _ADXDMA_UINT16*           pActiveUserInts);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_WaitUserIntAsync(
  ADXDMA_HUSERINT           hUserInt,
  _ADXDMA_UINT32            flags,
  _ADXDMA_UINT16            sensitivity,
#ifdef _WIN32
  OVERLAPPED*               pOverlapped, /* Cannot be NULL */
#else
  void*                     pReserved, /* Must be NULL */
#endif
  _ADXDMA_UINT16*           pActiveUserInts);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_WriteDMA(
  ADXDMA_HDMA               hDMAEngine,
  _ADXDMA_UINT32            flags,
  _ADXDMA_UINT64            remoteAddress,
  const void*               pBuffer,
  size_t                    transferLength,
  ADXDMA_COMPLETION*        pCompletionInfo); /* May be NULL */

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_WriteDMAAsync(
  ADXDMA_HDMA               hEngine,
  _ADXDMA_UINT32            flags,
  _ADXDMA_UINT64            remoteAddress,
  const void*               pBuffer,
  size_t                    transferLength,
#ifdef _WIN32
  OVERLAPPED*               pOverlapped, /* Cannot be NULL */
#else
  void*                     pReserved, /* Must be NULL */
#endif
  ADXDMA_COMPLETION*        pCompletionInfo); /* May be NULL */

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_WriteDMALocked(
  ADXDMA_HDMA               hDMAEngine,
  _ADXDMA_UINT32            flags,
  _ADXDMA_UINT64            remoteAddress,
  ADXDMA_HBUFFER            hBuffer,
  size_t                    bufferOffset,
  size_t                    transferLength,
  ADXDMA_COMPLETION*        pCompletionInfo); /* May be NULL */

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_WriteDMALockedAsync(
  ADXDMA_HDMA               hDMAEngine,
  _ADXDMA_UINT32            flags,
  _ADXDMA_UINT64            remoteAddress,
  ADXDMA_HBUFFER            hBuffer,
  size_t                    bufferOffset,
  size_t                    transferLength,
#ifdef _WIN32
  OVERLAPPED*               pOverlapped, /* Cannot be NULL */
#else
  void*                     pReserved, /* Must be NULL */
#endif
  ADXDMA_COMPLETION*        pCompletionInfo); /* May be NULL */

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_WriteWindow(
  ADXDMA_HWINDOW            hWindow,
  _ADXDMA_UINT32            flags,
  _ADXDMA_UINT8             preferredSize,
  _ADXDMA_UINT64            offset,
  size_t                    length,
  const void*               pBuffer,
  ADXDMA_COMPLETION*        pCompletionInfo);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_WriteWindowNative(
  ADXDMA_HWINDOW            hWindow,
  _ADXDMA_UINT64            offset,
  size_t                    length,
  const void*               pBuffer,
  size_t*                   pnTransferred);

#ifdef __cplusplus
}
#endif

#endif
