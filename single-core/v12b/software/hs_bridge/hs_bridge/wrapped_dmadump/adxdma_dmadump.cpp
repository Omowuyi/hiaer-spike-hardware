/*
** adxdma_dmadump.cpp
**
** Utility for reading from or writing to a particular ADXDMA Device using a C2H/H2C DMA engine.
*/

#ifdef _WIN32

# include <windows.h>
# include <malloc.h>
# include <tchar.h>

# define my_aligned_alloc(alignment, size) _aligned_malloc(size, alignment)
# define my_aligned_free(p) _aligned_free(p)

typedef UINT8 uint8_t;
typedef UINT16 uint16_t;
typedef UINT32 uint32_t;
typedef UINT64 uint64_t;

#elif defined(__linux)

#define _LARGEFILE64_SOURCE /* To get lseek64 */
# include <errno.h>
# include <stdint.h>
# include <stdlib.h>
# include <stdbool.h>
# include <sys/types.h>
# include <unistd.h>

# define _T(x) x
# define _tmain main
# define _stprintf_s snprintf
# define _tcscat_s my_tcscat_s
# define _tcslen_s strlen
# define my_aligned_alloc(alignment, size) aligned_alloc(alignment, size)
# define my_aligned_free(p) free(p)

typedef char TCHAR;

#elif defined(__VXWORKS__) || defined(__vxworks)

# include <vxWorks.h>

# if _WRS_VXWORKS_MAJOR >= 6
#   include <stdint.h>
# endif

# define _T(x) x
# define _tmain main
typedef char TCHAR;

#endif

#include <cassert>
#include <cstdarg>
#include <cstring>
#include <string>
#include <iostream>

#include <exappmessage.h>

#include <adxdma.h>

#include "adxdma_dmadump.h"

using namespace AlphaData::AppFramework;

#ifndef FALSE
# define FALSE 0
#endif
#ifndef TRUE
# define TRUE 1
#endif

#define ARRAY_LENGTH(x) (sizeof(x) / sizeof((x)[0]))

#define IS_ALIGNED(p, s) (((uintptr_t)(p) & ((s) - 1)) == 0)

#ifdef _UNICODE
typedef std::wstringstream SStreamType;
#define SSEMPTY(ss) ((ss).str(std::basic_string<wchar_t>()))
#else
typedef std::stringstream SStreamType;
#define SSEMPTY(ss) ((ss).str(std::string()))
#endif

CExAppMessageDisplay g_messageDisplay;

#ifndef _WIN32
static void
my_tcscat_s(
  TCHAR* pDst,
  size_t bufSizeChar,
  const TCHAR* pSrc)
{
  size_t n = _tcslen_s(pDst);
  size_t m, srcLen;

  if (n >= bufSizeChar) {
    return;
  }

  /* Subtract number of bytes already at pDst from buffer size */
  bufSizeChar -= n;

  srcLen = _tcslen_s(pSrc);

  m = bufSizeChar - 1; /* Subtract 1 to leave space for NUL terminator */
  if (srcLen > m) {
    srcLen = m;
  }

  memmove(pDst + n, pSrc, sizeof(TCHAR) * m);

  n += m;

  /* Add NUL terminator */
  pDst[n] = _T('\0');
}
#endif

