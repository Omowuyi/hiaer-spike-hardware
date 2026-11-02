#ifndef _ADATA_APP_FRAMEWORK_EXAPPNUMPARSE_H
#define _ADATA_APP_FRAMEWORK_EXAPPNUMPARSE_H

#ifdef _WIN32
# include <windows.h>
# include <tchar.h>
#else
# include <stdint.h>
#endif

#include <cassert>
#include <cfloat>
#include <climits>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <string>
#include <sstream>
#include <vector>

namespace AlphaData {
namespace AppFramework {

class CExAppNumParse {
public:
#ifdef _UNICODE
  typedef std::wstring StringType;
#else
  typedef std::string StringType;
#endif
  typedef int Int;
  typedef unsigned int UInt;
  typedef float Float;
  typedef double Double;
#ifdef _WIN32
  typedef INT32 Int32;
  typedef INT64 Int64;
  typedef UINT32 UInt32;
  typedef UINT64 UInt64;
#else
  typedef int32_t Int32;
  typedef int64_t Int64;
  typedef uint32_t UInt32;
  typedef uint64_t UInt64;
  typedef char TCHAR;
#endif

public:
  static bool IsANumber(const StringType& str, bool bAllowHex) {
    StringType trimmed = Trim(str);
    size_t length = trimmed.length();
    if (0 == length) {
      // Empty string after trimming cannot be a number
      return false;
    }
    size_t i = 0;
    if (trimmed[i] == _T('-') || trimmed[i] == _T('+')) {
      // Allow number starting with - or +
      i++;
      length--;
    }
    if (0 == length) {
      return false;
    }
    if (bAllowHex && (trimmed.find(_T("0x"), i) == i || trimmed.find(_T("0X"), i) == i)) {
      // Appears to be beginning of a hexadecimal number
      return true;
    }
    if (0 == length) {
      return false;
    }
    if (trimmed[i] >= _T('0') && trimmed[i] <= _T('9')) {
      // Appears to be beginning of a decimal or real number
      return true;
    }
    // Does not appear to be the beginning of a number
    return false;
  }

  static bool IsADecimalNumber(const StringType& str, bool bAllowSign) {
    StringType trimmed = Trim(str);
    size_t length = trimmed.length();
    if (0 == length) {
      // Empty string after trimming cannot be a number
      return false;
    }
    size_t i = 0;
    if (bAllowSign) {
      if (trimmed[i] == _T('-') || trimmed[i] == _T('+')) {
        // Allow number starting with - or +
        i++;
        length--;
      }
    }
    if (0 == length) {
      return false;
    }
    while (length) {
      if (!(trimmed[i] >= _T('0') && trimmed[i] <= _T('9'))) {
        // Not a decimal digit
        return false;
      }
      length--;
      i++;
    }

    // Is a decimal number
    return true;
  }

  static bool ParseUIntDec(const StringType& str, UInt& valueOut) {
    const UInt maxAccumDiv10 = UINT_MAX / 10U;
    if (str.length() == 0) {
      return false;
    }
    UInt accum = 0U;
    size_t n = str.length();
    unsigned int digit;
    for (size_t i = 0; i < n; i++) {
      TCHAR c = str[i];
      if (c >= _T('0') && c <= _T('9')) {
        digit = (unsigned int)(c - _T('0'));
      } else {
        // Not a decimal digit
        return false;
      }
      if (accum > maxAccumDiv10) {
        // Overflow will occur
        return false;
      }
      accum = accum * 10;
      UInt limit = UINT_MAX - accum;
      if (digit > limit) {
        // Overflow will occur
        return false;
      }
      accum += digit;
    }
    valueOut = accum;
    return true;
  }

