#ifndef _ADATA_APP_FRAMEWORK_EXAPPMESSAGE_H
#define _ADATA_APP_FRAMEWORK_EXAPPMESSAGE_H

#ifdef _WIN32

# include <windows.h>
# include <tchar.h>

#elif defined(__linux)

# include <stdint.h>
# include <pthread.h>

#elif defined(__VXWORKS__) || defined(__vxworks)

# include <vxWorks.h>
# include <semLib.h>
# include <stdint.h>

#else

# error Cannot detect platform at compile-time. Build will likely fail.

#endif

#include <cassert>
#include <cfloat>
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstdarg>
#include <iomanip>
#include <iostream>
#include <string>
#include <sstream>
#include <vector>

#include <exapptermlayout.h>

namespace AlphaData {
namespace AppFramework {

enum ExAppSeverity {
  ExAppSeverityInfo = 0,
  ExAppSeverityWarning,
  ExAppSeverityError
};

class CExAppMessage {
public:
#ifdef _UNICODE
  typedef std::wstring StringType;
#else
  typedef std::string StringType;
#endif

public:
  CExAppMessage(const TCHAR* pText, ExAppSeverity severity = ExAppSeverityInfo) {
    m_text = pText;
    m_severity = severity;
  }

  virtual ~CExAppMessage() {
  }

  const StringType& GetText() const {
    return m_text;
  }

  ExAppSeverity GetSeverity() const {
    return m_severity;
  }

protected:
  StringType m_text;
  ExAppSeverity m_severity;
};

class CExAppMessageDisplay {
public:
#ifdef _UNICODE
  typedef std::wstring StringType;
  typedef std::wstringstream SStreamType;
  typedef std::basic_ostream<wchar_t> OStreamType;
#else
  typedef std::string StringType;
  typedef std::stringstream SStreamType;
  typedef std::ostream OStreamType;
#endif

public:
  CExAppMessageDisplay() :
    m_layout(3),
    m_logLayout(3),
#ifdef _UNICODE
    m_pOstream(&std::wcout)
#else
    m_pOstream(&std::cout)
#endif
  {
    m_pLogOstream = NULL;
    InitMutex();
    CExAppTermLayout& layout = GetLayout();
    layout.SetColumnWidth(0, 6);
    layout.SetColumnWidth(1, 1);
    layout.SetColumnWidth(2, CExAppTermLayout::GetTerminalWidth() - 6 - 1 - 1); // For columns 0 & 1 & leaving one char blank at edge of terminal
    m_bAutoFlush = true;
    CExAppTermLayout& logLayout = GetLogLayout();
    logLayout.SetColumnWidth(0, 6);
    logLayout.SetColumnWidth(1, 1);
    logLayout.SetColumnWidth(1, 1000000);
  }
  
  virtual ~CExAppMessageDisplay() {
    UninitMutex();
  }

  CExAppTermLayout& GetLayout() {
    return m_layout;
  }
  
  CExAppTermLayout& GetLogLayout() {
    return m_logLayout;
  }

  //
  // Displaying messages
  // Thread safe
  //

  void AddMessage(const TCHAR* pMessage, ExAppSeverity severity) {
    TakeMutex();
    CExAppMessage message(pMessage, severity);
    _LogMessage(message);
    m_messages.push_back(message);
    if (m_bAutoFlush) {
      _DisplayMessages();
    }
    ReleaseMutex();
  }

  void AddMessage(const StringType& message, ExAppSeverity severity) {
    AddMessage(message.c_str(), severity);
  }

  void FormatMessage(const TCHAR* pFormat, ExAppSeverity severity, ...) {
    TCHAR buf[1024];
    size_t n = sizeof(buf) / sizeof(buf[0]);
    va_list ap;

    va_start(ap, severity);
#ifdef _WIN32
    _vsntprintf_s(buf, n, pFormat, ap);
    buf[n - 1] = _T('\0');
#elif defined(__linux)
    vsnprintf(buf, sizeof(buf) / sizeof(buf[0]), pFormat, ap);
    buf[n - 1] = '\0';
#elif defined(__VXWORKS__) || defined(__vxworks)
    vsnprintf(buf, sizeof(buf) / sizeof(buf[0]), pFormat, ap);
    buf[n - 1] = '\0';
#endif
    va_end(ap);
    AddMessage(buf, severity);
  }

