#ifndef _ADATA_APP_FRAMEWORK_EXAPPTHREAD_H
#define _ADATA_APP_FRAMEWORK_EXAPPTHREAD_H

#ifdef _WIN32

# include <windows.h>

# include <cassert>

namespace AlphaData {
namespace AppFramework {

class CExAppThread {
public:
  CExAppThread() {
    m_bRunning = false;
    m_hThread = CreateThread(NULL, 0, ThreadStub, this, CREATE_SUSPENDED, &m_hThreadId);
  }

  ~CExAppThread() {
    if (IsValid()) {
      if (IsRunning()) {
        TerminateThread(m_hThread, 0);
        Join();
      }
      CloseHandle(m_hThread);
      m_hThread = NULL;
    }
  }

  bool IsValid() {
    return m_hThread != NULL;
  }

  bool IsRunning() {
    return m_bRunning;
  }

  void Start() {
    assert(!IsRunning());
    assert(IsValid());
    m_bRunning = true;
    ResumeThread(m_hThread);
  }

  void* Join() {
    IsValid();
    WaitForSingleObject(m_hThread, INFINITE);
    m_bRunning = false;
    return m_pExitCode;
  }

  void* GetExitCode() {
    assert(!IsRunning());
    return m_pExitCode;
  }

protected:
  static DWORD WINAPI ThreadStub(void* pContext) {
    CExAppThread* pThread = static_cast<CExAppThread*>(pContext);
    pThread->m_pExitCode = pThread->ThreadFunction();
    return 0;
  }

  virtual void* ThreadFunction() = 0;

protected:
  bool m_bRunning;
  HANDLE m_hThread;
  DWORD m_hThreadId;
  void* m_pExitCode;
};

} // end of namespace AppFramework
} // end of namespace AlphaData

#elif defined(__linux)

# include <stdint.h>
# include <pthread.h>
# include <semaphore.h>

namespace AlphaData {
namespace AppFramework {

class CExAppThread {
public:
  CExAppThread() {
    m_bRunning = false;
    m_bValid = false;
    if (0 != sem_init(&m_runSem, 0, 0)) {
      return;
    }
    if (0 != pthread_create(&m_thread, NULL, ThreadStub, this)) {
      sem_destroy(&m_runSem);
      return;
    }
    m_bValid = true;
  }

  ~CExAppThread() {
    if (IsValid()) {
      if (IsRunning()) {
        pthread_cancel(m_thread);
        Join();
      }
      sem_destroy(&m_runSem);
      m_bValid = false;
    }
  }

  bool IsValid() {
    return m_bValid;
  }

  bool IsRunning() {
    return m_bRunning;
  }

  void Start() {
    assert(!IsRunning());
    assert(IsValid());
    m_bRunning = true;
    sem_post(&m_runSem);
  }

  void* Join() {
    IsValid();
    pthread_join(m_thread, &m_pExitCode);
    m_bRunning = false;
    return m_pExitCode;
  }

  void* GetExitCode() {
    assert(!IsRunning());
    return m_pExitCode;
  }

protected:
  static void* ThreadStub(void* pContext) {
    CExAppThread* pThread = static_cast<CExAppThread*>(pContext);
    sem_wait(&pThread->m_runSem);
    return pThread->ThreadFunction();
  }

  virtual void* ThreadFunction() = 0;

protected:
  bool m_bValid;
  bool m_bRunning;
  sem_t m_runSem;
  pthread_t m_thread;
  void* m_pExitCode;
};

} // end of namespace AppFramework
} // end of namespace AlphaData

#elif defined(__VXWORKS__) || defined(__vxworks)

# include <vxWorks.h>
# include <taskLib.h>