static void
displayMemory(
  const uint8_t* pBuffer,
  uint64_t address,
  size_t byteCount,
  unsigned int wordSize,
  bool bNoAlign)
{
  const uint32_t bytesPerLine = 16; /* Must be a power of 2 */
  const uint32_t offsetLowMask = bytesPerLine - 1;
  TCHAR hexBuffer[3 * bytesPerLine + 1];
  TCHAR asciiBuffer[bytesPerLine + 1];
  TCHAR wordBuffer[17];
  TCHAR byteRepresentation[3];
  uint32_t position;
  size_t numLine, line;
  unsigned int byteInWord;
  uint32_t offsetLo;
  uint64_t offset, addressLimit, lineOffset;
  uint8_t currentByte;
  TCHAR asciiSymbol;

  assert(wordSize == 1 || wordSize == 2 || wordSize == 4 || wordSize == 8);

  addressLimit = address + byteCount;

  offsetLo = (uint32_t)address & offsetLowMask;

  asciiBuffer[bytesPerLine] = _T('\0');

  if (bNoAlign) {
    offset = address;
    numLine = (byteCount + offsetLowMask) / bytesPerLine;
  } else {
    offset = address & ~(uint64_t)offsetLowMask;
    numLine = (byteCount + offsetLo + offsetLowMask) / bytesPerLine;
  }

  for (line = 0; line < numLine; line++) {
    hexBuffer[0] = _T('\0');
    asciiBuffer[0] = _T('\0');
    lineOffset = offset;

    for (position = 0; position < bytesPerLine; position++) {
      byteInWord = position & (wordSize - 1);
      if (offset < address || offset >= addressLimit) {
        byteRepresentation[1] = byteRepresentation[0] = _T('?');
        byteRepresentation[2] = _T('\0');
        asciiSymbol = _T('.');
      } else {
        currentByte = *pBuffer++;
        _stprintf_s(byteRepresentation, ARRAY_LENGTH(byteRepresentation), _T("%02X"), currentByte);
        asciiSymbol = isprint((int)currentByte) ? (TCHAR)currentByte : _T('.');
      }
      wordBuffer[(wordSize - byteInWord - 1) * 2] = byteRepresentation[0];
      wordBuffer[(wordSize - byteInWord - 1) * 2 + 1] = byteRepresentation[1];
      if (byteInWord == wordSize - 1) {
        wordBuffer[wordSize * 2] = _T('\0');
        _tcscat_s(hexBuffer, ARRAY_LENGTH(hexBuffer), wordBuffer);
        _tcscat_s(hexBuffer, ARRAY_LENGTH(hexBuffer), _T(" "));
      }
      asciiBuffer[position] = asciiSymbol;
      offset++;
    }

    g_messageDisplay.FormatInfo(_T("%08lX_%08lX: %s %s"),
      (unsigned long)((lineOffset >> 32) & 0xFFFFFFFF), (unsigned long)(lineOffset & 0xFFFFFFFF),
      hexBuffer, asciiBuffer);

    lineOffset += bytesPerLine;
  }
}

#ifdef _WIN32
static ExitCode
doReadNative(
  ADXDMA_HDMA hDMAEngine,
  uint64_t address,
  uint32_t byteCount,
  unsigned int wordSize)
{
  ExitCode exitCode = ExitCodeSuccess;
  OVERLAPPED overlapped;
  uint8_t* pBuffer = NULL;
  DWORD bytesRead;
  uint32_t totalRead = 0, remaining;
  uint64_t currentOffset;
  BOOL bResult;
  DWORD dwLastError;

  _ASSERTE(wordSize == 1 || wordSize == 2 || wordSize == 4 || wordSize == 8);

  ZeroMemory(&overlapped, sizeof(overlapped));

  pBuffer = (uint8_t*)my_aligned_alloc(ADXDMA_DMA_BUFFER_ALIGNMENT, byteCount);
  if (NULL == pBuffer) {
    g_messageDisplay.FormatError(_T("Failed to allocate data buffer of 0x%X byte(s)."), byteCount);
    exitCode = ExitCodeBufferAllocFailed;
    goto done;
  }

  overlapped.hEvent = CreateEvent(NULL, FALSE, FALSE, NULL);
  _ASSERTE(NULL != overlapped.hEvent);

  currentOffset = address;
  remaining = byteCount;
  while (remaining) {
    overlapped.Offset = (DWORD)(currentOffset & 0xFFFFFFFF);
    overlapped.OffsetHigh = (DWORD)((currentOffset >> 32) & 0xFFFFFFFF);

    bResult = ReadFile(hDMAEngine, pBuffer, remaining, NULL, &overlapped);
    if (!bResult) {
      dwLastError = GetLastError();
      if (ERROR_IO_PENDING == dwLastError) {
        bResult = GetOverlappedResult(hDMAEngine, &overlapped, &bytesRead, TRUE);
        if (!bResult) {
          dwLastError = GetLastError();
        }
      }
    }

    if (!bResult) {
      break;
    }

    remaining -= bytesRead;
    currentOffset += bytesRead;
    totalRead += bytesRead;

    if (bytesRead < remaining) {
      break;
    }
  }

  if (!bResult) {
    g_messageDisplay.FormatError(_T("Failed to read 0x%X bytes using H2C DMA engine at offset 0x%08lX_%08lX: Win32 error code 0x%X"),
      byteCount, (unsigned long)((address >> 32) & 0xFFFFFFFF), (unsigned long)(address & 0xFFFFFFFF), dwLastError);
    exitCode = ExitCodeDMAReadFailed;
    goto done;
  }

  if (totalRead != byteCount) {
    g_messageDisplay.FormatWarning(_T("Encountered end-of-file before reading 0x%X bytes; actually read 0x%X bytes"),
      byteCount, totalRead);
  }

  //displayMemory(pBuffer, address, totalRead, wordSize, FALSE);

done:
  if (NULL != overlapped.hEvent) {
    CloseHandle(overlapped.hEvent);
  }

  if (NULL != pBuffer) {
    my_aligned_free(pBuffer);
  }

  return exitCode;
}
#else
static ExitCode
doReadNative(
  ADXDMA_HDMA hDMAEngine,
  uint64_t address,
  uint32_t byteCount,
  unsigned int wordSize)
{
  ExitCode exitCode = ExitCodeSuccess;
  void* pBuffer = NULL;
  uint8_t* p;
  ssize_t bytesRead;
  size_t remaining, totalRead;
  off_t seekErr;

  assert(wordSize == 1 || wordSize == 2 || wordSize == 4 || wordSize == 8);

  pBuffer = (uint8_t*)my_aligned_alloc(ADXDMA_DMA_BUFFER_ALIGNMENT, byteCount);
  if (NULL == pBuffer) {
    g_messageDisplay.FormatError(_T("Failed to allocate data buffer of 0x%X byte(s)."), byteCount);
    exitCode = ExitCodeBufferAllocFailed;
    goto done;
  }

  seekErr = lseek64((int)hDMAEngine, address, SEEK_SET);
  if (seekErr < 0) {
    int err = errno;

    g_messageDisplay.FormatError(_T("Failed to set seek to offset %llu(0x%llX); errno %d"),
      (unsigned long long)address, (unsigned long long)address, err);
  }

  remaining = byteCount;
  p = (uint8_t*)pBuffer;

  while (remaining) {
    bytesRead = read((int)hDMAEngine, p, remaining);
    if (bytesRead < 0) {
      int err = errno;

      g_messageDisplay.FormatError(_T("Failed to read %llu(0x%llX) bytes; errno %d"),
        (unsigned long long)byteCount, (unsigned long long)byteCount, err);
      exitCode = ExitCodeDMAReadFailed;
      goto done;
    } else if (0 == bytesRead) {
      /* EOF */
      break;
    }

    assert((size_t)bytesRead <= remaining);

    remaining -= bytesRead;
    p = (uint8_t*)((uintptr_t)p + bytesRead);
  }

  totalRead = byteCount - remaining;

  if (remaining) {
    g_messageDisplay.FormatWarning(_T("Encountered end-of-file before reading 0x%X byte(s); actually read 0x%llX byte(s)"),
      byteCount, (unsigned long long)totalRead);
  }

  //displayMemory((uint8_t*)pBuffer, address, totalRead, wordSize, FALSE);

done:
  if (NULL != pBuffer) {
    my_aligned_free(pBuffer);
  }

  return exitCode;
}
#endif

