#ifndef _ALPHADATA_ADXDMA_TYPES_H
#define _ALPHADATA_ADXDMA_TYPES_H

/*
** types.h - scalar datatypes used in ADXDMA API
**
** (C) Copyright Alpha Data 2017
*/


/* Flags for "Flags" member of ADXDMA_WINDOW_INFO. */
#define ADXDMA_WINDOW_PREFETCHABLE (0x8)

/* Flags for all API functions ADXDMA_DMA{Read,Write}* */
#define ADXDMA_DMA_FLAG_CONSTADDR (0x10000) /* Does not increment remote (AXI) address */

/* Flags for "ValidFlags" member of ADXDMA_DMAQ_CONFIG */
#define ADXDMA_DMAQ_VALID_MAXOUTSTANDING (0x1U << 0)
#define ADXDMA_DMAQ_VALID_TESTMODE       (0x1U << 1)
#define ADXDMA_DMAQ_VALID_ALL            (ADXDMA_DMAQ_VALID_MAXOUTSTANDING | ADXDMA_DMAQ_VALID_TESTMODE)

/* Flags for ADXDMA_Cancel* (but not ADXDMA_Cancel*Async) */
#define ADXDMA_CANCEL_OUTSTANDING  (1 << 0) /* Causes outstanding (uncompleted) operations to be aborted */
#define ADXDMA_CANCEL_SET_STICKY   (1 << 1) /* Mutually exclusive with ADXDMA_CANCEL_UNSET_STICKY */
#define ADXDMA_CANCEL_UNSET_STICKY (1 << 2) /* Mutually exclusive with ADXDMA_CANCEL_SET_STICKY */
#define ADXDMA_CANCEL_STICKY       (ADXDMA_CANCEL_OUTSTANDING | ADXDMA_CANCEL_SET_STICKY)

/* Values for "operation" argument of ADXDMA_ControlDMA */
typedef enum _ADXDMA_DMA_CONTROL_OP {
  ADXDMA_DMA_CONTROL_PAUSE_DMAQ  = 1,
  ADXDMA_DMA_CONTROL_RESUME_DMAQ = 2,
  ADXDMA_DMA_CONTROL_STOP_HW     = 3,
  ADXDMA_DMA_CONTROL_START_HW    = 4
} ADXDMA_DMA_CONTROL_OP;

/* Values for "operation" parameter of ADXDMA_ControlUserInt */
typedef enum _ADXDMA_USERINT_OP {
  ADXDMA_USERINT_OP_SET_ENABLE    = 0x10, /* Set some bits to 1 in User Interrupt Enable register in XDMA PCIe Endpoint */
  ADXDMA_USERINT_OP_CLEAR_ENABLE  = 0x11, /* Clear some bits to 0 in User Interrupt Enable register in XDMA PCIe Endpoint */
  ADXDMA_USERINT_OP_WRITE_ENABLE  = 0x12, /* Overwrite all bits in User Interrupt Enable register in XDMA PCIe Endpoint */
  ADXDMA_USERINT_OP_SET_PENDING   = 0x20, /* Set some bits to 1 in the pending vector of the ADXDMA Driver */
  ADXDMA_USERINT_OP_CLEAR_PENDING = 0x21, /* Clear some bits to 0 in the pending vector of the ADXDMA Driver */
  ADXDMA_USERINT_OP_WRITE_PENDING = 0x22  /* Overwrite all bits of the pending vector of the ADXDMA Driver */
} ADXDMA_USERINT_OP;

#if 0
/* Cooperation level, used by ADXDMA_Open */
/* In VxWorks kernel task (not RTP), ADXDMA_COOP_PROCESS_SHARED has same effect as ADXDMA_COOP_EXCLUSIVE */
typedef enum _ADXDMA_COOP_LEVEL {
  ADXDMA_COOP_SHARED         = 0,         /* Any security level; allows further opens */
  ADXDMA_COOP_PROCESS_SHARED = 1          /* Requires TRUSTED security level; prevents next open by a different process if next open security level != PASSIVE */
  ADXDMA_COOP_EXCLUSIVE      = 2          /* Requires TRUSTED security level; prevents next open if next open security level != PASSIVE */
  __ADXDMA_COOP_INT32        = 0x7FFFFFFF /* Ensure 32 bits */
} ADXDMA_COOP_LEVEL;
#endif

#endif
