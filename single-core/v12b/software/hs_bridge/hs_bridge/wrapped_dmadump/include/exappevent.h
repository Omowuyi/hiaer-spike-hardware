#ifndef _ADATA_APP_FRAMEWORK_EXAPPEVENT_H
#define _ADATA_APP_FRAMEWORK_EXAPPEVENT_H

#ifdef _WIN32

# include <windows.h>

# include <cassert>

namespace AlphaData {
namespace AppFramework {

class CExAppEvent {
public:
  CExAppEvent() {
    m_hEvent = CreateEvent(NULL, FALSE, FALSE, NULL);
  }

  ~CExAppEvent() {
    if (IsValid()) {
      CloseHandle(m_hEvent);
      m_hEvent = NULL;
    }
  }

  bool IsValid() {
    return m_hEvent != NULL;
  }

  void Set() {
    assert(IsValid());
    SetEvent(m_hEvent);
  }

  void Wait() {
    assert(IsValid());
    WaitForSingleObject(m_hEvent, INFINITE);
  }

protected:
  HANDLE m_hEvent;
};

} // end of namespace AppFramework
} // end of namespace AlphaData

#elif defined(__linux)

# include <stdint.h>
# include <semaphore.h>

namespace AlphaData {
namespace AppFramework {

class CExAppEvent {
public:
  CExAppEvent() {
    m_bValid = 0;
    if (0 == sem_init(&m_sem, 0, 0)) {
      m_bValid = true;
    }
  }

  ~CExAppEvent() {
    if (IsValid()) {
      sem_destroy(&m_sem);
      m_bValid = false;
    }
  }

  bool IsValid() {
    return m_bValid;
  }

  void Set() {
    assert(IsValid());
    sem_post(&m_sem);
  }

  void Wait() {
    assert(IsValid());
    sem_wait(&m_sem);
  }

protected:
  sem_t m_sem;
  bool m_bValid;
};

} // end of namespace AppFramework
} // end of namespace AlphaData

#elif defined(__VXWORKS__) || defined(__vxworks)

# include <vxWorks.h>
# include <semLib.h>

# include <assert.h>

namespace AlphaData {
namespace AppFramework {

class CExAppEvent {
public:
  CExAppEvent() {
    m_semId = semBCreate(SEM_Q_FIFO, SEM_EMPTY);
  }

  ~CExAppEvent() {
    semDelete(m_semId);
    m_semId = NULL;
  }

  bool IsValid() {
    return (m_semId != NULL);
  }

  void Set() {
    assert(IsValid());
    semGive(m_semId);
  }

  void Wait() {
    assert(IsValid());
    semTake(m_semId, WAIT_FOREVER);
  }

protected:
  SEM_ID m_semId;
};

} // end of namespace AppFramework
} // end of namespace AlphaData

#else
  
# error Cannot detect platform at compile-time. Build will fail.

#endif

#endif
