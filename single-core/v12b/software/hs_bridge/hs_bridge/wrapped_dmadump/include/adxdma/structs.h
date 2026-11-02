#ifndef _ALPHADATA_ADXDMA_STRUCTS_H
#define _ALPHADATA_ADXDMA_STRUCTS_H

/*
** structs.h - structs used in ADXDMA API
**
** (C) Copyright Alpha Data 2017
**
** _ADXDMA_UINT* types must be defined (somehow) prior to #include'ing this file.
*/

#include <adxdma/types.h>

/*
** Completion information structure, used by:
**
** o ADXDMA_ReadDMA*, ADXDMA_WriteDMA*
*/
typedef struct _ADXDMA_COMPLETION {
  size_t        Transferred; /* Number of bytes successfully transferred */
  ADXDMA_STATUS Reason;      /* Reason for not transferring all requested bytes */
} ADXDMA_COMPLETION;

/*
** Device information structure, returned by ADXDMA_GetDeviceInfo
*/

typedef struct _ADXDMA_PCI_ID {
  _ADXDMA_UINT16 Vendor;
  _ADXDMA_UINT16 Device;
  _ADXDMA_UINT16 SubsystemVendor;
  _ADXDMA_UINT16 SubsystemDevice;
  _ADXDMA_UINT8  Revision;
  _ADXDMA_UINT8  ClassMajor;
  _ADXDMA_UINT8  ClassMinor;
  _ADXDMA_UINT8  ProgrammingInterface;
} ADXDMA_PCI_ID;

typedef struct _ADXDMA_PCI_LOCATION {
  _ADXDMA_UINT16 Domain;
  _ADXDMA_UINT8  Bus;
  _ADXDMA_UINT8  Slot;
  _ADXDMA_UINT8  Function;
} ADXDMA_PCI_LOCATION;

typedef struct _ADXDMA_DEVICE_INFO {
  unsigned int        NumWindow;
  unsigned int        ControlWindowIndex;
  unsigned int        NumH2C;
  unsigned int        NumC2H;
  unsigned int        NumUserInterrupt;
  unsigned int        NumMSIVector;
  ADXDMA_PCI_ID       HardwareID;
  ADXDMA_PCI_LOCATION Location;
} ADXDMA_DEVICE_INFO;

typedef struct _ADXDMA_DMA_ENGINE_INFO {
  _ADXDMA_BOOL       IsH2C;
  _ADXDMA_BOOL       IsStream;
  unsigned int       Index;
  unsigned int       AddressAlignment;
  unsigned int       LengthGranularity;
  unsigned int       AddressBits;
} ADXDMA_DMA_ENGINE_INFO;

/*
** API information structure, returned by ADXDMA_GetAPIInfo
*/

typedef struct _ADXDMA_API_INFO {
  /* <adxdma.h> version against which the API library binary was built */
  struct {
    _ADXDMA_UINT16 Super;
    _ADXDMA_UINT16 Major;
    _ADXDMA_UINT16 Minor;
  } HeaderVersion;
  /* API library binary version */
  struct {
    _ADXDMA_UINT16 Major;
    _ADXDMA_UINT16 Minor;
    _ADXDMA_UINT16 Bugfix;
  } BinaryVersion;
} ADXDMA_API_INFO;

/*
** Driver information structure, returned by ADXDMA_GetDriverInfo
*/

typedef struct _ADXDMA_DRIVER_INFO {
  /* <adxdma.h> version against which the Kernel-mode driver binary was built */
  struct {
    _ADXDMA_UINT16 Super;
    _ADXDMA_UINT16 Major;
    _ADXDMA_UINT16 Minor;
  } HeaderVersion;
  /* Kernel-mode driver binary version */
  struct {
    _ADXDMA_UINT16 Major;
    _ADXDMA_UINT16 Minor;
    _ADXDMA_UINT16 Bugfix;
  } BinaryVersion;
} ADXDMA_DRIVER_INFO;

/*
** Window information structure, returned by ADXDMA_GetWindowInfo
*/

