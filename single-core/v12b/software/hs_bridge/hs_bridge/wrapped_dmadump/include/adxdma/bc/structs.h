#ifndef _ALPHADATA_ADXDMA_BC_STRUCTS_H
#define _ALPHADATA_ADXDMA_BC_STRUCTS_H

/*
** <adxdma/bc/structs.h> - Structs used in Board Control functions of ADXDMA
**                         API.
**
** (C) Copyright Alpha Data 2017, 2018
*/

/*
** Microcontroller Status structure, returned by ADXDMA_GetUCStatus
*/

typedef struct _ADXDMA_UC_STATUS {
  struct {
    _ADXDMA_UINT32 ServiceMode     : 1;
    _ADXDMA_UINT32 RXProtocolError : 1;
    _ADXDMA_UINT32 TXFramingError  : 1;
    _ADXDMA_UINT32 Reserved1       : 29;
  } Flags;
  _ADXDMA_UINT32 Reserved;
} ADXDMA_UC_STATUS;

/*
** Board Control information structure, returned by ADXDMA_GetBCInfo
*/

typedef struct _ADXDMA_BC_INFO {
  _ADXDMA_UINT64 WindowOffset;       /* Window offset at which the BCI is visible */ 
  _ADXDMA_UINT8  WindowIndex;        /* Index of the Window in which the BCI is visible */
  _ADXDMA_UINT8  UserInterruptIndex; /* Index of the User Interrupt to which the BCI is connected (or 0xFF if not connected) */
  _ADXDMA_UINT16 Reserved1;
  _ADXDMA_UINT32 Reserved2;
  _ADXDMA_UINT32 ID;                 /* Identifies the BCI register-level interface */
  struct {
    _ADXDMA_UINT16 MajorFeature;     /* Firmware major version (currently 2) */
    _ADXDMA_UINT16 MinorFeature;     /* Indicates feature level */
    _ADXDMA_UINT16 MajorBuild;       /* Used by Alpha Data for traceability purposes */
    _ADXDMA_UINT16 MinorBuild;       /* Used by Alpha Data for traceability purposes; nonzero only for debug build */
  } FirmwareVersion;
  _ADXDMA_UINT32 DrawingNumber;      /* Identifies the Alpha Data product, or 0 if information could not be retrieved from uC */
  _ADXDMA_UINT32 SerialNumber;       /* The serial number of the card, or 0 if information could not be retrieved from uC */
  _ADXDMA_UINT32 VPDRegionSize;      /* Size of Vital Product Data region, in bytes */
  unsigned int   NumClock;           /* Number of available programmable clocks, or 0 if information could not be retrieved from uC */
  unsigned int   NumSensor;          /* Number of available sensors, or 0 if information could not be retrieved from uC */
} ADXDMA_BC_INFO;

/*
** Sensor Information structure, returned by ADXDMA_EnumerateSensors
*/

typedef struct _ADXDMA_SENSOR_INFOA {
  char               Description[32]; /* Textual description of sensor */
  ADXDMA_SENSOR_UNIT Unit;            /* Unit of readings (A, V, deg. C etc.) */
  short              Exponent;        /* Log10 of scaling factor applied to sensor readings */
} ADXDMA_SENSOR_INFOA;

typedef struct _ADXDMA_SENSOR_INFOW {
  wchar_t            Description[32]; /* Textual description of sensor */
  ADXDMA_SENSOR_UNIT Unit;            /* Unit of readings (A, V, deg. C etc.) */
  short              Exponent;        /* Log10 of scaling factor applied to sensor readings */
} ADXDMA_SENSOR_INFOW;

#if defined(_UNICODE)
# define ADXDMA_SENSOR_INFO ADXDMA_SENSOR_INFOW
#else
# define ADXDMA_SENSOR_INFO ADXDMA_SENSOR_INFOA
#endif

/*
** Sensor reading, returned by ADXDMA_ReadSensor
*/

typedef struct _ADXDMA_SENSOR_READING {
  _ADXDMA_INT64  Value;
  _ADXDMA_UINT32 Flags;
} ADXDMA_SENSOR_READING;

#endif
