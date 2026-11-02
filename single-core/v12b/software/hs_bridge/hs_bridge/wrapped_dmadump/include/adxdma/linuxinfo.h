#ifndef _ALPHADATA_ADXDMA_LINUXINFO_H
#define _ALPHADATA_ADXDMA_LINUXINFO_H

/*
** <adxdma/linuxinfo.h> - Functions related to Linux device model
**
** The functions defined in this header file are not for use in applications.
**
** (C) Copyright 2018 Alpha Data
*/

#ifdef __cplusplus
extern "C" {
#endif

/* handleInfo[0] is zero-based Device index */
/* handleInfo[1] is file object ID */
ADXDMA_EXPORT ADXDMA_STATUS
ADXDMA_CALLING_CONVENTION
ADXDMA_GetLinuxHandleInfo(
  int      hDevice, /* Any ADXDMA_*_HANDLE type */
  uint32_t handleInfo[2]);

#ifdef __cplusplus
}
#endif

#endif
