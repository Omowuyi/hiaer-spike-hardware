#ifndef _ALPHADATA_ADXDMA_BC_H
#define _ALPHADATA_ADXDMA_BC_H

/*
** <adxdma/bc.h> - Header file for Board Control functions of ADXDMA.
**
** (C) Copyright 2017, 2018 Alpha Data
**
** The integer datatypes used below that are prefixed by "_ADXDMA_", such
** as "_ADXDMA_UINT64" are defined in order to increase the portability of
** this header file but should NOT be used by application code that makes
** use of the ADXDMA API.
**
** Applications should use OS-specific types such as UINT32 (Windows) or
** uint32_t (Linux C99).
*/

#include <adxdma.h>

#include <adxdma/bc/platform.h>
#include <adxdma/bc/types.h>
#include <adxdma/bc/structs.h>
#include <adxdma/bc/version.h>

/*
** Function prototypes
*/

#ifdef __cplusplus
extern "C" {
#endif

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_CancelCommandUC(
  ADXDMA_HBC                hBC,
  _ADXDMA_UINT32            cancelFlags,
  ADXDMA_STATUS             completionStatus,
  _ADXDMA_UINT32*           pNumCancelled);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_CloseBC(
  ADXDMA_HBC                hBC);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_CommandUC(
  ADXDMA_HBC                hBC,
  _ADXDMA_UINT32            flags,
  _ADXDMA_UINT32            timeoutUs,
  _ADXDMA_UINT32            commandLength,
  const _ADXDMA_UINT8*      pCommand,
  _ADXDMA_UINT32            responseLength,
  _ADXDMA_UINT8*            pResponse,
  _ADXDMA_UINT32*           pActualResponseLength);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_GetBCInfo(
  ADXDMA_HBC                hBC,
  ADXDMA_BC_INFO*           pBCInfo);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_GetClockFrequency(
  ADXDMA_HBC                hBC,
  _ADXDMA_UINT32            flags,
  unsigned int              clockIndex,
  _ADXDMA_UINT32*           pCurrentFrequency);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_GetSensorInfoA(
  ADXDMA_HBC                hBC,
  unsigned int              sensorIndex,
  ADXDMA_SENSOR_INFOA*      pSensorInfo);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_GetSensorInfoW(
  ADXDMA_HBC                hBC,
  unsigned int              sensorIndex,
  ADXDMA_SENSOR_INFOW*      pSensorInfo);

#if defined(_UNICODE)
# define ADXDMA_GetSensorInfo ADXDMA_GetSensorInfoW
#else
# define ADXDMA_GetSensorInfo ADXDMA_GetSensorInfoA
#endif

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_GetUCStatus(
  ADXDMA_HBC                hBC,
  ADXDMA_UC_STATUS*         pUCStatus);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_OpenBC(
  ADXDMA_HDEVICE            hParentDevice,
  unsigned int              deviceIndex,
  _ADXDMA_BOOL              bPassive,
  ADXDMA_HBC*               phBC);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_ReadSensor(
  ADXDMA_HBC                hBC,
  unsigned int              sensorIndex,
  ADXDMA_SENSOR_READING*    pReading);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_ReopenBC(
  ADXDMA_HBC                hBC,
  _ADXDMA_BOOL              bPassive,
  ADXDMA_HBC*               phBCReopened);

ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_SetClockFrequency(
  ADXDMA_HBC                hBC,
  _ADXDMA_UINT32            flags,
  unsigned int              clockIndex,
  _ADXDMA_UINT32            requestedFrequency,
  _ADXDMA_UINT32*           pActualFrequency);

#ifdef __cplusplus
}
#endif

#endif