static ExitCode
doReadLocked(
  ADXDMA_HDEVICE hDevice,
  ADXDMA_HDMA hDMAEngine,
  uint64_t address,
  uint32_t byteCount,
  unsigned int wordSize)
{
  ExitCode exitCode = ExitCodeSuccess;
  uint8_t* pBuffer = NULL;
  ADXDMA_COMPLETION completion;
  ADXDMA_STATUS status;
  ADXDMA_HBUFFER hBuffer = 0;

  assert(wordSize == 1 || wordSize == 2 || wordSize == 4 || wordSize == 8);

  pBuffer = (uint8_t*)my_aligned_alloc(ADXDMA_DMA_BUFFER_ALIGNMENT, byteCount);
  if (NULL == pBuffer) {
    g_messageDisplay.FormatError(_T("Failed to allocate data buffer of 0x%X byte(s)."), byteCount);
    exitCode = ExitCodeBufferAllocFailed;
    goto done;
  }
  
  status = ADXDMA_Lock(hDevice, pBuffer, byteCount, &hBuffer);
  if (ADXDMA_SUCCESS != status) {
    g_messageDisplay.FormatError(_T("Failed to lock data buffer: %s(%u)"), ADXDMA_GetStatusString(status, TRUE), status);
    exitCode = ExitCodeBufferLockFailed;
    goto done;
  }

  status = ADXDMA_ReadDMALocked(
    hDMAEngine,
    0,
    address,
    hBuffer,
    0,
    byteCount,
    &completion);

  if (ADXDMA_IS_ERROR(status)) {
    g_messageDisplay.FormatError(_T("Failed to read 0x%X bytes from C2H DMA engine at offset 0x%08lX_%08lX: %s(%u)"),
      byteCount, (unsigned long)((address >> 32) & 0xFFFFFFFF), (unsigned long)(address & 0xFFFFFFFF), ADXDMA_GetStatusString(status, TRUE), status);
    exitCode = ExitCodeDMAReadFailed;
    goto done;
  }

  if (completion.Transferred != byteCount) {
    g_messageDisplay.FormatError(_T("Failed to read all 0x%llX bytes from C2H DMA engine; actually read 0x%llX; completion.Reason=%s(%u)."),
      (unsigned long long)byteCount, (unsigned long long)completion.Transferred, ADXDMA_GetStatusString(completion.Reason, TRUE), completion.Reason);
    exitCode = ExitCodeDMAReadFailed;
    goto done;
  }

  //displayMemory(pBuffer, address, byteCount, wordSize, FALSE);

done:
  if (ADXDMA_NULL_HBUFFER != hBuffer) {
    ADXDMA_STATUS tmpStatus = ADXDMA_Unlock(hDevice, hBuffer);
    if (ADXDMA_SUCCESS != tmpStatus) {
      g_messageDisplay.FormatWarning(_T("Failed to unlock buffer; hBuffer=%u"), hBuffer);
    }
  }

  if (NULL != pBuffer) {
    my_aligned_free(pBuffer);
  }

  return exitCode;
}


