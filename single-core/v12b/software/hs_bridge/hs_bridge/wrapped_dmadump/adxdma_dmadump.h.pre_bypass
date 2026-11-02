#ifndef _ALPHADATA_ADXDMA_DMADUMP_H
#define _ALPHADATA_ADXDMA_DMADUMP_H

enum ExitCode {
  ExitCodeSuccess = 0,
  ExitCodeCannotOpenIndex      = 100,
  ExitCodeCannotOpenDMAEngine  = 101,
  ExitCodeNoSuchDMAEngine      = 102,
  ExitCodeNoSuchDMAMethod      = 103,
  ExitCodeBufferAllocFailed    = 104,
  ExitCodeBufferLockFailed     = 105,
  ExitCodeDMAReadFailed        = 106,
  ExitCodeDMAWriteFailed       = 107
};

enum DmaMethod {
  DmaMethodNormal = 0, /* Use ADXDMA_DMA{Read,Write} */
  DmaMethodLocked = 1, /* Use ADXDMA_DMA{Read,Write}Locked */
  DmaMethodNative = 2  /* Use OS-specific read or write functions */
};

/* When XDMA IP is configured for AXI stream interface, source, destination
** and length must be integral multiple of AXI width, in bytes. Since the
** maximum possible AXI width is 128 bytes, we align DMA buffers to this
** boundary in case the XDMA IP is configured for AXI stream interface. */
#define ADXDMA_DMA_BUFFER_ALIGNMENT (0x80)

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__VXWORKS__) || defined(__vxworks)

int /* ExitCode */
adxdmaDMAReadB( /* Entry point in VxWorks */
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  DmaMethod       method);

int /* ExitCode */
adxdmaDMAReadW( /* Entry point in VxWorks */
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  DmaMethod       method);

int /* ExitCode */
adxdmaDMAReadD( /* Entry point in VxWorks */
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  ReadWriteMethod method);

int /* ExitCode */
adxdmaDMAReadQ( /* Entry point in VxWorks */
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  DmaMethod       method);

#endif
 
int /* ExitCode */
adxdmaDMARead( /* Entry point in VxWorks */
  unsigned int deviceIndex,
  unsigned int engineIndex,
  uint64_t     address,
  uint32_t     readCount,
  unsigned int wordSize,
  DmaMethod    dmaMethod,
  uint64_t data[],
  unsigned int dataElements,
  unsigned int dataStride);

#if defined(__VXWORKS__) || defined(__vxworks)

int /* ExitCode */
adxdmaWriteB( /* Entry point in VxWorks */
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  DmaMethod       method,
  ...);

int /* ExitCode */
adxdmaWriteW( /* Entry point in VxWorks */
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  DmaMethod       method,
  ...);

int /* ExitCode */
adxdmaWriteD( /* Entry point in VxWorks */
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  DmaMethod       method,
  ...);

int /* ExitCode */
adxdmaWriteQ( /* Entry point in VxWorks */
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  DmaMethod       method,
  ...);

#endif

int /* ExitCode */
adxdmaDMAWriteBuffer(
  unsigned int    deviceIndex,
  unsigned int    engineIndex,
  uint64_t        address,
  uint32_t        byteCount,
  DmaMethod       method,
  const void*     pBuffer);

#ifdef __cplusplus
}
#endif

#endif
