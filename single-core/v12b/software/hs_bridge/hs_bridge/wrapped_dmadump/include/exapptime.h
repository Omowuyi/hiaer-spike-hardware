#ifndef _ADATA_APP_FRAMEWORK_EXAPPTIME_H
#define _ADATA_APP_FRAMEWORK_EXAPPTIME_H

#ifdef _WIN32

# include <windows.h>
# include <cmath>
# include <cassert>

namespace AlphaData {
namespace AppFramework {

class CExAppTime {
public:
  typedef DWORD OSTickType;
  typedef INT64 TickType;   // Use INT64 to allow negative time intervals

  CExAppTime() {
    m_ticks = 0;
  }

  CExAppTime(double seconds, bool bRoundUp = true) {
    if (bRoundUp) {
      m_ticks = (TickType)ceil(1000.0 * seconds);
    } else {
      m_ticks = (TickType)floor(1000.0 * seconds);
    }
  }

  CExAppTime(int seconds, unsigned int microseconds, bool bRoundUp = true) {
    assert(microseconds < 1000000U);
    m_ticks = (TickType)(seconds * 1000);
    if (bRoundUp) {
      m_ticks += (microseconds + 999) / 1000;
    } else {
      m_ticks += microseconds / 1000;
    }
  }

  CExAppTime(int seconds, bool /* bRoundUp */ = true) {
    m_ticks = (TickType)(seconds * 1000);
  }

  CExAppTime(const CExAppTime& time) {
    *this = time;
  }

  CExAppTime(OSTickType ticks) {
    m_ticks = (TickType)ticks;
  }

  CExAppTime(TickType ticks) {
    m_ticks = ticks;
  }

  CExAppTime& operator = (double seconds) {
    m_ticks = (TickType)ceil(1000.0 * seconds);
    return *this;
  }

  CExAppTime& operator = (int seconds) {
    m_ticks = seconds * 1000;
    return *this;
  }

  CExAppTime& operator = (const CExAppTime& time) {
    m_ticks = time.m_ticks;
    return *this;
  }

  static CExAppTime Now() {
    return CExAppTime(GetTickCount());
  }

  operator double() const {
    return (double)m_ticks * 1.0e-3;
  }

  // Returns OS-specific tick count
  OSTickType GetOSTicks() const {
    return (OSTickType)m_ticks;
  }

  TickType GetTicks() const {
    return m_ticks;
  }

  bool IsZero() const {
    return (0 == m_ticks);
  }

  CExAppTime Increment() const {
    return CExAppTime(m_ticks + 1);
  }

  static void Increment(CExAppTime& time) {
    time.m_ticks++;
  }

  CExAppTime Decrement() const {
    return CExAppTime(m_ticks - 1);
  }

  static void Decrement(CExAppTime& time) {
    time.m_ticks--;
  }

  bool operator > (const CExAppTime& time) const {
    return m_ticks > time.m_ticks;
  }

  bool operator >= (const CExAppTime& time) const {
    return m_ticks >= time.m_ticks;
  }

  bool operator < (const CExAppTime& time) const {
    return m_ticks < time.m_ticks;
  }

  bool operator <= (const CExAppTime& time) const {
    return m_ticks <= time.m_ticks;
  }

  bool operator == (const CExAppTime& time) const {
    return m_ticks == time.m_ticks;
  }

  bool operator != (const CExAppTime& time) const {
    return m_ticks != time.m_ticks;
  }

  CExAppTime operator - (const CExAppTime& time) const {
    return CExAppTime(m_ticks - time.m_ticks);
  }

  CExAppTime operator + (const CExAppTime& time) const {
    return CExAppTime(m_ticks + time.m_ticks);
  }

protected:
  TickType m_ticks;
};

} // end of namespace AppFramework
} // end of namespace AlphaData

#elif defined(__linux)

# include <stdint.h>
# include <sys/time.h>
# include <math.h>
# include <cassert>