static ExitCode
doRead(
  ADXDMA_HDMA hDMAEngine,
  uint64_t address,
  uint32_t readCount,
  unsigned int wordSize,
  uint64_t data[],
  unsigned int dataElements,
  unsigned int dataStride)
{
  uint32_t byteCount = (uint32_t)(readCount * wordSize); 
  ExitCode exitCode = ExitCodeSuccess;
  uint8_t* pBuffer = NULL;
  ADXDMA_COMPLETION completion;
  ADXDMA_STATUS status;

  assert(wordSize == 1 || wordSize == 2 || wordSize == 4 || wordSize == 8);

  pBuffer = (uint8_t*)my_aligned_alloc(ADXDMA_DMA_BUFFER_ALIGNMENT, byteCount);
  if (NULL == pBuffer) {
    g_messageDisplay.FormatError(_T("Failed to allocate data buffer of 0x%X byte(s)."), byteCount);
    exitCode = ExitCodeBufferAllocFailed;
    goto done;
  }

  status = ADXDMA_ReadDMA(
    hDMAEngine,
    0,
    address,
    pBuffer,
    byteCount,
    &completion);

  if (ADXDMA_IS_ERROR(status)) {
    g_messageDisplay.FormatError(_T("Failed to read 0x%X bytes from C2H DMA engine at offset 0x%08lX_%08lX: %s(%u)"),
      byteCount, (unsigned long)((address >> 32) & 0xFFFFFFFF), (unsigned long)(address & 0xFFFFFFFF), ADXDMA_GetStatusString(status, TRUE), status);
    exitCode = ExitCodeDMAReadFailed;
    goto done;
  }

  if (completion.Transferred != byteCount) {
    g_messageDisplay.FormatError(_T("Failed to read all 0x%llX bytes from C2H DMA engine; actually read 0x%llX; completion.Reason=%s(%u)."),
      (unsigned long long)byteCount, (unsigned long long)completion.Transferred, ADXDMA_GetStatusString(completion.Reason, TRUE), completion.Reason);
    exitCode = ExitCodeDMAReadFailed;
    goto done;
  }
  //TODO: Can I just divide byteCount like this?
  if (wordSize == 1){
      for(int i = 0; i < readCount; i++){
          data[dataStride*i] = (uint64_t)((uint8_t*)pBuffer)[i];
      }
  }
  else if (wordSize == 2){
      for(int i = 0; i < readCount; i++){
          data[dataStride*i] = (uint64_t)((uint16_t*)pBuffer)[i];
      }
  }
  else if (wordSize == 3){
      for(int i = 0; i < readCount; i++){
          data[dataStride*i] = (uint64_t)((uint32_t*)pBuffer)[i];
      }
  }
  else{
      for(int i = 0; i < readCount; i++){
          data[dataStride*i] = (uint64_t)pBuffer[i];
      }
  }
  //displayMemory(pBuffer, address, byteCount, wordSize, FALSE);

done:
  if (NULL != pBuffer) {
    my_aligned_free(pBuffer);
  }

  return exitCode;
  //we somehow want to return the contents of pBuffer, we might need to pass in our own buffer to get data back into
}