  void AddError(const TCHAR* pMessage) {
    AddMessage(pMessage, ExAppSeverityError);
  }

  void AddError(const StringType& message) {
    AddError(message.c_str());
  }

  void FormatError(const TCHAR* pFormat, ...) {
    TCHAR buf[1024];
    size_t n = sizeof(buf) / sizeof(buf[0]);
    va_list ap;

    va_start(ap, pFormat);
#ifdef _WIN32
    _vsntprintf_s(buf, n, pFormat, ap);
    buf[n - 1] = _T('\0');
#elif defined(__linux)
    vsnprintf(buf, sizeof(buf) / sizeof(buf[0]), pFormat, ap);
    buf[n - 1] = '\0';
#elif defined(__VXWORKS__) || defined(__vxworks)
    vsnprintf(buf, sizeof(buf) / sizeof(buf[0]), pFormat, ap);
    buf[n - 1] = '\0';
#endif
    va_end(ap);
    AddError(buf);
  }

  void AddInfo(const TCHAR* pMessage) {
    AddMessage(pMessage, ExAppSeverityInfo);
  }

  void AddInfo(const StringType& message) {
    AddInfo(message.c_str());
  }

  void FormatInfo(const TCHAR* pFormat, ...) {
    TCHAR buf[1024];
    size_t n = sizeof(buf) / sizeof(buf[0]);
    va_list ap;

    va_start(ap, pFormat);
#ifdef _WIN32
    _vsntprintf_s(buf, n, pFormat, ap);
    buf[n - 1] = _T('\0');
#elif defined(__linux)
    vsnprintf(buf, sizeof(buf) / sizeof(buf[0]), pFormat, ap);
    buf[n - 1] = '\0';
#elif defined(__VXWORKS__) || defined(__vxworks)
    vsnprintf(buf, sizeof(buf) / sizeof(buf[0]), pFormat, ap);
    buf[n - 1] = '\0';
#endif
    va_end(ap);
    AddInfo(buf);
  }

  void AddWarning(const TCHAR* pMessage) {
    AddMessage(pMessage, ExAppSeverityWarning);
  }

  void AddWarning(const StringType& message) {
    AddWarning(message.c_str());
  }

  void FormatWarning(const TCHAR* pFormat, ...) {
    TCHAR buf[1024];
    size_t n = sizeof(buf) / sizeof(buf[0]);
    va_list ap;

    va_start(ap, pFormat);
#ifdef _WIN32
    _vsntprintf_s(buf, n, pFormat, ap);
    buf[n - 1] = _T('\0');
#elif defined(__linux)
    vsnprintf(buf, sizeof(buf) / sizeof(buf[0]), pFormat, ap);
    buf[n - 1] = '\0';
#elif defined(__VXWORKS__) || defined(__vxworks)
    vsnprintf(buf, sizeof(buf) / sizeof(buf[0]), pFormat, ap);
    buf[n - 1] = '\0';
#endif
    va_end(ap);
    AddWarning(buf);
  }

  void ClearMessages() {
    TakeMutex();
    _ClearMessages();
    ReleaseMutex();
  }

