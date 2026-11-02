#ifndef _ADATA_APP_FRAMEWORK_EXAPPTERMLAYOUT_H
#define _ADATA_APP_FRAMEWORK_EXAPPTERMLAYOUT_H

#ifdef _WIN32

# include <windows.h>
# include <tchar.h>

#elif defined(__linux)

# include <sys/ioctl.h>
# include <unistd.h>

# define _T(x) x

#elif defined(__VXWORKS__) || defined(__vxworks)

# define _T(x) x

#else
  
# warning Cannot detect platform at compile-time. Build will probably fail.

#endif

#include <cassert>
#include <iomanip>
#include <iostream>
#include <string>
#include <sstream>
#include <vector>

namespace AlphaData {
namespace AppFramework {

class CExAppTermColumn {
public:
#ifdef _UNICODE
  typedef std::wstring StringType;
  typedef std::wstringstream SStreamType;
#else
  typedef std::string StringType;
  typedef std::stringstream SStreamType;
#endif
  typedef unsigned int uint;

  CExAppTermColumn() {
    m_width = 0U;
    m_spaceCharacters = _T(" \t\n");
    m_bCollapseSpace = true;
  }

  SStreamType& GetStream() {
    return m_text;
  }

  uint GetWidth() const {
    return m_width;
  }

  void SetWidth(uint width) {
    m_width = width;
  }

  const StringType& GetSpaceCharacters() const {
    return m_spaceCharacters;
  }

  void SetSpaceCharacters(const TCHAR* pSpaceCharacters) {
    m_spaceCharacters = pSpaceCharacters;
  }

  const bool GetCollapseSpace() const {
    return m_bCollapseSpace;
  }

  void SetCollapseSpace(bool bCollapseSpace) {
    m_bCollapseSpace = bCollapseSpace;
  }

protected:
  virtual ~CExAppTermColumn() {
  }

protected:
  SStreamType m_text;
  StringType m_spaceCharacters;
  uint m_width;
  bool m_bCollapseSpace;
};

class CExAppTermLayout {
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
  typedef unsigned int uint;

public:
  // Returns width of visible terminal window, in characters
  static uint GetTerminalWidth(bool bQuiet = false) {
#ifdef _WIN32
    HANDLE hStdout = GetStdHandle(STD_OUTPUT_HANDLE);
    CONSOLE_SCREEN_BUFFER_INFO csbiInfo; 
    if (!GetConsoleScreenBufferInfo(hStdout, &csbiInfo))  {
      if (!bQuiet) {
        SStreamType ss;
        DWORD dwLastError = GetLastError();
        ss << _T("GetConsoleScreenBufferInfo failed, GetLastError returned 0x") << std::hex << dwLastError << std::endl;
        OutputDebugString(ss.str().c_str());
      }
    }
    if (csbiInfo.dwSize.X < 0) {
      return 0U;
    }
    return (uint)csbiInfo.dwSize.X;
#elif defined(__linux)
    struct winsize w;
    if (0 != ioctl(STDOUT_FILENO, TIOCGWINSZ, &w)) {
      return 0U;
    }
    if (w.ws_col < 0) {
      return 0U;
    }
    return (uint)w.ws_col;
#else
    /* For other platforms, assume 80 characters. */
    return 80U;
#endif
  }

public:
  CExAppTermLayout(uint nColumn = 1U) :
    m_column(nColumn)
  {
    ResetColumns();
  }
  
  virtual ~CExAppTermLayout() {
  }

  uint GetNumColumn() const {
    return (uint)m_column.size();
  }

  void SetNumColumn(uint nColumn) {
    m_column.resize(nColumn);
  }

  uint GetColumnWidth(uint column) const {
    return m_column[column].GetWidth();
  }

  void SetColumnWidth(uint column, uint width) {
    if (column < m_column.size()) {
      m_column[column].SetWidth(width);
    }
  }

  SStreamType& GetStream(uint column) {
    if (column < m_column.size()) {
      return m_column[column].GetStream();
    } else {
      return m_column[0].GetStream();
    }
  }

  CExAppTermColumn& GetColumn(uint column) {
    if (column < m_column.size()) {
      return m_column[column];
    } else {
      return m_column[0];
    }
  }

