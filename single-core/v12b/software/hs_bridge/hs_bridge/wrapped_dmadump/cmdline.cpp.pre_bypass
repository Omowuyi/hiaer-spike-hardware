/*
** cmdline.cpp
**
** Command-line argument handling for the adxdma_dmadump utility.
**
** Notes
** =====
**
** This source file contains the main() entry point for Linux & Windows,
** and should not be compiled for VxWorks.
*/

#ifdef _WIN32

# include <windows.h>
# include <tchar.h>

typedef UINT32 uint32_t;
# define my_aligned_alloc(alignment, size) _aligned_malloc(size, alignment)
# define my_aligned_free(p) _aligned_free(p)

#else

# include <stdint.h>
# include <stdbool.h>
# include <string.h>

# define _T(x) x
# define _tmain main
# define _tcsicmp strcasecmp
# define my_aligned_alloc(alignment, size) aligned_alloc(alignment, size)
# define my_aligned_free(p) free(p)

typedef char TCHAR;

#endif

#include <iostream>
#include <cstring>

#include <exappcmdline.h>

#include <adxdma.h>

//#include "adxdma_dmadump.h"

using namespace AlphaData::AppFramework;

#ifdef _UNICODE
typedef std::wstringstream SStreamType;
#define SSEMPTY(ss) ((ss).str(std::basic_string<wchar_t>()))
#else
typedef std::stringstream SStreamType;
#define SSEMPTY(ss) ((ss).str(std::string()))
#endif

//extern CExAppMessageDisplay g_messageDisplay;