  static bool ParseUIntDec32(const StringType& str, UInt32& valueOut) {
    const UInt32 max = 0xFFFFFFFFU;
    const UInt32 maxAccumDiv10 = 0xFFFFFFFFU / 10U;
    if (str.length() == 0) {
      return false;
    }
    UInt32 accum = 0U;
    size_t n = str.length();
    unsigned int digit;
    for (size_t i = 0; i < n; i++) {
      TCHAR c = str[i];
      if (c >= _T('0') && c <= _T('9')) {
        digit = (unsigned int)(c - _T('0'));
      } else {
        // Not a decimal digit
        return false;
      }
      if (accum > maxAccumDiv10) {
        // Overflow will occur
        return false;
      }
      accum = accum * 10;
      UInt32 limit = max - accum;
      if (digit > limit) {
        // Overflow will occur
        return false;
      }
      accum += digit;
    }
    valueOut = accum;
    return true;
  }

  static bool ParseUIntDec64(const StringType& str, UInt64& valueOut) {
    const UInt64 max = (UInt64)0xFFFFFFFFFFFFFFFFULL;
    const UInt64 maxAccumDiv10 = (UInt64)0xFFFFFFFFFFFFFFFFULL / 10U;
    if (str.length() == 0) {
      return false;
    }
    UInt64 accum = 0U;
    size_t n = str.length();
    unsigned int digit;
    for (size_t i = 0; i < n; i++) {
      TCHAR c = str[i];
      if (c >= _T('0') && c <= _T('9')) {
        digit = (unsigned int)(c - _T('0'));
      } else {
        // Not a decimal digit
        return false;
      }
      if (accum > maxAccumDiv10) {
        // Overflow will occur
        return false;
      }
      accum = accum * 10U;
      UInt64 limit = max - accum;
      if (digit > limit) {
        // Overflow will occur
        return false;
      }
      accum += digit;
    }
    valueOut = accum;
    return true;
  }

  static bool ParseUIntHex(const StringType& str, UInt& valueOut) {
    const UInt max = UINT_MAX;
    const UInt maxAccumDiv16 = UINT_MAX / 16U;
    if (str.length() == 0) {
      return false;
    }
    UInt accum = 0U;
    size_t n = str.length();
    for (size_t i = 0; i < n; i++) {
      TCHAR c = str[i];
      unsigned int digit;
      if (c == '_') {
        // Ignore underscores
        continue;
      } else if (c >= _T('0') && c <= _T('9')) {
        digit = (unsigned int)(c - _T('0'));
      } else if (c >= _T('a') && c <= _T('f')) {
        digit = (unsigned int)(c - _T('a')) + 10U;
      } else if (c >= _T('A') && c <= _T('F')) {
        digit = (unsigned int)(c - _T('A')) + 10U;
      } else {
        // Not a hexadecimal digit
        return false;
      }
      if (accum > maxAccumDiv16) {
        // Overflow will occur
        return false;
      }
      accum = accum << 4;
      UInt limit = max - accum;
      if (digit > limit) {
        // Overflow will occur
        return false;
      }
      accum += digit;
    }
    valueOut = accum;
    return true;
  }

  static bool ParseUIntHex32(const StringType& str, UInt32& valueOut) {
    if (str.length() == 0) {
      return false;
    }
    UInt32 accum = 0U;
    size_t n = str.length();
    for (size_t i = 0, numDigit = 0; i < n; i++) {
      TCHAR c = str[i];
      unsigned int digit;
      if (c == _T('_')) {
        // Ignore underscores
        continue;
      } else if (c >= _T('0') && c <= _T('9')) {
        digit = (unsigned int)(c - _T('0'));
      } else if (c >= _T('a') && c <= _T('f')) {
        digit = (unsigned int)(c - _T('a')) + 10U;
      } else if (c >= _T('A') && c <= _T('F')) {
        digit = (unsigned int)(c - _T('A')) + 10U;
      } else {
        // Not a hexadecimal digit
        return false;
      }
      if (numDigit >= 8) {
        // More than 8 hexadecimal characters will overflow 
        return false;
      }
      accum = (accum << 4) + digit;
      numDigit++;
    }
    valueOut = accum;
    return true;
  }