namespace AlphaData {
namespace AppFramework {

#if (_WRS_VXWORKS_MAJOR > 6) || (_WRS_VXWORKS_MAJOR == 6 && _WRS_VXWORKS_MINOR >= 9)
# define EXAPPTHREAD_HAS_VX_USR_ARG_T (1)
# define EXAPPTHREAD_HAS_TASK_ID (1)
#else
# define EXAPPTHREAD_HAS_VX_USR_ARG_T (0)
# define EXAPPTHREAD_HAS_TASK_ID (0)
#endif

#define EXAPPTHREAD_STACKSIZE_DEFAULT (0x10000)

class CExAppThread {
public:
  CExAppThread(int stackSize = EXAPPTHREAD_STACKSIZE_DEFAULT) {
    m_bRunning = false;
    m_sem = semBCreate(SEM_Q_FIFO, SEM_EMPTY);
    int priority;
    taskPriorityGet(taskIdSelf(), &priority);
    m_taskId = taskSpawn(
      NULL,
      priority,
      VX_FP_TASK,
      stackSize,
      (FUNCPTR)ThreadStub, 
#if EXAPPTHREAD_HAS_VX_USR_ARG_T
      (_Vx_usr_arg_t)this,
      (_Vx_usr_arg_t)0,
      (_Vx_usr_arg_t)0,
      (_Vx_usr_arg_t)0,
      (_Vx_usr_arg_t)0,
      (_Vx_usr_arg_t)0,
      (_Vx_usr_arg_t)0,
      (_Vx_usr_arg_t)0,
      (_Vx_usr_arg_t)0,
      (_Vx_usr_arg_t)0);
#else
      (int)this,
      (int)0,
      (int)0,
      (int)0,
      (int)0,
      (int)0,
      (int)0,
      (int)0,
      (int)0,
      (int)0);
#endif
  }

  ~CExAppThread() {
    if (IsValid()) {
      if (IsRunning()) {
        Join();
      }
      taskDelete(m_taskId);
    }
  }

  bool IsValid() {
#if EXAPPTHREAD_HAS_TASK_ID
    return (m_taskId != (TASK_ID)ERROR);
#else
    return (m_taskId != ERROR);
#endif
  }

  bool IsRunning() {
    return m_bRunning;
  }

  void Start() {
    assert(!IsRunning());
    assert(IsValid());
    semGive(m_sem);
    m_bRunning = true;
  }

  void* Join() {
    IsValid();
    semTake(m_sem, WAIT_FOREVER);
    m_bRunning = false;
    taskDelete(m_taskId);
#if EXAPPTHREAD_HAS_TASK_ID
    m_taskId = (TASK_ID)ERROR;
#else
    m_taskId = ERROR;
#endif
    return m_pExitCode;
  }

  void* GetExitCode() {
    assert(!IsRunning());
    return m_pExitCode;
  }

protected:
  static void* ThreadStub(
#if EXAPPTHREAD_HAS_VX_USR_ARG_T
    _Vx_usr_arg_t arg1,
    _Vx_usr_arg_t arg2,
    _Vx_usr_arg_t arg3,
    _Vx_usr_arg_t arg4,
    _Vx_usr_arg_t arg5,
    _Vx_usr_arg_t arg6,
    _Vx_usr_arg_t arg7,
    _Vx_usr_arg_t arg8,
    _Vx_usr_arg_t arg9,
    _Vx_usr_arg_t arg10)
#else
    int arg1,
    int arg2,
    int arg3,
    int arg4,
    int arg5,
    int arg6,
    int arg7,
    int arg8,
    int arg9,
    int arg10)
#endif
  {
    CExAppThread* pThread = (CExAppThread*)arg1;
    semTake(pThread->m_sem, WAIT_FOREVER);
    pThread->m_pExitCode = pThread->ThreadFunction();
    semGive(pThread->m_sem);
    return 0;
  }

  virtual void* ThreadFunction() = 0;

protected:
  bool m_bRunning;
  void* m_pExitCode;
  SEM_ID m_sem;
#if EXAPPTHREAD_HAS_TASK_ID
  TASK_ID m_taskId;
#else
  int m_taskId;
#endif
};

} // end of namespace AppFramework
} // end of namespace AlphaData

#else
  
# error Cannot detect platform at compile-time. Build will fail.

#endif

#endif