#ifdef _WIN32
static ExitCode
doWriteNative(
  ADXDMA_HDMA hDMAEngine,
  uint64_t address,
  uint32_t byteCount,
  const void* pData)
{
  ExitCode exitCode = ExitCodeSuccess;
  OVERLAPPED overlapped;
  DWORD bytesWritten;
  BOOL bResult = TRUE;
  DWORD dwLastError;

  ZeroMemory(&overlapped, sizeof(overlapped));

  overlapped.hEvent = CreateEvent(NULL, FALSE, FALSE, NULL);
  _ASSERTE(NULL != overlapped.hEvent);

  overlapped.Offset = (DWORD)(address & 0xFFFFFFFF);
  overlapped.OffsetHigh = (DWORD)((address >> 32) & 0xFFFFFFFF);

  bResult = WriteFile(hDMAEngine, pData, byteCount, NULL, &overlapped);
  if (!bResult) {
    dwLastError = GetLastError();
    if (ERROR_IO_PENDING == dwLastError) {
      bResult = GetOverlappedResult(hDMAEngine, &overlapped, &bytesWritten, TRUE);
      if (!bResult) {
        dwLastError = GetLastError();
      } else {
        _ASSERTE(bytesWritten <= byteCount);
      }
    }
  }

  if (bytesWritten < byteCount) {
    g_messageDisplay.FormatWarning(_T("Encountered end-of-file before writing 0x%X bytes; actually wrote 0x%X bytes"),
      byteCount, bytesWritten);
  }

  if (!bResult) {
    g_messageDisplay.FormatError(
      _T("Failed to write 0x%X bytes using H2C DMA engine at offset 0x%08lX_%08lX: Win32 error code 0x%X"),
      byteCount, (unsigned long)((address >> 32) & 0xFFFFFFFF), (unsigned long)(address & 0xFFFFFFFF), dwLastError);
    exitCode = ExitCodeDMAWriteFailed;
    goto done;
  }

done:
  if (NULL != overlapped.hEvent) {
    CloseHandle(overlapped.hEvent);
  }

  return ExitCodeSuccess;
}
#else
static ExitCode
doWriteNative(
  ADXDMA_HDMA hDMAEngine,
  uint64_t address,
  uint32_t byteCount,
  const void* pData)
{
  ExitCode exitCode = ExitCodeSuccess;
  ssize_t bytesWritten;
  size_t remaining;
  off_t seekErr;

  seekErr = lseek64((int)hDMAEngine, address, SEEK_SET);
  if (seekErr < 0) {
    int err = errno;

    g_messageDisplay.FormatError(_T("Failed to set seek to offset %llu(0x%llX); errno %d"),
      (unsigned long long)address, (unsigned long long)address, err);
  }

  remaining = byteCount;

  while (remaining) {
    bytesWritten = write((int)hDMAEngine, pData, remaining);
    if (bytesWritten < 0) {
      int err = errno;

      g_messageDisplay.FormatError(_T("Failed to write %llu(0x%llX) bytes; errno %d"),
        (unsigned long long)byteCount, (unsigned long long)byteCount, err);
      exitCode = ExitCodeDMAWriteFailed;
      goto done;
    } else if (0 == bytesWritten) {
      /* EOF */
      break;
    }

    assert((size_t)bytesWritten <= remaining);

    remaining -= bytesWritten;
    pData = (const void*)((uintptr_t)pData + bytesWritten);
  }

  if (remaining) {
    g_messageDisplay.FormatWarning(_T("Encountered end-of-file before writing 0x%X byte(s); actually wrote 0x%llX byte(s)"),
      byteCount, (unsigned long long)(byteCount - remaining));
  }

done:
  return exitCode;
}
#endif

static ExitCode
doWrite(
  ADXDMA_HDMA hDMAEngine,
  uint64_t address,
  uint32_t byteCount,
  const void* pData)
{
  ExitCode exitCode = ExitCodeSuccess;
  ADXDMA_COMPLETION completion;
  ADXDMA_STATUS status;

  status = ADXDMA_WriteDMA(
    hDMAEngine,
    0,
    address,
    pData,
    byteCount,
    &completion);
  if (ADXDMA_IS_ERROR(status)) {
    g_messageDisplay.FormatError(_T("Failed to write 0x%X bytes using H2C DMA engine at address 0x%08lX_%08lX: %s(%u)"),
      byteCount, (unsigned long)((address >> 32) & 0xFFFFFFFF), (unsigned long)(address & 0xFFFFFFFF), ADXDMA_GetStatusString(status, TRUE), status);
    exitCode = ExitCodeDMAWriteFailed;
    goto done;
  }

  if (completion.Transferred != byteCount) {
    g_messageDisplay.FormatError(_T("Failed to write all 0x%llX bytes using H2C DMA engine; actually wrote 0x%llX; completion.Reason=%s(%u)."),
      (unsigned long long)byteCount, (unsigned long long)completion.Transferred, ADXDMA_GetStatusString(completion.Reason, TRUE), completion.Reason);
    exitCode = ExitCodeDMAWriteFailed;
    goto done;
  }

done:
  return exitCode;
}