namespace AlphaData {
namespace AppFramework {

class CExAppTime {
public:
  typedef struct timeval OSTickType;
  typedef OSTickType TickType;

  CExAppTime() {
    m_timeval.tv_sec = 0;
    m_timeval.tv_usec = 0;
  }

  CExAppTime(double seconds, bool bRoundUp = true) {
    int64_t us;
    if (bRoundUp) {
      us = (int64_t)ceil(seconds * 1.0e6);
    } else {
      us = (int64_t)floor(seconds * 1.0e6);
    }
    m_timeval.tv_sec = (time_t)(us / 1000000);
    m_timeval.tv_usec = (suseconds_t)(us % 1000000);
  }

  CExAppTime(int seconds, unsigned int microseconds, bool /* bRoundUp */ = true) {
    assert(microseconds < 1000000U);
    m_timeval.tv_sec = seconds;
    m_timeval.tv_usec = microseconds;
  }

  CExAppTime(int seconds, bool /* bRoundUp */ = true) {
    m_timeval.tv_sec = seconds;
    m_timeval.tv_usec = 0;
  }

  CExAppTime(const CExAppTime& time) {
    *this = time;
  }

  CExAppTime(struct timeval tv) { // Not portable, Linux only
    m_timeval = tv;
  }

  CExAppTime(time_t sec, suseconds_t usec) { // Not portable, Linux only
    m_timeval.tv_sec = sec;
    m_timeval.tv_usec = usec;
  }

  CExAppTime& operator = (double seconds) {
    int64_t us;
    us = (int64_t)ceil(seconds * 1.0e6);
    m_timeval.tv_sec = (time_t)(us / 1000000);
    m_timeval.tv_usec = (suseconds_t)(us % 1000000);
    return *this;
  }

  CExAppTime& operator = (int seconds) {
    m_timeval.tv_sec = seconds;
    m_timeval.tv_usec = 0;
    return *this;
  }

  CExAppTime& operator = (const CExAppTime& time) {
    m_timeval = time.m_timeval;
    return *this;
  }

  static CExAppTime Now() {
    struct timeval tv;
    int err = gettimeofday(&tv, NULL);
    assert(!err);
    return CExAppTime(tv);
  }

  operator double() const {
    return (double)m_timeval.tv_sec + (double)m_timeval.tv_usec * 1.0e-6;
  }

  // Returns OS-specific tick count
  OSTickType GetOSTicks() const {
    return (OSTickType)m_timeval;
  }

  TickType GetTicks() const {
    return m_timeval;
  }

  bool IsZero() const {
    return (0 == m_timeval.tv_sec && 0 == m_timeval.tv_usec);
  }

  CExAppTime Increment() const {
    suseconds_t usec = m_timeval.tv_usec + 1;
    time_t sec = m_timeval.tv_sec;
    if (usec >= 1000000) {
      usec = 0;
      sec++;
    }
    return CExAppTime(sec, usec);
  }

  static void Increment(CExAppTime& time) {
    suseconds_t usec = time.m_timeval.tv_usec + 1;
    if (usec >= 1000000) {
      usec = 0;
      time.m_timeval.tv_sec++;
    }
    time.m_timeval.tv_usec = usec;
  }

  CExAppTime Decrement() const {
    suseconds_t usec = m_timeval.tv_usec - 1;
    time_t sec = m_timeval.tv_sec;
    if (usec < 0) {
      usec = 999999;
      sec--;
    }
    return CExAppTime((unsigned int)sec, (unsigned int)usec);
  }

  static void Decrement(CExAppTime& time) {
    suseconds_t usec = time.m_timeval.tv_usec - 1;
    if (usec < 0) {
      usec = 999999;
      time.m_timeval.tv_sec--;
    }
    time.m_timeval.tv_usec = usec;
  }

  bool operator > (const CExAppTime& time) const {
    if (m_timeval.tv_sec > time.m_timeval.tv_sec) {
      return true;
    }
    if (m_timeval.tv_sec == time.m_timeval.tv_sec && m_timeval.tv_usec > time.m_timeval.tv_usec) {
      return true;
    }
    return false;
  }

