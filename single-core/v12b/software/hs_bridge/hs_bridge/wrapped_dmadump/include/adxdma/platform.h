#ifndef _ALPHADATA_ADXDMA_PLATFORM_H
#define _ALPHADATA_ADXDMA_PLATFORM_H

/*
** platform.h - define elementary datatypes used by API
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

#if defined(_MSC_VER)
/* MSVC */
typedef INT16  _ADXDMA_INT16;
typedef UINT16 _ADXDMA_UINT16;
typedef UINT8  _ADXDMA_UINT8;
#else
/* Not MSVC, use C99 header */
#include <stdint.h>
typedef int16_t  _ADXDMA_INT16;
typedef uint16_t _ADXDMA_UINT16;
typedef uint8_t  _ADXDMA_UINT8;
#endif
typedef INT64  _ADXDMA_INT64;
typedef INT32  _ADXDMA_INT32;
typedef UINT64 _ADXDMA_UINT64;
typedef UINT32 _ADXDMA_UINT32;
typedef BYTE   _ADXDMA_BYTE;
typedef BOOL   _ADXDMA_BOOL;

/* Define ADXDMA_HDEVICE as a pointer to a struct to get benefits of static type checking */
struct _ADXDMA_HDEVICE_STRUCT;
typedef struct _ADXDMA_HDEVICE_STRUCT* ADXDMA_HDEVICE;

/* This value is invalid for an ADXDMA_HDEVICE */ 
# define ADXDMA_NULL_HDEVICE ((ADXDMA_HDEVICE)NULL)

/* Define ADXDMA_HDMA as a pointer to a struct to get benefits of static type checking */
struct _ADXDMA_HDMA_STRUCT;
typedef struct _ADXDMA_HDMA_STRUCT* ADXDMA_HDMA;

/* This value is invalid for an ADXDMA_HDMA */
# define ADXDMA_NULL_HDMA ((ADXDMA_HDMA)NULL)

/* Define ADXDMA_HWINDOW as a pointer to a struct to get benefits of static type checking */
struct _ADXDMA_HWINDOW_STRUCT;
typedef struct _ADXDMA_HWINDOW_STRUCT* ADXDMA_HWINDOW;

/* This value is invalid for an ADXDMA_HUSERINT */
# define ADXDMA_NULL_HWINDOW ((ADXDMA_HWINDOW)NULL)

/* Define ADXDMA_HUSERINT as a pointer to a struct to get benefits of static type checking */
struct _ADXDMA_HUSERINT_STRUCT;
typedef struct _ADXDMA_HUSERINT_STRUCT* ADXDMA_HUSERINT;

/* This value is invalid for an ADXDMA_HWINDOW */
# define ADXDMA_NULL_HUSERINT ((ADXDMA_HUSERINT)NULL)

/* Define ADXDMA_HBUFFER as typedef of 32-bit unsigned integer. */
typedef UINT32 ADXDMA_HBUFFER;

/* Invalid value for ADXDMA_HBUFFER */
#define ADXDMA_NULL_HBUFFER ((ADXDMA_HBUFFER)0)

/* Value for timeout parameter that means "wait for ever" */
#define ADXDMA_WAIT_FOREVER (INFINITE)

#elif defined(__linux) || defined(__VXWORKS__) || defined(__vxworks)

/* Linux or VxWorks - assume C99-compliant */

# if defined(__linux)
#   include <stdint.h>
# endif

typedef int64_t  _ADXDMA_INT64;
typedef int32_t  _ADXDMA_INT32;
typedef int16_t  _ADXDMA_INT16;
typedef uint64_t _ADXDMA_UINT64;
typedef uint32_t _ADXDMA_UINT32;
typedef uint16_t _ADXDMA_UINT16;
typedef uint8_t  _ADXDMA_UINT8;
typedef uint8_t  _ADXDMA_BYTE;
typedef int      _ADXDMA_BOOL;

typedef int ADXDMA_HDEVICE;

/* This value is invalid for an ADXDMA_HDEVICE */ 
# define ADXDMA_NULL_HDEVICE (-1)

typedef int ADXDMA_HDMA;

/* This value is invalid for an ADXDMA_HDMA */
# define ADXDMA_NULL_HDMA (-1)

typedef int ADXDMA_HWINDOW;

/* This value is invalid for an ADXDMA_HWINDOW */
# define ADXDMA_NULL_HWINDOW (-1)

typedef int ADXDMA_HUSERINT;

/* This value is invalid for an ADXDMA_HUSERINT */
# define ADXDMA_NULL_HUSERINT (-1)

/* Define ADXDMA_HBUFFER as typedef of 32-bit unsigned integer. */
typedef uint32_t ADXDMA_HBUFFER;

/* Invalid value for ADXDMA_HBUFFER */
#define ADXDMA_NULL_HBUFFER ((ADXDMA_HBUFFER)0)

/* Value for timeout parameter that means "wait for ever" */
#define ADXDMA_WAIT_FOREVER ((uint32_t)0xFFFFFFFF)

#else

# error Cannot detect target operating system.

#endif

#endif