static ExitCode
doWriteLocked(
  ADXDMA_HDEVICE hDevice,
  ADXDMA_HDMA hDMAEngine,
  uint64_t address,
  uint32_t byteCount,
  const void* pData)
{
  ExitCode exitCode = ExitCodeSuccess;
  ADXDMA_COMPLETION completion;
  ADXDMA_HBUFFER hBuffer = 0;
  ADXDMA_STATUS status;

  status = ADXDMA_Lock(hDevice, pData, byteCount, &hBuffer);
  if (ADXDMA_SUCCESS != status) {
    g_messageDisplay.FormatError(_T("Failed to lock data buffer: %s(%u)"), ADXDMA_GetStatusString(status, TRUE), status);
    exitCode = ExitCodeBufferLockFailed;
    goto done;
  }

  status = ADXDMA_WriteDMALocked(
    hDMAEngine,
    0,
    address,
    hBuffer,
    0,
    byteCount,
    &completion);
  if (ADXDMA_IS_ERROR(status)) {
    g_messageDisplay.FormatError(_T("Failed to write 0x%X bytes using H2C DMA engine at address 0x%08lX_%08lX: %s(%u)"),
      byteCount, (unsigned long)((address >> 32) & 0xFFFFFFFF), (unsigned long)(address & 0xFFFFFFFF), ADXDMA_GetStatusString(status, TRUE), status);
    exitCode = ExitCodeDMAWriteFailed;
    goto done;
  }

  if (completion.Transferred != byteCount) {
    g_messageDisplay.FormatError(_T("Failed to write all 0x%llX bytes using H2C DMA engine; actually wrote 0x%llX; completion.Reason=%s(%u)."),
      (unsigned long long)byteCount, (unsigned long long)completion.Transferred, ADXDMA_GetStatusString(completion.Reason, TRUE), completion.Reason);
    exitCode = ExitCodeDMAWriteFailed;
    goto done;
  }

done:
  if (ADXDMA_NULL_HBUFFER != hBuffer) {
    ADXDMA_STATUS tmpStatus = ADXDMA_Unlock(hDevice, hBuffer);
    if (ADXDMA_SUCCESS != tmpStatus) {
      g_messageDisplay.FormatWarning(_T("Failed to unlock buffer; hBuffer=%u"), hBuffer);
    }
  }

  return exitCode;
}

static ExitCode
doDMARead(
  unsigned int deviceIndex,
  unsigned int engineIndex,
  uint64_t address,
  uint32_t readCount,
  unsigned int wordSize,
  DmaMethod dmaMethod,
  uint64_t data[],
  unsigned int dataElements,
  unsigned int dataStride)
{
  ADXDMA_STATUS status;
  ADXDMA_HDEVICE hDevice = ADXDMA_NULL_HDEVICE;
  ADXDMA_HDMA hDMAEngine = ADXDMA_NULL_HDMA;
  ExitCode exitCode = ExitCodeSuccess;

  status = ADXDMA_Open(deviceIndex, FALSE, &hDevice);
  if (ADXDMA_SUCCESS != status) {
    g_messageDisplay.FormatError(_T("Failed to open ADXDMA device with index %u: %s(%u)."), deviceIndex, ADXDMA_GetStatusString(status, TRUE), status);
    exitCode = ExitCodeCannotOpenIndex;
    goto done;
  }

  status = ADXDMA_OpenDMAEngine(hDevice, 0, FALSE, FALSE, engineIndex, &hDMAEngine);
  if (ADXDMA_SUCCESS != status) {
    g_messageDisplay.FormatError(_T("Failed to open C2H%u DMA engine: %s(%u)."),
      engineIndex, ADXDMA_GetStatusString(status, TRUE), status);
    exitCode = ExitCodeCannotOpenDMAEngine;
    goto done;
  }

  switch (dmaMethod) {
  case DmaMethodNormal:
    exitCode = doRead(hDMAEngine, address, readCount, wordSize, data, dataElements, dataStride);
    break;

  case DmaMethodLocked:
    exitCode = doReadLocked(hDevice, hDMAEngine, address, readCount, wordSize);
    break;

  case DmaMethodNative:
    exitCode = doReadNative(hDMAEngine, address, readCount, wordSize);
    break;
  }

done:
  if (ADXDMA_NULL_HDMA != hDMAEngine) {
    ADXDMA_CloseDMAEngine(hDMAEngine);
  }

  if (ADXDMA_NULL_HDEVICE != hDevice) {
    ADXDMA_Close(hDevice);
  }

  return exitCode;
}