  void DisplayMessages() {
    TakeMutex();
    _DisplayMessages();
    ReleaseMutex();
  }
  
#ifdef _UNICODE
  void SetStream(OStreamType& ostream = std::wcout) {
#else
  void SetStream(OStreamType& ostream = std::cout) {
#endif
    TakeMutex();
    m_pOstream = &ostream;
    ReleaseMutex();
  }

  OStreamType& GetStream() {
    return *m_pOstream;
  }

  void SetLogStream(OStreamType* pLogOstream) {
    TakeMutex();
    m_pLogOstream = pLogOstream;
    ReleaseMutex();
  }

  OStreamType* GetLogStream() {
    return m_pLogOstream;
  }

  // Not thread safe

  const std::vector<CExAppMessage>& GetMessages() const {
    return m_messages;
  }
  
  void SetAutoFlush(bool bAutoFlush) {
    m_bAutoFlush = bAutoFlush;
    if (m_bAutoFlush) {
      DisplayMessages();
    }
  }
  
  bool GetAutoFlush(void) {
    return m_bAutoFlush;
  }
  
protected:
  void InitMutex() {
#ifdef _WIN32
    m_hMutex = CreateMutex(NULL, FALSE, NULL);
    assert(NULL != m_hMutex);
#elif defined(__linux)
    int res = pthread_mutex_init(&m_mutex, NULL);
    assert(0 == res);
#elif defined(__VXWORKS__) || defined(__vxworks)
    m_mutexId = semMCreate(SEM_Q_FIFO);
    assert(NULL != m_mutexId);
#endif
  }

  void UninitMutex() {
#ifdef _WIN32
    if (NULL != m_hMutex) {
      CloseHandle(m_hMutex);
      m_hMutex = NULL;
    }
#elif defined(__linux)
    pthread_mutex_destroy(&m_mutex);
#elif defined(__VXWORKS__) || defined(__vxworks)
    semDelete(m_mutexId);
    m_mutexId = NULL;
#endif
  }

  void TakeMutex() {
#ifdef _WIN32
    DWORD dwRes = WaitForSingleObject(m_hMutex, INFINITE);
    assert(dwRes == WAIT_OBJECT_0);
#elif defined(__linux)
    int res = pthread_mutex_lock(&m_mutex);
    assert(0 == res);
#elif defined(__VXWORKS__) || defined(__vxworks)
    semTake(m_mutexId, WAIT_FOREVER);
#endif
  }

  void ReleaseMutex() {
#ifdef _WIN32
    BOOL bRes = ::ReleaseMutex(m_hMutex);
    assert(bRes);
#elif defined(__linux)
    int res = pthread_mutex_unlock(&m_mutex);
    assert(0 == res);
#elif defined(__VXWORKS__) || defined(__vxworks)
    semGive(m_mutexId);
#endif
  }

  void _ClearMessages() {
    m_messages.clear();
  }

  void _DisplayMessages() {
    SStreamType& severityColumn = m_layout.GetStream(0);
    SStreamType& messageColumn = m_layout.GetStream(2);
    for (std::vector<CExAppMessage>::const_iterator i = m_messages.begin(); i != m_messages.end(); i++) {
      switch (i->GetSeverity()) {
      case ExAppSeverityInfo:
        severityColumn << _T("INFO: ");
        break;

      case ExAppSeverityWarning:
        severityColumn << _T("WARN: ");
        break;

      case ExAppSeverityError:
        severityColumn << _T("ERROR:");
        break;

      default:
        assert(false);
        break;
      }
      messageColumn << i->GetText().c_str() << std::endl;
      m_layout.Flush(GetStream());
    }
    _ClearMessages();
  }

  void _LogMessage(CExAppMessage& message) {
    if (NULL != m_pLogOstream) {
      OStreamType& stream = *m_pLogOstream;
      switch (message.GetSeverity()) {
      case ExAppSeverityInfo:
        stream << _T("INFO:  ");
        break;

      case ExAppSeverityWarning:
        stream << _T("WARN:  ");
        break;

      case ExAppSeverityError:
        stream << _T("ERROR: ");
        break;

      default:
        assert(false);
        break;
      }
      stream << message.GetText().c_str() << std::endl;
    }
  }
  

protected:
  std::vector<CExAppMessage> m_messages;
  CExAppTermLayout m_layout;
  CExAppTermLayout m_logLayout;
  bool m_bAutoFlush;
  OStreamType* m_pOstream;
  OStreamType* m_pLogOstream;
#ifdef _WIN32
  HANDLE m_hMutex;
#elif defined(__linux)
  pthread_mutex_t m_mutex;
#elif defined(__VXWORKS__) || defined(__vxworks)
  SEM_ID m_mutexId;
#endif
};

} // end of namespace AppFramework
} // end of namespace AlphaData

#endif
