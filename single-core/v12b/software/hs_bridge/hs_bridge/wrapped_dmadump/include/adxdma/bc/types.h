#ifndef _ALPHADATA_ADXDMA_BC_TYPES_H
#define _ALPHADATA_ADXDMA_BC_TYPES_H

/*
** <adxdma/bc/types.h> - Scalar types used in Board Control functions of
**                       ADXDMA API.
**
** (C) Copyright Alpha Data 2018
*/

/* Values for ADXDMA_SENSOR_INFO::Unit */
typedef enum _ADXDMA_SENSOR_UNIT {
  ADXDMA_SENSOR_UNIT_NONE        = 0,
  ADXDMA_SENSOR_UNIT_A           = 1, /* Amp */
  ADXDMA_SENSOR_UNIT_V           = 2, /* Volt */
  ADXDMA_SENSOR_UNIT_C           = 3, /* Degrees Celsius */
  ADXDMA_SENSOR_UNIT_K           = 4, /* Degrees Kelvin */
  ADXDMA_SENSOR_UNIT_SEC         = 5, /* Seconds */
  ADXDMA_SENSOR_UNIT_FORCE32BITS = 0x7FFFFFFF
} ADXDMA_SENSOR_UNIT;

/* Flags for ADXDMA_SENSOR_READING::Flags */
#define ADXDMA_SENSOR_UNDER_CRITICAL (0x1 << 0)
#define ADXDMA_SENSOR_UNDER_WARNING  (0x1 << 1)
#define ADXDMA_SENSOR_OVER_WARNING   (0x1 << 2)
#define ADXDMA_SENSOR_OVER_CRITICAL  (0x1 << 3)
#define ADXDMA_SENSOR_ALL_ALARMS     (ADXDMA_SENSOR_UNDER_CRITICAL | ADXDMA_SENSOR_UNDER_WARNING | ADXDMA_SENSOR_OVER_WARNING | ADXDMA_SENSOR_OVER_CRITICAL)

/* Flags for ADXDMA_GetClockFrequency & ADXDMA_SetClockFrequency */
#define ADXDMA_CLOCK_NONVOLATILE     (0x1 << 31)  /* Gets/sets nonvolatile frequency without changing current frequency */

#endif