  static bool ParseUIntHex64(const StringType& str, UInt64& valueOut) {
    if (str.length() == 0) {
      return false;
    }
    UInt64 accum = 0U;
    size_t n = str.length();
    for (size_t i = 0, numDigit = 0; i < n; i++) {
      TCHAR c = str[i];
      unsigned int digit;
      if (c == '_') {
        // Ignore underscores
        continue;
      } else if (c >= _T('0') && c <= _T('9')) {
        digit = (unsigned int)(c - _T('0'));
      } else if (c >= _T('a') && c <= _T('f')) {
        digit = (unsigned int)(c - _T('a')) + 10U;
      } else if (c >= _T('A') && c <= _T('F')) {
        digit = (unsigned int)(c - _T('A')) + 10U;
      } else {
        // Not a hexadecimal digit
        return false;
      }
      if (numDigit >= 16) {
        // More than 16 hexadecimal characters will overflow 
        return false;
      }
      accum = (accum << 4) + digit;
      numDigit++;
    }
    valueOut = accum;
    return true;
  }

  static bool ParseUInt(const StringType& str, bool bAllowHex, UInt& valueOut) {
    if (str.length() == 0) {
      return false;
    }
    UInt valueUintTmp;
    if (bAllowHex && (str.find(_T("0x")) == 0 || str.find(_T("0X")) == 0)) {
      StringType trimmed = str.substr(2);
      if (!ParseUIntHex32(trimmed, valueUintTmp)) {
        return false;
      }
    } else {
      if (!ParseUIntDec(str, valueUintTmp)) {
        return false;
      }
    }
    valueOut = valueUintTmp;
    return true;
  }

  static bool ParseUInt32(const StringType& str, bool bAllowHex, UInt32& valueOut) {
    if (str.length() == 0) {
      return false;
    }
    UInt32 valueUintTmp;
    if (bAllowHex && (str.find(_T("0x")) == 0 || str.find(_T("0X")) == 0)) {
      StringType trimmed = str.substr(2);
      if (!ParseUIntHex32(trimmed, valueUintTmp)) {
        return false;
      }
    } else {
      if (!ParseUIntDec32(str, valueUintTmp)) {
        return false;
      }
    }
    valueOut = valueUintTmp;
    return true;
  }

  static bool ParseUInt64(const StringType& str, bool bAllowHex, UInt64& valueOut) {
    if (str.length() == 0) {
      return false;
    }
    UInt64 valueUintTmp;
    if (bAllowHex && (str.find(_T("0x")) == 0 || str.find(_T("0X")) == 0)) {
      StringType trimmed = str.substr(2);
      if (!ParseUIntHex64(trimmed, valueUintTmp)) {
        return false;
      }
    } else {
      if (!ParseUIntDec64(str, valueUintTmp)) {
        return false;
      }
    }
    valueOut = valueUintTmp;
    return true;
  }

  static bool ParseInt(const StringType& str, bool bAllowHex, Int& valueOut) {
    if (str.length() == 0) {
      return false;
    }
    bool bNegative = false;
    UInt valueUintTmp;
    StringType trimmed;
    if (str.find(_T("-")) == 0) {
      bNegative = true;
      trimmed = str.substr(1);
    } else if (str.find(_T("+")) == 0) {
      trimmed = str.substr(1);
    } else {
      trimmed = str;
    }
    if (!ParseUInt(trimmed, bAllowHex, valueUintTmp)) {
      return false;
    }
    if (bNegative) {
      assert(INT_MIN < 0);
      // This performs test (valueUintTmp > -INT_MIN) without integer overflow occurring.
      if (valueUintTmp > 0 && valueUintTmp - 1 > (UInt)-(INT_MIN + 1)) {
        return false;
      }
    } else {
      if (valueUintTmp > (UInt)INT_MAX) {
        return false;
      }
    }
    // This assumes 2's complement, which should be a pretty safe bet...
    valueOut = bNegative ? (Int)(~valueUintTmp + 1) : (Int)valueUintTmp;
    return true;
  }