/*class MyCmdLineArguments : public CExAppCmdLineArgs {
public:
  MyCmdLineArguments(int argc, TCHAR* argv[]) :
    CExAppCmdLineArgs(argc, argv),
    m_index(0U, _T("index"), _T("Zero-based index of ADXDMA device to use.")),
    m_dmaMethod(_T("normal"), _T("method"), _T("Method to use for DMA calls: normal, locked or native")),
    m_command(_T("command"), _T("Command, specifying read or write and word size. Must be one of: rb rw rd rq wb ww wd wq.")),
    m_engineIndex(_T("engine"), _T("Zero-based index of H2C/C2H DMA engine to use.")),
    m_address(_T("address"), _T("Remote address at which to begin reading or writing.")),
    m_readCount(_T("read-count"), _T("Number of bytes to read.")),
    m_writeValue(_T("write-value"), _T("A value to write (may be truncated to word size implied by command)."))
  {
    m_pass = 0;
    m_eDmaMethod = DmaMethodNormal;
    m_nWriteData = 0;

    AddOption(m_index);
    AddOption(m_dmaMethod);
    AddPositional(m_command);
    AddPositional(m_engineIndex);
    AddPositional(m_address);

    SetWarnExtraPositionals(false);
    SetNumRequiredPositionals(3);
  }

  virtual void OnParseComplete() {
    m_pass++;

    if (m_bHelpRequested) {
      return;
    }

    if (1 == m_pass) {
      if (_tcsicmp(m_command.GetValueString().c_str(), _T("rb")) == 0) {
        m_wordSize = 1;
        m_bWriteNotRead = false;
      } else if (_tcsicmp(m_command.GetValueString().c_str(), _T("rw")) == 0) {
        m_wordSize = 2;
        m_bWriteNotRead = false;
      } else if (_tcsicmp(m_command.GetValueString().c_str(), _T("rd")) == 0) {
        m_wordSize = 4;
        m_bWriteNotRead = false;
      } else if (_tcsicmp(m_command.GetValueString().c_str(), _T("rq")) == 0) {
        m_wordSize = 8;
        m_bWriteNotRead = false;
      } else if (_tcsicmp(m_command.GetValueString().c_str(), _T("wb")) == 0) {
        m_wordSize = 1;
        m_bWriteNotRead = true;
      } else if (_tcsicmp(m_command.GetValueString().c_str(), _T("ww")) == 0) {
        m_wordSize = 2;
        m_bWriteNotRead = true;
      } else if (_tcsicmp(m_command.GetValueString().c_str(), _T("wd")) == 0) {
        m_wordSize = 4;
        m_bWriteNotRead = true;
      } else if (_tcsicmp(m_command.GetValueString().c_str(), _T("wq")) == 0) {
        m_wordSize = 8;
        m_bWriteNotRead = true;
      } else {
        AddError(_T("Illegal command. Use adxdma_dmadump -h for help."));
        SetParseResult(ExAppParseResultBadValue);
      }

      if (_tcsicmp(_T("normal"), m_dmaMethod.GetValueString().c_str()) == 0) {
        m_eDmaMethod = DmaMethodNormal;
      } else if (_tcsicmp(_T("locked"), m_dmaMethod.GetValueString().c_str()) == 0) {
        m_eDmaMethod = DmaMethodLocked;
      } else if (_tcsicmp(_T("native"), m_dmaMethod.GetValueString().c_str()) == 0) {
        m_eDmaMethod = DmaMethodNative;
      } else {
        FormatError(_T("Invalid value '%s' for option '-%s'. Legal values are: normal, locked, native."),
          m_dmaMethod.GetValueString().c_str(), m_dmaMethod.GetName(0).c_str());
        SetParseResult(ExAppParseResultBadValue);
      }

      if (m_bWriteNotRead) {
        m_nWriteData = GetNumExtraPositional();

        if (m_nWriteData) {
          // If command is a write command and argument vector has additional positional items,
          // interpret them as write data value positionals for satisfying the requested byte count.
          for (size_t i = 0; i < m_nWriteData; i++) {
            CExAppPositionalUInt64* pNewPositional = new CExAppPositionalUInt64(_T("val"), _T("Write data item"));
            AddPositional(*pNewPositional);
          }

          // Request re-parsing, to get new positionals parsed.
          RequestParseAgain();
          return;
        }
      } else {
        AddPositional(m_readCount);
        SetNumRequiredPositionals(4);

        // Request re-parsing to get byte count positional parsed.
        RequestParseAgain();
        return;
      }
    }
  }

#ifdef _UNICODE
  virtual void DisplaySummary(OStreamType& ostream = std::wcout) {
#else
  virtual void DisplaySummary(OStreamType& ostream = std::cout) {
#endif
    m_bodyLayout.GetStream(0) << _T("This program permits reading or writing data using a particular C2H or H2C DMA Engine in an ADXDMA device.") << std::endl << std::endl;
    m_bodyLayout.Flush(ostream);
    CExAppCmdLineArgs::DisplaySummary(ostream);
  }
  
#ifdef _UNICODE
  virtual void DisplayForms(OStreamType& ostream = std::wcout) {
#else
  virtual void DisplayForms(OStreamType& ostream = std::cout) {
#endif
    m_bodyLayout.GetStream(0) << std::endl;
    m_bodyLayout.Flush(ostream);

    SStreamType& formColumn = m_formLayout.GetStream(1);

    formColumn << m_programName << _T(" [option ...]");
    formColumn << _T(" ") << m_command.GetName(0).c_str();
    formColumn << _T(" ") << m_engineIndex.GetName(0).c_str();
    formColumn << _T(" ") << m_address.GetName(0).c_str();
    formColumn << _T(" ") << m_readCount.GetName(0).c_str();
    formColumn << std::endl;
    m_formLayout.Flush(ostream);

    formColumn << m_programName << _T(" [option ...]");
    formColumn << _T(" ") << m_command.GetName(0).c_str();
    formColumn << _T(" ") << m_engineIndex.GetName(0).c_str();
    formColumn << _T(" ") << m_address.GetName(0).c_str();
    formColumn << _T(" ") << m_writeValue.GetName(0).c_str();
    formColumn << _T(" ...");
    formColumn << std::endl;
    m_formLayout.Flush(ostream);

    AddPositional(m_readCount);
    AddPositional(m_writeValue);
    SetNumRequiredPositionals(5);
  }

public:
  CExAppOptionUInt m_index;
  CExAppOptionStringDef m_dmaMethod;
  CExAppPositionalString m_command;
  CExAppPositionalUInt m_engineIndex;
  CExAppPositionalUInt64 m_address;
  CExAppPositionalUInt32 m_readCount;
  CExAppPositionalUInt64 m_writeValue; // Only used for displaying help
  unsigned int m_pass;
  unsigned int m_wordSize;
  bool m_bWriteNotRead;
  DmaMethod m_eDmaMethod;
  size_t m_nWriteData;
};*/