typedef struct _ADXDMA_WINDOW_INFO {
  _ADXDMA_UINT64 BusSize;     /* Size of BAR in bytes on I/O bus (i.e. in PCIe memory space) */
  _ADXDMA_UINT64 BusBase;     /* Base address of BAR on I/O bus (i.e. in PCIe memory space) */
  _ADXDMA_UINT64 VirtualSize; /* Size of BAR when mapped into a process' virtual address space */
  _ADXDMA_UINT32 Flags;       /* See ADXDMA_WINDOW_* values in <adxdma/types.h> */
} ADXDMA_WINDOW_INFO;

/*
** Window policy structure, used by ADXDMA_GetWindowPolicy & ADXDMA_SetWindowPolicy
*/

typedef struct _ADXDMA_WINDOW_POLICY {
  /* Preferred sizes: 1 => 8 bits, 2 => 16 bits, 4 => 32 bits, 8 => 64 bits */
  /* In a 32-bit OS, a value of 8 produces identical results to those of a value of 4. */
  _ADXDMA_UINT8 PreferredReadSize;  /* Preferred word size of reads from device memory, used for ReadFile/ReadFileEx only */
  _ADXDMA_UINT8 PreferredWriteSize; /* Preferred word size of writes to device memory, used for WriteFile/WriteFileEx only */
} ADXDMA_WINDOW_POLICY;

static const ADXDMA_WINDOW_POLICY ADXDMA_WINDOW_POLICY_DEFAULT = { 4, 4 };

/*
** Per-DMA engine queue configuration structure, used by ADXDMA_GetDMAQConfig & ADXDMA_SetDMAQConfig
*/

typedef struct _ADXDMA_DMAQ_CONFIG {
  _ADXDMA_UINT32   ValidFlags;     /* Indicates which of below members are valid */
  _ADXDMA_UINT32   MaxOutstanding; /* Maximum number of DMA transactions queued/executing for this DMA engine (0 => no limit) */
  _ADXDMA_UINT32   TestMode;       /* Reserved for use by Alpha Data for test purposes; must be 0 for normal operation */
} ADXDMA_DMAQ_CONFIG;

static const ADXDMA_DMAQ_CONFIG ADXDMA_DMAQ_CONFIG_DEFAULT = {
  ADXDMA_DMAQ_VALID_ALL,
  0,
  0
};

#ifdef _WIN32
/*
** State structure for a DMA engine & its queue.
** Used by Alpha Data for development and debugging.
*/

typedef struct _ADXDMA_DMA_DEBUG_STATE {
  LONG ClientCount;

  BOOL IsH2C;
  UINT8 EngineIndex;

  BOOL UseCompletionCountBuffer;

  UINT8 TestMode;

  UINT32 NumDescriptor;
  UINT32 NumDescriptorBlock;

  UINT32 UserPauseCount;
  UINT32 SystemPauseCount;

  UINT32 UserStopHardwareCount;
  UINT32 SystemStopHardwareCount;

  UINT8 QueueState;

  UINT8 HardwareState;

  UINT8 CancelState;

  BOOL IsMapping;

  UINT32 MaxExecutingXaction;
  UINT32 NumExecutingXaction;
  UINT32 MaxOutstandingXaction;
  UINT32 NumOutstandingXaction;

  BOOL IsMappingQueueEmpty;
  BOOL IsCurrentMapXactionNull;
  BOOL IsCancelListEmpty;

  struct {
    UINT32 PagePtr;
    UINT32 ChunkPtr;
    UINT32 TotalDescriptors;
  } Map;

  struct {
    UINT32 PageCount;
    BOOL IsCompleted;
    BOOL IsTransactionNull;
    UINT64 RemoteAddress;
  } MapParam;

  struct {
    UINT32 PagePtr;
    UINT32 ChunkPtr;
    UINT32 TotalDescriptors;
  } Unmap;

  struct {
    UINT32 LastStatus;
    UINT32 LastDescCompletion;
    UINT32 InitialDescCount;
    UINT32 TotalDescCount;
  } TestMode0;

  struct {
    UINT32 TotalDescCount;
  } TestMode1;
} ADXDMA_DMA_DEBUG_STATE;
#endif

#endif