  CExAppTermColumn& operator [] (uint column) {
    return GetColumn(column);
  }

#ifdef _UNICODE
  void Flush(OStreamType& ostream = std::wcout) {
#else
  void Flush(OStreamType& ostream = std::cout) {
#endif
    uint nColumn = (uint)m_column.size();
    bool bWork;
    do {
      bWork = false;
      m_line.str(_T(""));
      for (uint i = 0; i < nColumn; i++) {
        CExAppTermColumnPrivate& column = m_column[i];
        const TCHAR* pSpaceChars = column.GetSpaceCharacters().c_str();
        bool bCollapseSpace = column.GetCollapseSpace();
        uint width = column.GetWidth();
        uint position = column.GetPosition();
        const StringType text = column.GetStream().str();
        size_t length = text.length();
        bool bLastColumn = (i + 1 == nColumn);

        if (0U == width) {
          // Skip zero-width columns
          break;
        }

        if (position != length) {
          // We still have work to do
          bWork = true;
        }

        bool bLineDone = false;
        do {
          TCHAR c = (position < length) ? text[position] : _T('\0');
          if (c == _T('\0')) {
            // End of string, so pad out rest of column with spaces
            if (!bLastColumn) {
              while (width--) {
                m_line << _T(' ');
              }
            }
            bLineDone = true;
          } else if (c == _T('\n')) {
            // Newline, so pad out rest of column with spaces (unless last column)
            if (!bLastColumn) {
              while (width--) {
                m_line << _T(' ');
              }
            }
            bLineDone = true;
            position++;
          } else if (IsSpaceCharacter(pSpaceChars, c)) {
            if (bCollapseSpace) {
              // More space, so skip it
              position++;
            } else {
              if (width) {
                m_line << text[position++];
                width--;
              } else {
                bLineDone = true;
              }
            }
          } else {
            // Look ahead to next non-word character
            size_t wordEnd = text.find_first_of((const TCHAR*)pSpaceChars, position);
            if (std::string::npos == wordEnd) {
              // There is no next non-word character, so use end of string
              wordEnd = length;
            }
            if (wordEnd - position > width) {
              // This word would overflow the column
              if (wordEnd - position > column.GetWidth()) {
                // This word is wider than a column, so print as much of it as we can in this column (and go to next line)
                while (width--) {
                  m_line << text[position++];
                }
              } else {
                // This word will fit into column if we go to next line.
                wordEnd = position + width;
                if (!bLastColumn) {
                  while (width--) {
                    m_line << _T(' ');
                  }
                }
              }
              bLineDone = true;
            } else {
              // We can print this whole word without going to the next line
              while (position < wordEnd) {
                m_line << text[position++];
                width--;
              }
              if (bCollapseSpace) {
                if (width) {
                  // Add a space after word, if not already at end of column
                  m_line << _T(' ');
                  width--;
                }
              }
            }
          }
        } while (!bLineDone);
        column.SetPosition(position);
      }
      if (bWork) {
        ostream << m_line.str() << std::endl;
      }
    } while (bWork);
    ResetColumns();
  }

protected:
  void ResetColumns() {
    for (std::vector<CExAppTermColumnPrivate>::iterator i = m_column.begin(); i != m_column.end(); i++) {
      i->Reset();
    }
  }

  static bool IsSpaceCharacter(const TCHAR* pSpaceCharacters, TCHAR c) {
    TCHAR spaceChar;

    assert(_T('\0') != c);

    do {
      spaceChar = *pSpaceCharacters++;
      if (c == spaceChar) {
        return true;
      }
    } while (spaceChar != _T('\0'));

    return false;
  }

protected:
  class CExAppTermColumnPrivate : public CExAppTermColumn {
  public:
    CExAppTermColumnPrivate() {
      m_position = 0U;
    }

    // Copy constructor to keep members of type SStreamType happy
    CExAppTermColumnPrivate(const CExAppTermColumnPrivate& column) {
      *this = column;
    }

    // Assignment operator overload to keep members of type SStreamType happy
    CExAppTermColumnPrivate& operator = (const CExAppTermColumnPrivate& column) {
      m_text.str(column.m_text.str());
      m_width = column.m_width;
      m_position = column.m_position;
      return *this;
    }

    virtual ~CExAppTermColumnPrivate() {
    }

    void Reset() {
      m_position = 0U;
      m_text.str(_T(""));
    }

    uint GetPosition() const {
      return m_position;
    }

    void SetPosition(uint position) {
      m_position = position;
    }

  protected:
    uint m_position;
  };

protected:
  std::vector<CExAppTermColumnPrivate> m_column;
  SStreamType m_line;
};

} // end of namespace AppFramework
} // end of namespace AlphaData

#endif