//int
//_tmain(
//  int argc, //argument count, number of strings pointed to by argv
//  TCHAR* argv[])//aray of strings
int dmadump(uint64_t data[], unsigned int dataElements, unsigned int dataStride, int m_bWriteNotRead, size_t m_nWriteData, unsigned int m_wordSize, unsigned int m_index,
      unsigned int m_engineIndex,
      uint64_t m_address,
      //uint32_t byteCount,//uint32_t
      DmaMethod m_eDmaMethod,
      unsigned int m_readCount      )
{
  int exitCode = ExitCodeSuccess;

  //cast all incoming python data to the correct type
  bool bWriteNotRead = (bool)m_bWriteNotRead;

  m_nWriteData = (size_t)dataElements; //number of elements to write is just equal to number of elements in data
  // Parse the command-line arguments; performs most of the required validation.
  //MyCmdLineArguments args(argc, argv); //initialize a CmdLineArguments object
  //args.SetMessageDisplay(&g_messageDisplay);//I doubt the message Display is super important
  //ExAppParseResult result = args.Parse();//python will be in charge of passing the parsed args
  //args.DisplayMessages();
  //if (ExAppParseResultOk != result) { //check args are good
  //  exitCode = args.GetExitCode();
  //  goto done;
  //}

  if (bWriteNotRead) { //bool to determine if we write instead of reading
    uint8_t* pBuffer = NULL;
    uint32_t byteCount;
    
    if (m_nWriteData == 0) {// number of arguments supplied as write data, bush this step to the python wrapper
      //replace this with a print
      //g_messageDisplay.FormatWarning(_T("No write data items passed on command line - nothing to do."));
      goto done;
    }

    byteCount = (uint32_t)(m_nWriteData * m_wordSize);//caluclate total bytes as product of number of write arguments and size per argument
    pBuffer = (uint8_t*)my_aligned_alloc(ADXDMA_DMA_BUFFER_ALIGNMENT, byteCount);
    if (NULL == pBuffer) {
      //g_messageDisplay.FormatError(_T("Failed to allocate buffer of %lu(0x%lX) byte(s) for assembling write values."),
      //  (unsigned long)byteCount, (unsigned long)byteCount);
      exitCode = ExitCodeBufferAllocFailed;
      goto done;
    }
    switch (m_wordSize) { //based off of word size assemble the write buffer
    case 1:
      for (size_t i = 0; i < m_nWriteData; i++) {
        //((uint8_t*)pBuffer)[i] = (uint8_t)args.GetPositional((unsigned int)i + 3).GetValueUInt64();
        ((uint8_t*)pBuffer)[i] = (uint8_t)data[i];
      }
      break;

    case 2:
      for (size_t i = 0; i < m_nWriteData; i++) {
        //((uint16_t*)pBuffer)[i] = (uint16_t)args.GetPositional((unsigned int)i + 3).GetValueUInt64();
        ((uint16_t*)pBuffer)[i] = (uint16_t)data[i];

      }
      break;

    case 4:
      for (size_t i = 0; i < m_nWriteData; i++) {
        //((uint32_t*)pBuffer)[i] = (uint32_t)args.GetPositional((unsigned int)i + 3).GetValueUInt64();
      }
      break;

    case 8:
      for (size_t i = 0; i < m_nWriteData; i++) {
        //((uint64_t*)pBuffer)[i] = args.GetPositional((unsigned int)i + 3).GetValueUInt64();
      }
      break;

    default:
      assert(0);
      break;
    }


    exitCode = adxdmaDMAWriteBuffer( //call the write command
      m_index, //unsigned int
      m_engineIndex,//unsigned int
      m_address,//uint64_t
      byteCount,//uint32_t
      m_eDmaMethod,//
      (void*)pBuffer);

    my_aligned_free(pBuffer);
  } else { //it's a read, so do the read
    //in the case of a read data will be where we write the read data to
    exitCode = adxdmaDMARead(
      m_index,
      m_engineIndex,
      m_address,
      m_readCount,
      m_wordSize,
      m_eDmaMethod,
      data,
      dataElements,
      dataStride);
  }

done:
  //args.DisplayMessages();
  return (int)exitCode;
}

int main(){
  std::cout << "Value of a is " << 2;
  return 1;
}