static ExitCode
doDMAWrite(
  unsigned int deviceIndex,
  unsigned int engineIndex,
  uint64_t address,
  uint32_t byteCount,
  DmaMethod dmaMethod,
  const void* pData)
{
  ADXDMA_STATUS status;
  ADXDMA_HDEVICE hDevice = ADXDMA_NULL_HDEVICE;
  ADXDMA_HDMA hDMAEngine = ADXDMA_NULL_HDMA;
  ExitCode exitCode = ExitCodeSuccess;

  status = ADXDMA_Open(deviceIndex, FALSE, &hDevice);
  if (ADXDMA_SUCCESS != status) {
    g_messageDisplay.FormatError(_T("Failed to open ADXDMA device with index %u: %s(%u)."), deviceIndex, ADXDMA_GetStatusString(status, TRUE), status);
    exitCode = ExitCodeCannotOpenIndex;
    goto done;
  }

  status = ADXDMA_OpenDMAEngine(hDevice, 0, FALSE, TRUE, engineIndex, &hDMAEngine);
  if (ADXDMA_SUCCESS != status) {
    g_messageDisplay.FormatError(_T("Failed to open H2C%u DMA engine: %s(%u)."),
      engineIndex, ADXDMA_GetStatusString(status, TRUE), status);
    exitCode = ExitCodeCannotOpenDMAEngine;
    goto done;
  }

  switch (dmaMethod) {
  case DmaMethodNormal:
    exitCode = doWrite(hDMAEngine, address, byteCount, pData);
    break;

  case DmaMethodLocked:
    exitCode = doWriteLocked(hDevice, hDMAEngine, address, byteCount, pData);
    break;

  case DmaMethodNative:
    exitCode = doWriteNative(hDMAEngine, address, byteCount, pData);
    break;
  }

done:
  if (ADXDMA_NULL_HDMA != hDMAEngine) {
    ADXDMA_CloseDMAEngine(hDMAEngine);
  }

  if (ADXDMA_NULL_HDEVICE != hDevice) {
    ADXDMA_Close(hDevice);
  }

  return exitCode;
}

int /* ExitCode */
adxdmaDMARead(
  unsigned int deviceIndex,
  unsigned int engineIndex,
  uint64_t     address,
  uint32_t     readCount,
  unsigned int wordSize,
  DmaMethod    dmaMethod,
  uint64_t data[],
  unsigned int dataElements,
  unsigned int dataStride)
{
  return (int)doDMARead(deviceIndex, engineIndex, address, readCount, wordSize, dmaMethod, data, dataElements, dataStride);
}

#if defined(__VXWORKS__) || defined(__vxworks)

int /* ExitCode */
adxdmaDMAReadB(
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  DmaMethod       method)
{
  return (int)doDMARead(deviceIndex, engineIndex, address, byteCount, 1, method);
}

int /* ExitCode */
adxdmaDMAReadW(
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  DmaMethod       method)
{
  return (int)doDMARead(deviceIndex, engineIndex, address, byteCount, 2, method);
}

int /* ExitCode */
adxdmaDMAReadD(
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  DmaMethod       method)
{
  return (int)doDMARead(deviceIndex, engineIndex, address, byteCount, 4, method);
}

int /* ExitCode */
adxdmaDMAReadQ(
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  DmaMethod       method)
{
  return (int)doDMARead(deviceIndex, engineIndex, address, byteCount, 8, method);
}

#endif

int /* ExitCode */
adxdmaDMAWriteBuffer(
  unsigned int deviceIndex,
  unsigned int engineIndex,
  uint64_t     address,
  uint32_t     byteCount,
  DmaMethod    dmaMethod,
  const void*  pData)
{
  return (int)doDMAWrite(deviceIndex, engineIndex, address, byteCount, dmaMethod, pData);
}

#if defined(__VXWORKS__) || defined(__vxworks)

int /* ExitCode */
adxdmaDMAWriteB(
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  DmaMethod       method,
  ...)
{
  uint8_t* pBuffer = NULL;
  va_list vl;
  int exitCode = 0;

  pBuffer = (uint8_t*)my_aligned_alloc(ADXDMA_DMA_BUFFER_ALIGNMENT, byteCount);
  if (NULL == pBuffer) {
    g_messageDisplay.FormatError(_T("Failed to allocate buffer of %lu(0x%lX) byte(s) for assembling write values."),
      (unsigned long)byteCount, (unsigned long)byteCount);
    return (int)ExitCodeBufferAllocFailed;
  }

  va_start(vl, method);
  for (uint32_t i = 0; i < byteCount; i += 1) {
    pBuffer[i] = (uint8_t)va_arg(vl, int);
  }
  va_end(vl);

  exitCode = (int)doDMAWrite(deviceIndex, engineIndex, address, byteCount, method, pBuffer);

  my_aligned_free(pBuffer);

  return exitCode;
}

