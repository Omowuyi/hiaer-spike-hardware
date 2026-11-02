#ifdef CMDLINE_H_
#define CMDLINE_H_

//#include <exappcmdline.h>

//#include <adxdma.h>

//#include "adxdma_dmadump.h"


int dmadump(uint64_t data[], unsigned int dataElements, unsigned int dataStride, int m_bWriteNotRead, size_t m_nWriteData, unsigned int m_wordSize, unsigned int m_index,
      unsigned int m_engineIndex,
      uint64_t m_address,
      //uint32_t byteCount,//uint32_t
      DmaMethod m_eDmaMethod,
      unsigned int m_readCount);
#endif