  bool operator >= (const CExAppTime& time) const {
    if (m_timeval.tv_sec > time.m_timeval.tv_sec) {
      return true;
    }
    if (m_timeval.tv_sec == time.m_timeval.tv_sec && m_timeval.tv_usec >= time.m_timeval.tv_usec) {
      return true;
    }
    return false;
  }

  bool operator < (const CExAppTime& time) const {
    if (m_timeval.tv_sec < time.m_timeval.tv_sec) {
      return true;
    }
    if (m_timeval.tv_sec == time.m_timeval.tv_sec && m_timeval.tv_usec < time.m_timeval.tv_usec) {
      return true;
    }
    return false;
  }
  
  bool operator <= (const CExAppTime& time) const {
    if (m_timeval.tv_sec < time.m_timeval.tv_sec) {
      return true;
    }
    if (m_timeval.tv_sec == time.m_timeval.tv_sec && m_timeval.tv_usec <= time.m_timeval.tv_usec) {
      return true;
    }
    return false;
  }

  bool operator == (const CExAppTime& time) const {
    return m_timeval.tv_sec == time.m_timeval.tv_sec && m_timeval.tv_usec == time.m_timeval.tv_usec;
  }

  bool operator != (const CExAppTime& time) const {
    return m_timeval.tv_sec != time.m_timeval.tv_sec || m_timeval.tv_usec != time.m_timeval.tv_usec;
  }

  CExAppTime operator - (const CExAppTime& time) const {
    time_t tv_sec = m_timeval.tv_sec - time.m_timeval.tv_sec;
    suseconds_t tv_usec = m_timeval.tv_usec - time.m_timeval.tv_usec;
    if (tv_usec < 0) {
      tv_sec--;
      tv_usec += 1000000;
    }
    return CExAppTime(tv_sec, tv_usec);
  }

  CExAppTime& operator -= (const CExAppTime& time) {
    *this = *this - time;
    return *this;
  }

  CExAppTime operator + (const CExAppTime& time) const {
    time_t tv_sec = m_timeval.tv_sec + time.m_timeval.tv_sec;
    suseconds_t tv_usec = m_timeval.tv_usec + time.m_timeval.tv_usec;
    if (tv_usec >= 1000000) {
      tv_sec--;
      tv_usec -= 1000000;
    }
    return CExAppTime(tv_sec, tv_usec);
  }

  CExAppTime& operator += (const CExAppTime& time) {
    *this = *this + time;
    return *this;
  }

protected:
  struct timeval m_timeval;
};

} // end of namespace AppFramework
} // end of namespace AlphaData

#elif defined(__VXWORKS__) || defined(__vxworks)

# include <vxWorks.h>
# include <sysLib.h>
# include <tickLib.h>

# include <cassert>
# include <cmath>

namespace AlphaData {
namespace AppFramework {

static unsigned int g_exAppTickRate = 0;
static double g_exAppSecPerTick = 0.0;
static unsigned int g_exAppUsPerTick = 0;
static unsigned int g_exAppUsPerTickMinus1 = 0;

class CExAppTime {
public:
  typedef ULONG OSTickType;
  typedef INT64 TickType;   // Use INT64 to allow negative time intervals

  CExAppTime() {
    m_ticks = 0;
  }

  CExAppTime(double seconds, bool bRoundUp) {
    if (bRoundUp) {
      m_ticks = (TickType)ceil(seconds * (double)GetTickRate());
    } else {
      m_ticks = (TickType)floor(seconds * (double)GetTickRate());
    }
  }

  CExAppTime(int seconds, unsigned int microseconds, bool bRoundUp = true) {
    assert(microseconds < 1000000U);
    m_ticks = (TickType)seconds * GetTickRate();
    if (bRoundUp) {
      m_ticks += (microseconds + GetUsPerTickMinus1()) / GetUsPerTick();
    } else {
      m_ticks += microseconds / GetUsPerTick();
    }
  }