int /* ExitCode */
adxdmaDMAWriteW(
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  DmaMethod       method,
  ...)
{
  const unsigned int wordSize = 2;
  unsigned int wordSizeMask = wordSize - 1;
  uint16_t* pBuffer = NULL;
  va_list vl;
  int exitCode = 0;

  if (!IS_ALIGNED(byteCount, wordSize)) {
    uint32_t byteCountAdjusted = byteCount & ~(uint32_t)wordSizeMask;
    g_messageDisplay.FormatWarning(_T("Byte count (0x%lX) is not a multiple of word size (%u); adjusted to 0x%lX."),
      (unsigned long)byteCount, wordSize, (unsigned long)byteCountAdjusted);
    byteCount = byteCountAdjusted;
  }

  pBuffer = (uint16_t*)my_aligned_alloc(ADXDMA_DMA_BUFFER_ALIGNMENT, byteCount);
  if (NULL == pBuffer) {
    g_messageDisplay.FormatError(_T("Failed to allocate buffer of %lu(0x%lX) byte(s) for assembling write values."),
      (unsigned long)byteCount, (unsigned long)byteCount);
    return (int)ExitCodeBufferAllocFailed;
  }

  va_start(vl, method);
  for (uint32_t i = 0; i < byteCount; i += 2) {
    pBuffer[i >> 1] = (uint16_t)va_arg(vl, int);
  }
  va_end(vl);

  exitCode = (int)doDMAWrite(deviceIndex, engineIndex, address, byteCount, method, pBuffer);

  my_aligned_free(pBuffer);

  return exitCode;
}

int /* ExitCode */
adxdmaDMAWriteD(
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  DmaMethod       method,
  ...)
{
  const unsigned int wordSize = 4;
  unsigned int wordSizeMask = wordSize - 1;
  uint32_t* pBuffer = NULL;
  va_list vl;
  int exitCode = 0;

  if (!IS_ALIGNED(byteCount, wordSize)) {
    uint32_t byteCountAdjusted = byteCount & ~(uint32_t)wordSizeMask;
    g_messageDisplay.FormatWarning(_T("Byte count (0x%lX) is not a multiple of word size (%u); adjusted to 0x%lX."),
      (unsigned long)byteCount, wordSize, (unsigned long)byteCountAdjusted);
    byteCount = byteCountAdjusted;
  }

  pBuffer = (uint32_t*)my_aligned_alloc(ADXDMA_DMA_BUFFER_ALIGNMENT, byteCount);
  if (NULL == pBuffer) {
    g_messageDisplay.FormatError(_T("Failed to allocate buffer of %lu(0x%lX) byte(s) for assembling write values."),
      (unsigned long)byteCount, (unsigned long)byteCount);
    return (int)ExitCodeBufferAllocFailed;
  }

  va_start(vl, method);
  for (uint32_t i = 0; i < byteCount; i += 4) {
    pBuffer[i >> 2] = (uint32_t)va_arg(vl, int);
  }
  va_end(vl);

  exitCode = (int)doDMAWrite(deviceIndex, engineIndex, address, byteCount, method, pBuffer);

  my_aligned_free(pBuffer);

  return exitCode;
}

int /* ExitCode */
adxdmaDMAWriteQ(
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  DmaMethod       method,
  ...)
{
  const unsigned int wordSize = 8;
  unsigned int wordSizeMask = wordSize - 1;
  uint64_t* pBuffer = NULL;
  va_list vl;
  int exitCode = 0;

  if (!IS_ALIGNED(byteCount, wordSize)) {
    uint32_t byteCountAdjusted = byteCount & ~(uint32_t)wordSizeMask;
    g_messageDisplay.FormatWarning(_T("Byte count (0x%lX) is not a multiple of word size (%u); adjusted to 0x%lX."),
      (unsigned long)byteCount, wordSize, (unsigned long)byteCountAdjusted);
    byteCount = byteCountAdjusted;
  }

  pBuffer = (uint64_t*)my_aligned_alloc(ADXDMA_DMA_BUFFER_ALIGNMENT, byteCount);
  if (NULL == pBuffer) {
    g_messageDisplay.FormatError(_T("Failed to allocate buffer of %lu(0x%lX) byte(s) for assembling write values."),
      (unsigned long)byteCount, (unsigned long)byteCount);
    return (int)ExitCodeBufferAllocFailed;
  }

  va_start(vl, method);
  for (uint32_t i = 0; i < byteCount; i += 8) {
    pBuffer[i >> 3] = (uint64_t)va_arg(vl, long long);
  }
  va_end(vl);

  exitCode = (int)doDMAWrite(deviceIndex, engineIndex, address, byteCount, method, pBuffer);

  my_aligned_free(pBuffer);

  return exitCode;
}

#endif
