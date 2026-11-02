#ifndef _ALPHADATA_ADXDMA_BC_PLATFORM_H
#define _ALPHADATA_ADXDMA_BC_PLATFORM_H

/*
** <adxdma/bc/platform.h> - Define platform-specific datatypes used by Board
**                          Control API functions in ADXDMA Driver.
**
** (C) Copyright Alpha Data 2017
**
** The integer datatypes defined below prefixed by "_ADXDMA_", such as
** "_ADXDMA_UINT64" are defined in order to increase the portability of
** this header file but should NOT be used by application code that
** makes use of the ADXDMA API.
*/

#if defined(_WIN32)

/* Windows */

/* Define ADXDMA_HDMA as a pointer to a struct to get benefits of static type checking */
struct _ADXDMA_HBC_STRUCT;
typedef struct _ADXDMA_HBC_STRUCT* ADXDMA_HBC;

/* This value is invalid for an ADXDMA_HDMA */
# define ADXDMA_NULL_HBC ((ADXDMA_HBC)NULL)

#elif defined(__linux) || defined(__VXWORKS__) || defined(__vxworks)

/* Linux or VxWorks - assume C99-compliant */

typedef int ADXDMA_HBC;

/* This value is invalid for an ADXDMA_HBC */ 
# define ADXDMA_NULL_HBC (-1)


#else

# error Cannot detect target operating system.

#endif

#endif