  CExAppTime(int seconds, bool /* bRoundUp */ = true) {
    m_ticks = (TickType)seconds * GetTickRate();
  }

  CExAppTime(const CExAppTime& time) {
    *this = time;
  }

  CExAppTime(OSTickType ticks) {
    m_ticks = (TickType)ticks;
  }

  CExAppTime(TickType ticks) {
    m_ticks = ticks;
  }

  CExAppTime& operator = (double seconds) {
    m_ticks = (TickType)ceil(seconds * (double)GetTickRate());
    return *this;
  }

  CExAppTime& operator = (int seconds) {
    m_ticks = (TickType)seconds * GetTickRate();
    return *this;
  }

  CExAppTime& operator = (const CExAppTime& time) {
    m_ticks = time.m_ticks;
    return *this;
  }

  static CExAppTime Now() {
    return CExAppTime((OSTickType)tickGet());
  }

  operator double() const {
    return (double)m_ticks * GetSecPerTick();
  }

  // Returns OS-specific tick count
  OSTickType GetOSTicks() const {
    return (OSTickType)m_ticks;
  }

  TickType GetTicks() const {
    return m_ticks;
  }

  bool IsZero() const {
    return (0 == m_ticks);
  }

  CExAppTime Increment() const {
    return CExAppTime(m_ticks + 1);
  }

  static void Increment(CExAppTime& time) {
    time.m_ticks++;
  }

  CExAppTime Decrement() const {
    return CExAppTime(m_ticks - 1);
  }

  static void Decrement(CExAppTime& time) {
    time.m_ticks--;
  }

  bool operator > (const CExAppTime& time) const {
    return m_ticks > time.m_ticks;
  }

  bool operator >= (const CExAppTime& time) const {
    return m_ticks >= time.m_ticks;
  }

  bool operator < (const CExAppTime& time) const {
    return m_ticks < time.m_ticks;
  }

  bool operator <= (const CExAppTime& time) const {
    return m_ticks <= time.m_ticks;
  }

  bool operator == (const CExAppTime& time) const {
    return m_ticks == time.m_ticks;
  }

  bool operator != (const CExAppTime& time) const {
    return m_ticks != time.m_ticks;
  }

  CExAppTime operator - (const CExAppTime& time) const {
    return CExAppTime(m_ticks - time.m_ticks);
  }

  CExAppTime operator + (const CExAppTime& time) const {
    return CExAppTime(m_ticks + time.m_ticks);
  }

protected:
  static void InitTickRate() {
    g_exAppTickRate = (unsigned int)sysClkRateGet();
    // We begin to lose accuracy in integer-based microsecond conversions if tick rate is too fast
    assert(g_exAppTickRate < 100000);
    g_exAppSecPerTick = 1.0 / (double)g_exAppTickRate;
    g_exAppUsPerTick = 1000000 / g_exAppTickRate;
    g_exAppUsPerTickMinus1 = g_exAppUsPerTick - 1;
  }
  
  unsigned int GetTickRate() const {
    if (0 == g_exAppTickRate) {
      InitTickRate();
    }
    return g_exAppTickRate;
  }
  
  double GetSecPerTick() const {
    if (0 == g_exAppTickRate) {
      InitTickRate();
    }
    return g_exAppSecPerTick;
  }
  
  unsigned int GetUsPerTick() const {
    if (0 == g_exAppTickRate) {
      InitTickRate();
    }
    return g_exAppUsPerTick;
  }
  
  unsigned int GetUsPerTickMinus1() const {
    if (0 == g_exAppTickRate) {
      InitTickRate();
    }
    return g_exAppUsPerTickMinus1;
  }
  
  TickType m_ticks;
};

} // end of namespace AppFramework
} // end of namespace AlphaData

#else
  
# error Cannot detect platform at compile-time. Build will fail.

#endif

#endif