  static bool ParseInt32(const StringType& str, bool bAllowHex, Int32& valueOut) {
    if (str.length() == 0) {
      return false;
    }
    bool bNegative = false;
    UInt32 valueUintTmp;
    StringType trimmed;
    if (str.find(_T("-")) == 0) {
      bNegative = true;
      trimmed = str.substr(1);
    } else if (str.find(_T("+")) == 0) {
      trimmed = str.substr(1);
    } else {
      trimmed = str;
    }
    if (!ParseUInt32(trimmed, bAllowHex, valueUintTmp)) {
      return false;
    }
    if (bNegative) {
      if (valueUintTmp > (UInt32)0x80000000U) {
        return false;
      }
    } else {
      if (valueUintTmp > (UInt32)0x7FFFFFFFU) {
        return false;
      }
    }
    // This assumes 2's complement, which should be a pretty safe bet...
    valueOut = bNegative ? (Int32)(~valueUintTmp + 1) : (Int32)valueUintTmp;
    return true;
  }

  static bool ParseInt64(const StringType& str, bool bAllowHex, Int64& valueOut) {
    if (str.length() == 0) {
      return false;
    }
    bool bNegative = false;
    UInt64 valueUintTmp;
    StringType trimmed;
    if (str.find(_T("-")) == 0) {
      bNegative = true;
      trimmed = str.substr(1);
    } else if (str.find(_T("+")) == 0) {
      trimmed = str.substr(1);
    } else {
      trimmed = str;
    }
    if (!ParseUInt64(trimmed, bAllowHex, valueUintTmp)) {
      return false;
    }
    if (bNegative) {
      if (valueUintTmp > (UInt64)0x8000000000000000ULL) {
        return false;
      }
    } else {
      if (valueUintTmp > (UInt64)0x7FFFFFFFFFFFFFFFULL) {
        return false;
      }
    }
    // This assumes 2's complement, which should be a pretty safe bet...
    valueOut = bNegative ? (Int64)(~valueUintTmp + 1) : (Int64)valueUintTmp;
    return true;
  }

  static bool ParseFloat(const StringType& str, Float& valueOut) {
    double tmp;
    if (!ParseDouble(str, tmp)) {
      return false;
    }
    if (tmp > FLT_MAX || tmp < FLT_MIN) {
      return false;
    }
    valueOut = (float)tmp;
    return true;
  }

  static bool ParseDouble(const StringType& str, Double& valueOut) {
    StringType whole, fraction, exponent;
    bool bHasFraction, bHasExponent;
    if (!SplitReal(str, whole, fraction, exponent, bHasFraction, bHasExponent)) {
      return false;
    }

    // Number looks OK. Use standard strtod () function to convert it.
#if _UNICODE
    valueOut = wcstod(str.c_str(), NULL);
#else
    valueOut = strtod(str.c_str(), NULL);
#endif
    return true;
  }

protected:
  static StringType Trim(const StringType& str) {
    StringType tmp = str;
    const TCHAR* pSpace = _T(" \t\f\v\n\r");
    size_t pos = tmp.find_first_not_of(pSpace);
    if (std::string::npos != pos) {
      tmp.erase(0, pos);
    }
    pos = tmp.find_last_not_of(pSpace);
    if (std::string::npos != pos) {
      tmp.erase(pos + 1);
    }
    return tmp;
  }

  static bool SplitReal(const StringType& str, StringType& whole, StringType& fraction, StringType& exponent, bool& bHasFraction, bool& bHasExponent) {
    if (str.length() == 0) {
      return false;
    }

    // Isolate mantissa and exponent
    StringType mantissa;
    size_t pos = str.find_first_of(_T("eE"));
    bHasExponent = false;
    if (std::string::npos == pos) {
      mantissa = str;
    } else {
      mantissa = str.substr(0, pos);
      exponent = str.substr(pos + 1);
      bHasExponent = true;
    }

    // Isolate whole and fractional parts
    bHasFraction = false;
    pos = mantissa.find_first_of(_T('.'));
    if (std::string::npos == pos) {
      whole = mantissa;
    } else {
      whole = mantissa.substr(0, pos);
      fraction = mantissa.substr(pos + 1);
      bHasFraction = true;
    }

    // Check that whole, fraction and exponent parts are all decimal numbers
    if (!IsADecimalNumber(whole, true) || (bHasFraction && !IsADecimalNumber(fraction, false)) || (bHasExponent && !IsADecimalNumber(exponent, true))) {
      return false;
    }

    // Number looks OK.
    return true;
  }
};

} // end of namespace AppFramework
} // end of namespace AlphaData

#endif
