#ifndef _ALPHADATA_ADXDMA_STATUS_H
#define _ALPHADATA_ADXDMA_STATUS_H

/*
** status.h - status codes returned by ADXDMA API calls
**
** (C) Copyright Alpha Data 2017
*/

/*
** Base value for success status codes
*/
#define ADXDMA_STATUS_SUCCESS_CODE_START ((ADXDMA_STATUS)0)

/*
** Base value for error status codes
*/
#define ADXDMA_STATUS_ERROR_CODE_START ((ADXDMA_STATUS)0x100)

/*
** Base value for user-defined error codes.
** Can be passed to ADXDMA_Cancel* functions (except ADXDMA_Cancel*Async)
** via completionStatus parameter.
*/
#define ADXDMA_STATUS_USER_ERROR_CODE_START ((ADXDMA_STATUS)0x200)

/* Maximum allowed value for a user-defined error code */
#define ADXDMA_STATUS_USER_ERROR_CODE_END   ((ADXDMA_STATUS)0xFFFF)

/*
** Macro that returns TRUE if an ADXDMA_STATUS value indicates success (or partial success).
*/
#define ADXDMA_IS_ERROR(status) ((status) >= ADXDMA_STATUS_ERROR_CODE_START)

/*
** Status and error codes
*/
typedef enum _ADXDMA_STATUS
{
    /* Operation completed without error. */
    ADXDMA_SUCCESS                 = 0x0,

    /* Asynchronous operation started without error. */
    ADXDMA_STARTED                 = 0x1,

    /* Operation transferred some, but not all of the requested bytes. */
    ADXDMA_TRUNCATED               = 0x2,

    /* An error in the API logic was detected */
    ADXDMA_INTERNAL_ERROR          = 0x100,

    /* An unexpected error caused the operation to fail */
    ADXDMA_UNEXPECTED_ERROR        = 0x101,

    /* The driver might not be correctly installed */
    ADXDMA_BAD_DRIVER              = 0x102,

    /* Couldn't allocate memory required to complete operation */
    ADXDMA_NO_MEMORY               = 0x103,

    /* The calling process does not have permission to perform the operation */
    ADXDMA_ACCESS_DENIED           = 0x104,

    /* Failed to open the device with the specified index */
    ADXDMA_DEVICE_NOT_FOUND        = 0x105,

    /* The operation was aborted due to software-requested cancellation */
    ADXDMA_CANCELLED               = 0x106,

    /* The operation failed due to an error in the hardware */
    ADXDMA_HARDWARE_ERROR          = 0x107,

    /* The operation was aborted the hardware being reset */
    ADXDMA_HARDWARE_RESET          = 0x108,

    /* The operation was aborted due to a hardware power-down event */
    ADXDMA_HARDWARE_POWER_DOWN     = 0x109,

    /* The primary parameter to the function was invalid */
    ADXDMA_INVALID_PARAMETER       = 0x10A,

    /* A flag was invalid or not recognized */
    ADXDMA_INVALID_FLAG            = 0x10B,

    /* The device handle was invalid */
    ADXDMA_INVALID_HANDLE          = 0x10C,

    /* The index parameter was invalid */
    ADXDMA_INVALID_INDEX           = 0x10D,

    /* A NULL pointer was passed where non-NULL was required */
    ADXDMA_NULL_POINTER            = 0x10E,

    /* The hardware or the ADXDMA driver does not support the requested operation */
    ADXDMA_NOT_SUPPORTED           = 0x10F,

    /* The wrong kind of handle was supplied for an API function (e.g. a Window handle passed instead of a Device handle, or vice versa) */
    ADXDMA_WRONG_HANDLE_TYPE       = 0x110,

    /* The user-supplied timeout value was exceeded */
    ADXDMA_TIMEOUT_EXPIRED         = 0x111,

    /* At least one bit in the sensitivity parameter refers to a non-existent User Interrupt */
    ADXDMA_INVALID_SENSITIVITY     = 0x112,

    /* The virtual base address to be unmapped from the process' address space was not recognized */
    ADXDMA_INVALID_MAPPING         = 0x113,

    /* The word size specified was not valid */
    ADXDMA_INVALID_WORD_SIZE       = 0x114,

    /* The requested region was partially or completely out of bounds */
    ADXDMA_INVALID_REGION          = 0x115,

    /* The requested region exceeded a system-imposed limit */
    ADXDMA_REGION_OS_LIMIT         = 0x116,

    /* The limit on the number of locked buffers has been reached */
    ADXDMA_LOCK_LIMIT              = 0x117,

    /* An invalid locked buffer handle was supplied */
    ADXDMA_INVALID_BUFFER_HANDLE   = 0x118,

    /* Attempt to unlock a buffer owned by a different device handle */
    ADXDMA_NOT_BUFFER_OWNER        = 0x119,

    /* Attempt to change DMA queue configuration when it was not idle */
    ADXDMA_DMAQ_NOT_IDLE           = 0x11A,

    /* Invalid DMA Queue mode requested */
    ADXDMA_INVALID_DMAQ_MODE       = 0x11B,

    /* Maximum outstanding DMA transfer count reached */
    ADXDMA_DMAQ_OUTSTANDING_LIMIT  = 0x11C,

    /* Invalid address alignment, or length is not an integer multiple of length granularity */
    ADXDMA_INVALID_DMA_ALIGNMENT   = 0x11D,

    /* At least one Window mapping exists, preventing safe reset */
    ADXDMA_EXISTING_MAPPING        = 0x11E,

    /* Currently not used */
    ADXDMA_ALREADY_CANCELLING      = 0x11F,

    /* Attempting to perform an operation while there is already one in progress */
    ADXDMA_DEVICE_BUSY             = 0x120,

    /* Attempting to join a non-existent operation */
    ADXDMA_DEVICE_IDLE             = 0x121,

    ADXDMA_STATUS_FORCE32BITS = 0x7FFFFFFF
} ADXDMA_STATUS;

#endif
