#ifndef _ADATA_APP_FRAMEWORK_EXAPPCMDLINE_H
#define _ADATA_APP_FRAMEWORK_EXAPPCMDLINE_H

#ifdef _WIN32
# include <windows.h>
# include <tchar.h>
#else
# include <stdint.h>
#endif

#include <cassert>
#include <cfloat>
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstdarg>
#include <iomanip>
#include <iostream>
#include <fstream>
#include <string>
#include <sstream>
#include <vector>

#include <exappnumparse.h>
#include <exapptermlayout.h>
#include <exappmessage.h>

namespace AlphaData {
namespace AppFramework {

enum ExAppValueType {
  ExAppValueTypeNone = 0,
  ExAppValueTypeBool,
  ExAppValueTypeInt,
  ExAppValueTypeInt32,
  ExAppValueTypeInt64,
  ExAppValueTypeUInt,
  ExAppValueTypeUInt32,
  ExAppValueTypeUInt64,
  ExAppValueTypeUIntHex,
  ExAppValueTypeUIntHex32,
  ExAppValueTypeUIntHex64,
  ExAppValueTypeFloat,
  ExAppValueTypeDouble,
  ExAppValueTypeString
};

enum ExAppParseResult {
  ExAppParseResultOk = 0,
  ExAppParseResultHelpOnly = 1,        // -h / -help /-? option was given
  ExAppParseResultUnrecognizedOption,  // An unrecognised option was given
  ExAppParseResultMissingValue,        // No value was given for an option that expects a value
  ExAppParseResultMissingPositional,   // A required positional argument was not given
  ExAppParseResultBadValue,            // A bad value was given for a positional or an option that expects a value
  ExAppParseResultMutuallyExclusive,   // Two options were given that cannot both be given
  ExAppParseResultOutOfRange           // A value was given that was outside of the permitted range
};

class CExAppCmdLineArgs;

class CExAppValue {
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
#endif

public:
  // Use CExAppIntValue constructor for CExAppValue(Int value)

  CExAppValue(Int32 value) {
    m_scalar.m_int32 = value;
  }
  
  CExAppValue(Int64 value) {
    m_scalar.m_int64 = value;
  }
  
  // Use CExAppUIntValue constructor for CExAppValue(UInt value)
  
  CExAppValue(UInt32 value) {
    m_scalar.m_uint32 = value;
  }
  
  CExAppValue(UInt64 value) {
    m_scalar.m_uint64 = value;
  }
  
  CExAppValue(bool value) {
    m_scalar.m_bool = value;
  }
  
  CExAppValue(float value) {
    m_scalar.m_float = value;
  }

  CExAppValue(double value) {
    m_scalar.m_double = value;
  }

  CExAppValue(const StringType& value) {
    m_string = value;
  }

  CExAppValue(const TCHAR* pValue) {
    m_string = pValue;
  }

  CExAppValue() {
  }
  
  union {
    bool m_bool;
    Int m_int;
    Int32 m_int32;
    Int64 m_int64;
    UInt m_uint;
    UInt32 m_uint32;
    UInt64 m_uint64;
    float m_float;
    double m_double;
  } m_scalar;
  StringType m_string;
};

class CExAppIntValue : public CExAppValue {
public:
  CExAppIntValue(Int value) {
    m_scalar.m_int = value;
  }
};

class CExAppUIntValue : public CExAppValue {
public:
  CExAppUIntValue(UInt value) {
    m_scalar.m_uint = value;
  }
};

class CExAppOption {
  friend class CExAppCmdLineArgs;

public:
#ifdef _UNICODE
  typedef std::wstring StringType;
  typedef std::wstringstream SStreamType;
#else
  typedef std::string StringType;
  typedef std::stringstream SStreamType;
#endif
  
public:
  CExAppOption(const TCHAR* pName, const TCHAR* pDescription = NULL) {
    Init();
    m_type = ExAppValueTypeNone;
    m_bHasDefault = false;
    m_names.push_back(pName);
    if (NULL != pDescription) {
      m_description = pDescription;
    }
  }
  
  CExAppOption(const TCHAR** ppNames, const TCHAR* pDescription = NULL) {
    Init();
    m_type = ExAppValueTypeNone;
    m_bHasDefault = false;
    while (NULL != *ppNames) {
      m_names.push_back(*ppNames);
      ppNames++;
    }
    if (NULL != pDescription) {
      m_description = pDescription;
    }
  }
  
  CExAppOption(ExAppValueType type, const TCHAR* pName, const TCHAR* pDescription = NULL) {
    Init();
    m_type = type;
    m_bHasDefault = false;
    m_names.push_back(pName);
    if (NULL != pDescription) {
      m_description = pDescription;
    }
  }
  
  CExAppOption(ExAppValueType type, const CExAppValue& def, const TCHAR* pName, const TCHAR* pDescription = NULL) {
    Init();
    m_type = type;
    m_bHasDefault = true;
    m_default = def;
    m_value = def;
    m_names.push_back(pName);
    if (NULL != pDescription) {
      m_description = pDescription;
    }
  }
  
  CExAppOption(ExAppValueType type, const TCHAR** ppNames, const TCHAR* pDescription = NULL) {
    Init();
    m_type = type;
    m_bHasDefault = false;
    while (NULL != *ppNames) {
      m_names.push_back(*ppNames);
      ppNames++;
    }
    if (NULL != pDescription) {
      m_description = pDescription;
    }
  }
  
  CExAppOption(ExAppValueType type, const CExAppValue& def, const TCHAR** ppNames, const TCHAR* pDescription = NULL) {
    Init();
    m_type = type;
    m_bHasDefault = true;
    m_default = def;
    m_value = def;
    while (NULL != *ppNames) {
      m_names.push_back(*ppNames);
      ppNames++;
    }
    if (NULL != pDescription) {
      m_description = pDescription;
    }
  }
  
  virtual ~CExAppOption() {
  }

  const StringType& GetName(size_t index) const {
    if (index >= m_names.size()) {
      return m_invalidIndexString;
    } else {
      return m_names[index];
    }
  }
  
  const std::vector<StringType>& GetNames() const {
    return m_names;
  }
  
  ExAppValueType GetType() const {
    return m_type;
  }
  
  const bool GetHasDefault() const {
    return m_bHasDefault;
  }

  const CExAppValue& GetDefault() const {
    return m_default;
  }

  const StringType& GetDescription() const {
    return m_description;
  }

  bool GetValueBool() const {
    assert(GetType() == ExAppValueTypeBool);
    assert(GetHasDefault() || IsSet());
    return m_value.m_scalar.m_bool;
  }
  
  CExAppValue::Int GetValueInt() const {
    assert(GetType() == ExAppValueTypeInt);
    assert(GetHasDefault() || IsSet());
    return m_value.m_scalar.m_int;
  }
  
  CExAppValue::Int32 GetValueInt32() const {
    assert(GetType() == ExAppValueTypeInt32);
    assert(GetHasDefault() || IsSet());
    return m_value.m_scalar.m_int32;
  }
  
  CExAppValue::Int64 GetValueInt64() const {
    assert(GetType() == ExAppValueTypeInt64);
    assert(GetHasDefault() || IsSet());
    return m_value.m_scalar.m_int64;
  }
  
  CExAppValue::UInt GetValueUInt() const {
    assert(GetType() == ExAppValueTypeUInt || GetType() == ExAppValueTypeUIntHex);
    assert(GetHasDefault() || IsSet());
    return m_value.m_scalar.m_uint;
  }
  
  CExAppValue::UInt32 GetValueUInt32() const {
    assert(GetType() == ExAppValueTypeUInt32 || GetType() == ExAppValueTypeUIntHex32);
    assert(GetHasDefault() || IsSet());
    return m_value.m_scalar.m_uint32;
  }
  
  CExAppValue::UInt64 GetValueUInt64() const {
    assert(GetType() == ExAppValueTypeUInt64 || GetType() == ExAppValueTypeUIntHex64);
    assert(GetHasDefault() || IsSet());
    return m_value.m_scalar.m_uint64;
  }
  
  CExAppValue::Float GetValueFloat() const {
    assert(GetType() == ExAppValueTypeFloat);
    assert(GetHasDefault() || IsSet());
    return m_value.m_scalar.m_float;
  }
  
  CExAppValue::Double GetValueDouble() const {
    assert(GetType() == ExAppValueTypeDouble);
    assert(GetHasDefault() || IsSet());
    return m_value.m_scalar.m_double;
  }
  
  const StringType& GetValueString() const {
    assert(GetType() == ExAppValueTypeString);
    assert(GetHasDefault() || IsSet());
    return m_value.m_string;
  }
  
  void SetValueNone() {
    assert(GetType() == ExAppValueTypeNone);
    m_bIsSet = true;
  }
  
  void SetValueBool(bool value) {
    assert(GetType() == ExAppValueTypeBool);
    m_value.m_scalar.m_bool = value;
    m_bIsSet = true;
  }
  
  void SetValueInt(CExAppValue::Int value) {
    assert(GetType() == ExAppValueTypeInt);
    m_value.m_scalar.m_int = value;
    m_bIsSet = true;
  }
  
  void SetValueInt32(CExAppValue::Int32 value) {
    assert(GetType() == ExAppValueTypeInt32);
    m_value.m_scalar.m_int32 = value;
    m_bIsSet = true;
  }
  
  void SetValueInt64(CExAppValue::Int64 value) {
    assert(GetType() == ExAppValueTypeInt64);
    m_value.m_scalar.m_int64 = value;
    m_bIsSet = true;
  }
  
  void SetValueUInt(CExAppValue::UInt value) {
    assert(GetType() == ExAppValueTypeUInt || GetType() == ExAppValueTypeUIntHex);
    m_value.m_scalar.m_uint = value;
    m_bIsSet = true;
  }
  
  void SetValueUInt32(CExAppValue::UInt32 value) {
    assert(GetType() == ExAppValueTypeUInt32 || GetType() == ExAppValueTypeUIntHex32);
    m_value.m_scalar.m_uint32 = value;
    m_bIsSet = true;
  }
  
  void SetValueUInt64(CExAppValue::UInt64 value) {
    assert(GetType() == ExAppValueTypeUInt64 || GetType() == ExAppValueTypeUIntHex64);
    m_value.m_scalar.m_uint64 = value;
    m_bIsSet = true;
  }
  
  void SetValueFloat(CExAppValue::Float value) {
    assert(GetType() == ExAppValueTypeFloat);
    m_value.m_scalar.m_float = value;
    m_bIsSet = true;
  }
  
  void SetValueDouble(CExAppValue::Double value) {
    assert(GetType() == ExAppValueTypeDouble);
    m_value.m_scalar.m_double = value;
    m_bIsSet = true;
  }
  
  void SetValueString(const StringType& value) {
    assert(GetType() == ExAppValueTypeString);
    m_value.m_string = value;
    m_bIsSet = true;
  }

  bool IsSet() const {
    return m_bIsSet;
  }
  
  bool IsValid() const {
    return m_bValidationResult;
  }
  
protected:
  void Init() {
    m_bIsSet = false;
    m_bValidationResult = true;
    m_invalidIndexString = _T("<INVALID INDEX>");
  }

  virtual bool Validate() {
    return true;
  }
  
  virtual bool OnComplete(CExAppCmdLineArgs& /* argsBase */) {
    return true;
  }
  
protected:
  StringType m_invalidIndexString;
  std::vector<StringType> m_names;
  StringType m_description;
  ExAppValueType m_type;
  bool m_bHasDefault;
  CExAppValue m_default;
  CExAppValue m_value;
  bool m_bIsSet;
  bool m_bValidationResult;
};

static bool CExAppOptionHelp_OnComplete(CExAppCmdLineArgs& args); // Forward reference

class CExAppOptionHelp : public CExAppOption {
public:
  CExAppOptionHelp() :
    CExAppOption(_T("h"), _T("Display this help."))
  {
    m_names.push_back(_T("help"));
    m_names.push_back(_T("?"));
  }

  virtual ~CExAppOptionHelp() {
  }

protected:
  virtual bool OnComplete(CExAppCmdLineArgs& args) {
    return CExAppOptionHelp_OnComplete(args);
  }
};

class CExAppOptionBool : public CExAppOption {
public:
  CExAppOptionBool(
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
    CExAppOption(ExAppValueTypeBool, pName, pDescription)
  {
  }
  
  CExAppOptionBool(
    bool def,
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
    CExAppOption(ExAppValueTypeBool, CExAppValue(def), pName, pDescription)
  {
  }
  
  CExAppOptionBool(
    const TCHAR** ppNames,
    const TCHAR* pDescription) :
      CExAppOption(ExAppValueTypeBool, ppNames, pDescription)
  {
  }

  CExAppOptionBool(
    bool def,
    const TCHAR** ppNames,
    const TCHAR* pDescription) :
      CExAppOption(ExAppValueTypeBool, CExAppValue(def), ppNames, pDescription)
  {
  }
};

class CExAppOptionInt : public CExAppOption {
public:
  CExAppOptionInt(
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeInt, pName, pDescription)
  {
  }
  
  CExAppOptionInt(
    CExAppValue::Int def,
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeInt, CExAppIntValue(def), pName, pDescription)
  {
  }
  
  CExAppOptionInt(
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeInt, ppNames, pDescription)
  {
  }
  CExAppOptionInt(
    CExAppValue::Int def,
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeInt, CExAppIntValue(def), ppNames, pDescription)
  {
  }
};

class CExAppOptionInt32 : public CExAppOption {
public:
  CExAppOptionInt32(
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeInt32, pName, pDescription)
  {
  }
  
  CExAppOptionInt32(
    CExAppValue::Int32 def,
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeInt32, CExAppValue(def), pName, pDescription)
  {
  }
  
  CExAppOptionInt32(
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeInt32, ppNames, pDescription)
  {
  }

  CExAppOptionInt32(
    CExAppValue::Int32 def,
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeInt32, CExAppValue(def), ppNames, pDescription)
  {
  }
};

class CExAppOptionInt64 : public CExAppOption {
public:
  CExAppOptionInt64(
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeInt64, pName, pDescription)
  {
  }
  
  CExAppOptionInt64(
    CExAppValue::Int64 def,
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeInt64, CExAppValue(def), pName, pDescription)
  {
  }
  
  CExAppOptionInt64(
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeInt64, ppNames, pDescription)
  {
  }
  
  CExAppOptionInt64(
    CExAppValue::Int64 def,
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeInt64, CExAppValue(def), ppNames, pDescription)
  {
  }
};

class CExAppOptionUInt : public CExAppOption {
public:
  CExAppOptionUInt(
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUInt, pName, pDescription)
  {
  }
  
  CExAppOptionUInt(
    CExAppValue::UInt def,
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUInt, CExAppUIntValue(def), pName, pDescription)
  {
  }
  
  CExAppOptionUInt(
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUInt, ppNames, pDescription)
  {
  }
  
  CExAppOptionUInt(
    CExAppValue::UInt def,
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUInt, CExAppUIntValue(def), ppNames, pDescription)
  {
  }
};

class CExAppOptionUInt32 : public CExAppOption {
public:
  CExAppOptionUInt32(
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUInt32, pName, pDescription)
  {
  }
  
  CExAppOptionUInt32(
    CExAppValue::UInt32 def,
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUInt32, CExAppValue(def), pName, pDescription)
  {
  }

  CExAppOptionUInt32(
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUInt32, ppNames, pDescription)
  {
  }

  CExAppOptionUInt32(
    CExAppValue::UInt32 def,
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUInt32, CExAppValue(def), ppNames, pDescription)
  {
  }
};

class CExAppOptionUInt64 : public CExAppOption {
public:
  CExAppOptionUInt64(
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUInt64, pName, pDescription)
  {
  }
  
  CExAppOptionUInt64(
    CExAppValue::UInt64 def,
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUInt64, CExAppValue(def), pName, pDescription)
  {
  }
  
  CExAppOptionUInt64(
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUInt64, ppNames, pDescription)
  {
  }
  
  CExAppOptionUInt64(
    CExAppValue::UInt64 def,
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUInt64, CExAppValue(def), ppNames, pDescription)
  {
  }
};

class CExAppOptionUIntHex : public CExAppOption {
public:
  CExAppOptionUIntHex(
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUIntHex, pName, pDescription)
  {
  }
  
  CExAppOptionUIntHex(
    CExAppValue::UInt def,
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUIntHex, CExAppUIntValue(def), pName, pDescription)
  {
  }
  
  CExAppOptionUIntHex(
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUIntHex, ppNames, pDescription)
  {
  }
  
  CExAppOptionUIntHex(
    CExAppValue::UInt def,
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUIntHex, CExAppUIntValue(def), ppNames, pDescription)
  {
  }
};

class CExAppOptionUIntHex32 : public CExAppOption {
public:
  CExAppOptionUIntHex32(
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUIntHex32, pName, pDescription)
  {
  }
  
  CExAppOptionUIntHex32(
    CExAppValue::UInt32 def,
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUIntHex32, CExAppValue(def), pName, pDescription)
  {
  }
  
  CExAppOptionUIntHex32(
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUIntHex32, ppNames, pDescription)
  {
  }
  
  CExAppOptionUIntHex32(
    CExAppValue::UInt32 def,
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUIntHex32, CExAppValue(def), ppNames, pDescription)
  {
  }
};

class CExAppOptionUIntHex64 : public CExAppOption {
public:
  CExAppOptionUIntHex64(
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUIntHex64, pName, pDescription)
  {
  }
  
  CExAppOptionUIntHex64(
    CExAppValue::UInt64 def,
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUIntHex64, CExAppValue(def), pName, pDescription)
  {
  }
  
  CExAppOptionUIntHex64(
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUIntHex64, ppNames, pDescription)
  {
  }
  
  CExAppOptionUIntHex64(
    CExAppValue::UInt64 def,
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeUIntHex64, CExAppValue(def), ppNames, pDescription)
  {
  }
};

class CExAppOptionFloat : public CExAppOption {
public:
  CExAppOptionFloat(
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeFloat, pName, pDescription)
  {
  }
  
  CExAppOptionFloat(
    CExAppValue::Float def,
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeFloat, CExAppValue(def), pName, pDescription)
  {
  }
  
  CExAppOptionFloat(
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeFloat, ppNames, pDescription)
  {
  }
  
  CExAppOptionFloat(
    CExAppValue::Float def,
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeFloat, CExAppValue(def), ppNames, pDescription)
  {
  }
};

class CExAppOptionDouble : public CExAppOption {
public:
  CExAppOptionDouble(
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeDouble, pName, pDescription)
  {
  }
  
  CExAppOptionDouble(
    CExAppValue::Double def,
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeDouble, CExAppValue(def), pName, pDescription)
  {
  }
  
  CExAppOptionDouble(
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeDouble, ppNames, pDescription)
  {
  }
  
  CExAppOptionDouble(
    CExAppValue::Double def,
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeDouble, CExAppValue(def), ppNames, pDescription)
  {
  }
};

class CExAppOptionString : public CExAppOption {
public:
  CExAppOptionString(
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeString, pName, pDescription)
  {
  }
  
  CExAppOptionString(
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
      CExAppOption(ExAppValueTypeString, ppNames, pDescription)
  {
  }
};

class CExAppOptionStringDef : public CExAppOption {
public:
  CExAppOptionStringDef(
    const StringType& def,
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
    CExAppOption(ExAppValueTypeString, CExAppValue(def), pName, pDescription)
  {
  }

  CExAppOptionStringDef(
    const TCHAR* pDef,
    const TCHAR* pName,
    const TCHAR* pDescription = NULL) :
    CExAppOption(ExAppValueTypeString, CExAppValue(pDef), pName, pDescription)
  {
  }

  CExAppOptionStringDef(
    const StringType& def,
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
    CExAppOption(ExAppValueTypeString, CExAppValue(def), ppNames, pDescription)
  {
  }

  CExAppOptionStringDef(
    const TCHAR* pDef,
    const TCHAR** ppNames,
    const TCHAR* pDescription = NULL) :
    CExAppOption(ExAppValueTypeString, CExAppValue(pDef), ppNames, pDescription)
  {
  }
};

static bool CExAppOptionLog_OnComplete(CExAppCmdLineArgs& args); // Forward reference

class CExAppOptionLog : public CExAppOptionString {
public:
  CExAppOptionLog() :
    CExAppOptionString(_T("log"), _T("Relative or absolute path of log file. (Default no log file)"))
  {
  }

  virtual ~CExAppOptionLog() {
  }

protected:
  virtual bool OnComplete(CExAppCmdLineArgs& args) {
    return CExAppOptionLog_OnComplete(args);
  }
};

class CExAppPositional : public CExAppOption {
public:
  CExAppPositional(ExAppValueType type, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppOption(type, pName, pDescription) {
  }

  CExAppPositional(ExAppValueType type, const CExAppValue& def, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppOption(type, def, pName, pDescription) {
  }

  virtual ~CExAppPositional() {
  }
};

class CExAppPositionalBool : public CExAppPositional {  
public:
  CExAppPositionalBool(const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeBool, pName, pDescription) {
  }

  CExAppPositionalBool(bool def, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeBool, CExAppValue(def), pName, pDescription) {
  }

  virtual ~CExAppPositionalBool() {
  }
};

class CExAppPositionalInt : public CExAppPositional {  
public:
  CExAppPositionalInt(const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeInt, pName, pDescription) {
  }

  CExAppPositionalInt(CExAppValue::Int def, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeInt, CExAppIntValue(def), pName, pDescription) {
  }

  virtual ~CExAppPositionalInt() {
  }
};

class CExAppPositionalInt32 : public CExAppPositional {  
public:
  CExAppPositionalInt32(const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeInt32, pName, pDescription) {
  }

  CExAppPositionalInt32(CExAppValue::Int32 def, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeInt32, CExAppValue(def), pName, pDescription) {
  }

  virtual ~CExAppPositionalInt32() {
  }
};

class CExAppPositionalInt64 : public CExAppPositional {  
public:
  CExAppPositionalInt64(const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeInt64, pName, pDescription) {
  }

  CExAppPositionalInt64(CExAppValue::Int64 def, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeInt64, CExAppValue(def), pName, pDescription) {
  }

  virtual ~CExAppPositionalInt64() {
  }
};

class CExAppPositionalUInt : public CExAppPositional {  
public:
  CExAppPositionalUInt(const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeUInt, pName, pDescription) {
  }

  CExAppPositionalUInt(CExAppValue::UInt def, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeUInt, CExAppUIntValue(def), pName, pDescription) {
  }

  virtual ~CExAppPositionalUInt() {
  }
};

class CExAppPositionalUInt32 : public CExAppPositional {  
public:
  CExAppPositionalUInt32(const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeUInt32, pName, pDescription) {
  }

  CExAppPositionalUInt32(CExAppValue::UInt32 def, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeUInt32, CExAppValue(def), pName, pDescription) {
  }

  virtual ~CExAppPositionalUInt32() {
  }
};

class CExAppPositionalUInt64 : public CExAppPositional {  
public:
  CExAppPositionalUInt64(const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeUInt64, pName, pDescription) {
  }

  CExAppPositionalUInt64(CExAppValue::UInt64 def, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeUInt64, CExAppValue(def), pName, pDescription) {
  }

  virtual ~CExAppPositionalUInt64() {
  }
};

class CExAppPositionalUIntHex : public CExAppPositional {  
public:
  CExAppPositionalUIntHex(const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeUIntHex, pName, pDescription) {
  }

  CExAppPositionalUIntHex(CExAppValue::UInt def, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeUIntHex, CExAppUIntValue(def), pName, pDescription) {
  }

  virtual ~CExAppPositionalUIntHex() {
  }
};

class CExAppPositionalUIntHex32 : public CExAppPositional {  
public:
  CExAppPositionalUIntHex32(const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeUIntHex32, pName, pDescription) {
  }

  CExAppPositionalUIntHex32(CExAppValue::UInt32 def, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeUIntHex32, CExAppValue(def), pName, pDescription) {
  }

  virtual ~CExAppPositionalUIntHex32() {
  }
};

class CExAppPositionalUIntHex64 : public CExAppPositional {  
public:
  CExAppPositionalUIntHex64(const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeUIntHex64, pName, pDescription) {
  }

  CExAppPositionalUIntHex64(CExAppValue::UInt64 def, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeUIntHex64, CExAppValue(def), pName, pDescription) {
  }

  virtual ~CExAppPositionalUIntHex64() {
  }
};

class CExAppPositionalFloat : public CExAppPositional {  
public:
  CExAppPositionalFloat(const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeFloat, pName, pDescription) {
  }

  CExAppPositionalFloat(CExAppValue::Float def, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeFloat, CExAppValue(def), pName, pDescription) {
  }

  virtual ~CExAppPositionalFloat() {
  }
};

class CExAppPositionalDouble : public CExAppPositional {  
public:
  CExAppPositionalDouble(const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeDouble, pName, pDescription) {
  }

  CExAppPositionalDouble(CExAppValue::Double def, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeDouble, CExAppValue(def), pName, pDescription) {
  }

  virtual ~CExAppPositionalDouble() {
  }
};

class CExAppPositionalString : public CExAppPositional {  
public:
  CExAppPositionalString(const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeString, pName, pDescription) {
  }

#if 0
  CExAppPositionalString(const StringType& def, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeString, CExAppValue(def), pName, pDescription) {
  }

  CExAppPositionalString(const TCHAR* pDef, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeString, CExAppValue(pDef), pName, pDescription) {
  }
#endif

  virtual ~CExAppPositionalString() {
  }
};

class CExAppPositionalStringDef : public CExAppPositional {
public:
  CExAppPositionalStringDef(const StringType& def, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeString, CExAppValue(def), pName, pDescription) {
  }

  CExAppPositionalStringDef(const TCHAR* pDef, const TCHAR* pName, const TCHAR* pDescription = NULL) : CExAppPositional(ExAppValueTypeString, CExAppValue(pDef), pName, pDescription) {
  }

  virtual ~CExAppPositionalStringDef() {
  }
};

class CExAppCmdLineArgs {
  friend class CExAppOption;
  friend class CExAppPositional;

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

  typedef const TCHAR* ConstTcharPtr;
  typedef const ConstTcharPtr ConstArgvType[];

  typedef TCHAR* TcharPtr;
  typedef TcharPtr ArgvType[];

public:
  CExAppCmdLineArgs(bool bIncludeHelpOption = true, bool bIncludeLogOption = true) :
    m_bodyLayout(1), m_formLayout(2), m_optionLayout(4)
  {
    m_pLogStream = NULL;
    m_pMessageDisplay = &m_defaultMessageDisplay;
    m_numRequiredPositional = 0;
    m_bWarnExtraPositionals = true;
    m_bHelpRequested = false;
    static const TCHAR* argv[1] = { _T("unnamed") };
    SetArgVector(1, argv);
    if (bIncludeHelpOption) {
      AddOption(GetHelpOption());
    }
    if (bIncludeLogOption) {
      AddOption(GetLogOption());
    }
    RestoreDefaultLayout();
  }
  
  CExAppCmdLineArgs(int argc, ArgvType argv, bool bIncludeHelpOption = true, bool bIncludeLogOption = true) :
    m_bodyLayout(1), m_formLayout(2), m_optionLayout(4)
  {
    m_pLogStream = NULL;
    m_pMessageDisplay = &m_defaultMessageDisplay;
    m_numRequiredPositional = 0;
    m_bHelpRequested = false;
    SetArgVector(argc, argv);
    if (bIncludeHelpOption) {
      AddOption(GetHelpOption());
    }
    if (bIncludeLogOption) {
      AddOption(GetLogOption());
    }
    RestoreDefaultLayout();
  }
  
  virtual ~CExAppCmdLineArgs() {
    if (NULL != m_pLogStream) {
      m_pLogStream->flush();
      delete m_pLogStream;
    }
  }

  // 
  // Argument vector & program name
  //

  virtual void SetProgramName(const TCHAR* pProgramName) {
    m_programName = pProgramName;
#ifdef _WIN32
    size_t pos = m_programName.find_last_of(_T("\\"));
#else
    size_t pos = m_programName.find_last_of(_T("/"));
#endif
    if (std::string::npos != pos) {
      m_programName = m_programName.substr(pos + 1);
    }
  }

  const TCHAR* GetProgramName() const {
    return m_programName.c_str();
  }

  virtual void SetArgVector(int argc, ArgvType argv) {
    if (argc > 0) {
      SetProgramName(argv[0]);
    } else {
      SetProgramName(_T("unnamed"));
    }
    m_argv.clear();
    for (int i = 0; i < argc; i++) {
      m_argv.push_back(argv[i]);
    }
  }

  virtual void SetArgVector(int argc, ConstArgvType argv) {
    if (argc > 0) {
      SetProgramName(argv[0]);
    } else {
      SetProgramName(_T("unnamed"));
    }
    m_argv.clear();
    for (int i = 0; i < argc; i++) {
      m_argv.push_back(argv[i]);
    }
  }

  virtual void SetArgVector(const std::vector<StringType>& argv) {
    size_t argc = m_argv.size();
    m_argv.clear();
    for (size_t i = 0; i < argc; i++) {
      m_argv.push_back(argv[i]);
    }
  }

  const std::vector<StringType>& GetArgVector() const {
    return m_argv;
  }
  
  // 
  // Layout
  //

  CExAppTermLayout& GetBodyLayout() {
    return m_bodyLayout;
  }

  CExAppTermLayout& GetFormLayout() {
    return m_formLayout;
  }

  CExAppTermLayout& GetOptionLayout() {
    return m_optionLayout;
  }

  void RestoreDefaultLayout() {
    unsigned int terminalWidth = CExAppTermLayout::GetTerminalWidth();
    if (terminalWidth < 40) {
      // This might happen if directing stdout, so just assume 80 characters.
      terminalWidth = 80;
    }

    // Layout for displaying non-tabulated text
    m_bodyLayout.SetColumnWidth(0, terminalWidth - 1);

    // Layout for displaying messages
    CExAppTermLayout& messageLayout = m_pMessageDisplay->GetLayout();
    messageLayout.SetColumnWidth(0, 6);
    messageLayout.SetColumnWidth(1, 1);
    messageLayout.SetColumnWidth(2, terminalWidth - 6 - 1 - 1); // For columns 0 & 1 & leaving one char blank at edge of terminal

    // Layout for displaying forms of command
    unsigned int availableWidth = terminalWidth - (2 + 1); // For column 0 & leaving one char blank at edge of terminal
    m_formLayout.SetColumnWidth(0, 2U);           // Indent
    m_formLayout.SetColumnWidth(1, availableWidth); // Positional names

    // Layout for displaying options & positionals
    availableWidth = terminalWidth - (2 + 1 + 1); // For columns 0 & 2 & leaving one char blank at edge of terminal
    unsigned int optionWidth = (availableWidth + 2) / 3;   // 1/3 of available width, rounded up
    unsigned int descWidth = availableWidth - optionWidth; // remaining available width
    m_optionLayout.SetColumnWidth(0, 2);           // Indent
    m_optionLayout.SetColumnWidth(1, optionWidth); // Option names
    m_optionLayout.SetColumnWidth(2, 1);           // Spacer
    m_optionLayout.SetColumnWidth(3, descWidth);   // Option description
  }

  // 
  // Options
  //

  CExAppOptionHelp& GetHelpOption() {
    return m_helpOption;
  }
  
  CExAppOptionLog& GetLogOption() {
    return m_logOption;
  }

  void AddOption(CExAppOption& option) {
    m_options.push_back(&option);
  }
  
  void InsertOption(CExAppOption& option, unsigned int at) {
    m_options.insert(m_options.begin() + at, &option);
  }
  
  CExAppOption& RemoveOption(unsigned int at) {
    CExAppOption& ref = *m_options[at];
    m_options.erase(m_options.begin() + at);
    return ref;
  }
  
  void ClearOptions() {
    m_options.erase(m_options.begin());
  }

  CExAppOption& GetOption(unsigned int at) {
    return *(m_options[at]);
  }
  
  const std::vector<CExAppOption*>& GetOptions() const {
    return m_options;
  }
  
  // 
  // Positionals
  //

  bool GetWarnExtraPositionals() const {
    return m_bWarnExtraPositionals;
  }

  size_t GetNumExtraPositional() const {
    return m_nExtraPositionals;
  }

  void SetWarnExtraPositionals(bool bWarnExtraPositionals) {
    m_bWarnExtraPositionals = bWarnExtraPositionals;
  }

  void AddPositional(CExAppPositional& positional) {
    m_positionals.push_back(&positional);
  }

  void InsertPositional(CExAppPositional& positional, unsigned int at) {
    m_positionals.insert(m_positionals.begin() + at, &positional);
  }
  
  CExAppPositional& RemovePositional(unsigned int at) {
    CExAppPositional& ref = *m_positionals[at];
    m_positionals.erase(m_positionals.begin() + at);
    return ref;
  }
  
  void ClearPositionals() {
    m_positionals.erase(m_positionals.begin());
  }

  CExAppPositional& GetPositional(unsigned int at) {
    return *(m_positionals[at]);
  }
  
  const std::vector<CExAppPositional*>& GetPositionals() const {
    return m_positionals;
  }
  
  unsigned int GetNumRequiredPositionals() {
    return m_numRequiredPositional;
  }

  void SetNumRequiredPositionals(unsigned int n) {
    m_numRequiredPositional = n;
  }

  //
  // Displaying help
  //

#ifdef _UNICODE
  virtual void DisplayHelp(OStreamType& ostream = std::wcout) {
#else
  virtual void DisplayHelp(OStreamType& ostream = std::cout) {
#endif
    DisplaySummary(ostream);
    DisplayForms(ostream);
    DisplayPositionals(ostream);
    DisplayOptions(ostream);
  }
  
#ifdef _UNICODE
  virtual void DisplaySummary(OStreamType& ostream = std::wcout) {
#else
  virtual void DisplaySummary(OStreamType& ostream = std::cout) {
#endif
    m_bodyLayout.GetStream(0) << _T("Usage:");
    m_bodyLayout.Flush(ostream);
  }
  
#ifdef _UNICODE
  virtual void DisplayForms(OStreamType& ostream = std::wcout) {
#else
  virtual void DisplayForms(OStreamType& ostream = std::cout) {
#endif
    m_bodyLayout.GetStream(0) << std::endl;
    m_bodyLayout.Flush(ostream);

    SStreamType& formColumn = m_formLayout.GetStream(1);
    formColumn << m_programName;
    if (m_options.size() > 0) {
      formColumn << _T(" [option ...]");
    }
    unsigned int index = 0;
    for (std::vector<CExAppPositional*>::const_iterator i = m_positionals.begin(); i != m_positionals.end(); i++) {
      CExAppPositional* pPositional = *i;
      bool bOptional = m_numRequiredPositional <= index;
      const StringType& name = pPositional->GetName(0);
      if (bOptional) {
        formColumn << _T(" [") << name << _T("]");
      } else {
        formColumn << _T(" ") << name;
      }
      index++;
    }
    if (!m_bWarnExtraPositionals) {
      formColumn << _T(" ...");
    }
    formColumn << std::endl;
    m_formLayout.Flush(ostream);
  }

#ifdef _UNICODE
  virtual void DisplayOptions(OStreamType& ostream = std::wcout) {
#else
  virtual void DisplayOptions(OStreamType& ostream = std::cout) {
#endif
    if (0 == m_options.size()) {
      return;
    }

    m_bodyLayout.GetStream(0) << std::endl;
    m_bodyLayout.Flush(ostream);
    m_bodyLayout.GetStream(0) << _T("where [option ...] is zero or more of:") << std::endl << std::endl;
    m_bodyLayout.Flush(ostream);

    SStreamType& nameColumn = m_optionLayout.GetStream(1);
    SStreamType& descColumn = m_optionLayout.GetStream(3);
    for (std::vector<CExAppOption*>::const_iterator i = m_options.begin(); i != m_options.end(); i++) {
      CExAppOption* pOption = *i;
      const std::vector<StringType>& names = pOption->GetNames();
      for (std::vector<StringType>::const_iterator j = names.begin(); j != names.end(); j++) {
        nameColumn << m_primaryOptionChar << *j;
        if (j + 1 != names.end()) {
          nameColumn << _T(", ");
        }
      }
      ExAppValueType type = pOption->GetType();
      switch (type) {
      case ExAppValueTypeBool:
        nameColumn << _T(" <bool>");
        break;

      case ExAppValueTypeInt:
        nameColumn << _T(" <int>");
        break;

      case ExAppValueTypeInt32:
        nameColumn << _T(" <int32>");
        break;

      case ExAppValueTypeInt64:
        nameColumn << _T(" <int64>");
        break;

      case ExAppValueTypeUInt:
        nameColumn << _T(" <uint>");
        break;

      case ExAppValueTypeUInt32:
        nameColumn << _T(" <uint32>");
        break;

      case ExAppValueTypeUInt64:
        nameColumn << _T(" <uint64>");
        break;

      case ExAppValueTypeUIntHex:
        nameColumn << _T(" <hex uint>");
        break;

      case ExAppValueTypeUIntHex32:
        nameColumn << _T(" <hex uint32>");
        break;

      case ExAppValueTypeUIntHex64:
        nameColumn << _T(" <hex uint64>");
        break;

      case ExAppValueTypeFloat:
        nameColumn << _T(" <float>");
        break;

      case ExAppValueTypeDouble:
        nameColumn << _T(" <double>");
        break;

      case ExAppValueTypeString:
        nameColumn << _T(" <string>");
        break;

      case ExAppValueTypeNone:
        break;

      default:
        assert(false);
        break;
      }
      descColumn << pOption->GetDescription();
      bool bHasDefault = pOption->GetHasDefault();
      if (bHasDefault) {
        CExAppValue::UInt64 value64;
        switch (type) {
        case ExAppValueTypeBool:
          descColumn << _T(" (Default ") << (pOption->GetDefault().m_scalar.m_bool ? "TRUE" : "FALSE") << _T(")");
          break;

        case ExAppValueTypeInt:
          descColumn << _T(" (Default ") << std::dec << pOption->GetDefault().m_scalar.m_int << _T(")");
          break;

        case ExAppValueTypeInt32:
          descColumn << _T(" (Default ") << std::dec << pOption->GetDefault().m_scalar.m_int32 << _T(")");
          break;

        case ExAppValueTypeInt64:
          descColumn << _T(" (Default ") << std::dec << pOption->GetDefault().m_scalar.m_int64 << _T(")");
          break;

        case ExAppValueTypeUInt:
          descColumn << _T(" (Default ") << std::dec << pOption->GetDefault().m_scalar.m_uint << _T(")");
          break;

        case ExAppValueTypeUInt32:
          descColumn << _T(" (Default ") << std::dec << pOption->GetDefault().m_scalar.m_uint32 << _T(")");
          break;

        case ExAppValueTypeUInt64:
          descColumn << _T(" (Default ") << std::dec << pOption->GetDefault().m_scalar.m_uint64 << _T(")");
          break;

        case ExAppValueTypeUIntHex:
          descColumn << _T(" (Default 0x") << std::hex << pOption->GetDefault().m_scalar.m_uint << _T(")");
          break;

        case ExAppValueTypeUIntHex32:
          descColumn << _T(" (Default 0x") << std::hex << pOption->GetDefault().m_scalar.m_uint32 << _T(")");
          break;

        case ExAppValueTypeUIntHex64:
          value64 = pOption->GetDefault().m_scalar.m_uint64;
          if (value64 > 0xFFFFFFFFU) {
            descColumn << _T(" (Default 0x") << std::hex << ((value64 >> 32) & 0xFFFFFFFFU) << _T("_") << std::setw(8) << ((value64 >> 0) & 0xFFFFFFFFU) << _T(")");
          } else {
            descColumn << _T(" (Default 0x") << std::hex << value64 << _T(")");
          }
          break;

        case ExAppValueTypeFloat:
          descColumn << _T(" (Default ") << pOption->GetDefault().m_scalar.m_float << _T(")");
          break;

        case ExAppValueTypeDouble:
          descColumn << _T(" (Default ") << pOption->GetDefault().m_scalar.m_double << _T(")");
          break;

        case ExAppValueTypeString:
          descColumn << _T(" (Default ") << pOption->GetDefault().m_string << _T(")");
          break;

        case ExAppValueTypeNone:
          break;

        default:
          assert(false);
          break;
        }
      }
      m_optionLayout.Flush(ostream);
#if 0
      if (i + 1 != m_options.end()) {
        m_bodyLayout.GetStream(0) << std::endl;
        m_bodyLayout.Flush(ostream);
      }
#endif
    }
  }
  
#ifdef _UNICODE
  virtual void DisplayPositionals(OStreamType& ostream = std::wcout) {
#else
  virtual void DisplayPositionals(OStreamType& ostream = std::cout) {
#endif
    if (0 == m_positionals.size()) {
      return;
    }

    m_bodyLayout.GetStream(0) << std::endl;
    m_bodyLayout.Flush(ostream);
    m_bodyLayout.GetStream(0) << _T("where the positional arguments are:") << std::endl << std::endl;
    m_bodyLayout.Flush(ostream);

    SStreamType& nameColumn = m_optionLayout.GetStream(1);
    SStreamType& descColumn = m_optionLayout.GetStream(3);
    unsigned int index = 0;
    for (std::vector<CExAppPositional*>::const_iterator i = m_positionals.begin(); i != m_positionals.end(); i++) {
      CExAppPositional* pPositional = *i;
      const StringType& name = pPositional->GetName(0);
      nameColumn << name;
      ExAppValueType type = pPositional->GetType();
      switch (type) {
      case ExAppValueTypeBool:
        nameColumn << _T(" (bool)");
        break;

      case ExAppValueTypeInt:
        nameColumn << _T(" (int)");
        break;

      case ExAppValueTypeInt32:
        nameColumn << _T(" (int32)");
        break;

      case ExAppValueTypeInt64:
        nameColumn << _T(" (int64)");
        break;

      case ExAppValueTypeUInt:
        nameColumn << _T(" (uint)");
        break;

      case ExAppValueTypeUInt32:
        nameColumn << _T(" (uint32)");
        break;

      case ExAppValueTypeUInt64:
        nameColumn << _T(" (uint64)");
        break;

      case ExAppValueTypeUIntHex:
        nameColumn << _T(" (hex uint)");
        break;

      case ExAppValueTypeUIntHex32:
        nameColumn << _T(" (hex uint32)");
        break;

      case ExAppValueTypeUIntHex64:
        nameColumn << _T(" (hex uint64)");
        break;

      case ExAppValueTypeFloat:
        nameColumn << _T(" (float)");
        break;

      case ExAppValueTypeDouble:
        nameColumn << _T(" (double)");
        break;

      case ExAppValueTypeString:
        nameColumn << _T(" (string)");
        break;

      case ExAppValueTypeNone:
        assert(false); // Positionals must ALWAYS have a type
        break;

      default:
        assert(false);
        break;
      }
      if (m_numRequiredPositional <= index) {
        descColumn << _T("(Optional) ");
      }
      descColumn << pPositional->GetDescription();
      bool bHasDefault = pPositional->GetHasDefault();
      if (bHasDefault) {
        CExAppValue::UInt64 value64;
        switch (type) {
        case ExAppValueTypeBool:
          descColumn << _T(" (Default ") << (pPositional->GetDefault().m_scalar.m_bool ? "TRUE" : "FALSE") << _T(")");
          break;

        case ExAppValueTypeInt:
          descColumn << _T(" (Default ") << std::dec << pPositional->GetDefault().m_scalar.m_int << _T(")");
          break;

        case ExAppValueTypeInt32:
          descColumn << _T(" (Default ") << std::dec << pPositional->GetDefault().m_scalar.m_int32 << _T(")");
          break;

        case ExAppValueTypeInt64:
          descColumn << _T(" (Default ") << std::dec << pPositional->GetDefault().m_scalar.m_int64 << _T(")");
          break;

        case ExAppValueTypeUInt:
          descColumn << _T(" (Default ") << std::dec << pPositional->GetDefault().m_scalar.m_uint << _T(")");
          break;

        case ExAppValueTypeUInt32:
          descColumn << _T(" (Default ") << std::dec << pPositional->GetDefault().m_scalar.m_uint32 << _T(")");
          break;

        case ExAppValueTypeUInt64:
          descColumn << _T(" (Default ") << std::dec << pPositional->GetDefault().m_scalar.m_uint64 << _T(")");
          break;

        case ExAppValueTypeUIntHex:
          descColumn << _T(" (Default 0x") << std::hex << pPositional->GetDefault().m_scalar.m_uint << _T(")");
          break;

        case ExAppValueTypeUIntHex32:
          descColumn << _T(" (Default 0x") << std::hex << pPositional->GetDefault().m_scalar.m_uint32 << _T(")");
          break;

        case ExAppValueTypeUIntHex64:
          value64 = pPositional->GetDefault().m_scalar.m_uint64;
          if (value64 > 0xFFFFFFFFU) {
            descColumn << _T(" (Default 0x") << std::hex << ((value64 >> 32) & 0xFFFFFFFFU) << _T("_") << std::setw(8) << ((value64 >> 0) & 0xFFFFFFFFU) << _T(")");
          } else {
            descColumn << _T(" (Default 0x") << std::hex << value64 << _T(")");
          }
          break;

        case ExAppValueTypeFloat:
          descColumn << _T(" (Default ") << pPositional->GetDefault().m_scalar.m_float << _T(")");
          break;

        case ExAppValueTypeDouble:
          descColumn << _T(" (Default ") << pPositional->GetDefault().m_scalar.m_double << _T(")");
          break;

        case ExAppValueTypeString:
          descColumn << _T(" (Default ") << pPositional->GetDefault().m_string << _T(")");
          break;

        case ExAppValueTypeNone:
          break;

        default:
          assert(false);
          break;
        }
      }
      m_optionLayout.Flush(ostream);
#if 0
      if (i + 1 != m_positionals.end()) {
        m_bodyLayout.GetStream(0) << std::endl;
        m_bodyLayout.Flush(ostream);
      }
#endif
      index++;
    }
  }
  
  //
  // Doing the parsing & getting result
  //

  ExAppParseResult Parse() {
    do {
      m_bParseAgain = false;
      m_parseResult = ExAppParseResultOk;
      m_positionalIndex = 0;
      m_pExpectValue = NULL;
      m_bOptionsFinished = false;
      m_position = 1;
      m_nExtraPositionals = 0;
      size_t argc = m_argv.size();
      while (m_position < argc) {
        StringType& str = m_argv[m_position];
        if (!m_bOptionsFinished && str.length() >= 1 && (str[0] == m_primaryOptionChar || str[0] == m_secondaryOptionChar) && !CExAppNumParse::IsANumber(str, true)) {
          if (m_pExpectValue != NULL) {
            SStreamType msg;
            msg << _T("Expecting value for option '") << m_expectValueName << _T("' but got another option '") << str << _T("'");
            AddError(msg.str());
            SetParseResult(ExAppParseResultMissingValue);
            m_pExpectValue = NULL;
          }
          if (str.length() == 1) {
            m_bOptionsFinished = true;
            ConsumeArgToken();
            continue;
          }
          if (!HandleOption(str)) {
            break;
          }
        } else {
          if (m_pExpectValue != NULL) {
            if (!HandleValue(str)) {
              break;
            }
          } else {
            if (!HandlePositional(str)) {
              break;
            }
          }
        }
      }

      if (m_pExpectValue != NULL) {
        SStreamType msg;
        msg << _T("Expecting value for option '") << m_expectValueName << _T("'");
        AddError(msg.str());
        SetParseResult(ExAppParseResultMissingValue);
      }

      if (m_bHelpRequested) {
        DisplayHelp();
        break;
      } else {
      	if (m_positionalIndex < m_numRequiredPositional) {
          SStreamType msg;
          if (m_numRequiredPositional != m_positionals.size()) {
            msg << _T("Expecting between ") << m_numRequiredPositional << _T(" and ") << m_positionals.size() << _T(" positional argument(s) but got ") << m_positionalIndex << _T(".");
          } else {
            msg << _T("Expecting ") << m_numRequiredPositional << _T(" positional argument(s) but got ") << m_positionalIndex << _T(".");
          }
          AddError(msg.str());
          SetParseResult(ExAppParseResultMissingPositional);
        }
      }

      OnParseComplete();
    } while (m_bParseAgain && m_parseResult == ExAppParseResultOk);

    if (m_logPath.length() > 0 && !m_bHelpRequested) {
      CreateLogFile(m_logPath.c_str(), false);
    }

    return m_parseResult;
  }
  
  //
  // Displaying messages
  //

  void SetMessageDisplay(CExAppMessageDisplay* pMessageDisplay) {
    if (NULL == pMessageDisplay) {
      m_pMessageDisplay = &m_defaultMessageDisplay;
    } else {
      m_pMessageDisplay = pMessageDisplay;
    }
  }

  CExAppMessageDisplay* GetMessageDisplay() {
    return m_pMessageDisplay;
  }

  CExAppMessageDisplay& GetDefaultMessageDisplay() {
    return m_defaultMessageDisplay;
  }

  void AddError(const TCHAR* pMessage) {
    m_pMessageDisplay->AddError(pMessage);
  }

  void AddError(const StringType& message) {
    m_pMessageDisplay->AddError(message);
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
    m_pMessageDisplay->AddInfo(pMessage);
  }

  void AddInfo(const StringType& message) {
    m_pMessageDisplay->AddInfo(message);
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
    m_pMessageDisplay->AddWarning(pMessage);
  }

  void AddWarning(const StringType& message) {
    m_pMessageDisplay->AddWarning(message);
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

  void DisplayMessages() {
    m_pMessageDisplay->DisplayMessages();
  }

  //
  // Get return code for application
  //

  int GetExitCode() const {
    if (m_parseResult > ExAppParseResultHelpOnly) {
      return (int)m_parseResult - 1;
    } else {
      return 0;
    }
  }

  //
  // Callable by OnComplete() method of CExAppOption / CExAppPositional
  //

  void SetParseResult(ExAppParseResult result) {
    assert(result != ExAppParseResultOk);
    if (m_parseResult <= ExAppParseResultHelpOnly) {
      m_parseResult = result;
    }
  }

  ExAppParseResult GetExAppParseResult() const {
    return m_parseResult;
  }

  void RequestParseAgain() {
    m_bParseAgain = true;
  }

  void SetHelpRequested() {
    m_bHelpRequested = true;
  }

  void SetLogPath(const TCHAR* pPath) {
    m_logPath = pPath;
  }

  bool GetHelpRequested() const {
    return m_bHelpRequested;
  }

  bool CreateLogFile(const TCHAR* pLogPath, bool bAppend) {
    std::ios_base::openmode mode = std::ios_base::out;
    assert(NULL == m_pLogStream);
    if (bAppend) {
      mode |= std::ios_base::app;
    } else {
      mode |= std::ios_base::trunc;
    }
#ifdef _UNICODE
    m_pLogStream = new std::wofstream(pLogPath, mode);
#else
    m_pLogStream = new std::ofstream(pLogPath, mode);
#endif
    if (NULL == m_pLogStream || !m_pLogStream->good()) {
      FormatError(_T("Failed to log to file '%s'."), pLogPath);
      return false; // Failed to start logging
    }
    m_pMessageDisplay->SetLogStream(m_pLogStream);
    return true; // Success
  }

protected:
  virtual bool OnOptionComplete(const CExAppOption& /* option */) {
    return true;
  }
  
  virtual bool OnPositionalComplete(const CExAppPositional& /* positional */) {
    return true;
  }

  virtual void OnParseComplete() {
  }
  
private:
  void ConsumeArgToken() {
    m_position++;
  }

  bool HandleOption(const StringType& s) {
    size_t equalPos = s.find('=');
    bool bHasValue = false;
    StringType optionStem, optionName, optionValue;
    if (StringType::npos == equalPos) {
      optionStem = s;
      optionName = s.substr(1);
    } else {
      optionStem = s.substr(0, equalPos);
      optionName = s.substr(1, equalPos - 1);
      optionValue = s.substr(equalPos + 1);
      bHasValue = true;
    }
    for (std::vector<CExAppOption*>::const_iterator i = m_options.begin(); i != m_options.end(); i++) {
      CExAppOption* pOption = *i;
      const std::vector<StringType>& names = pOption->GetNames();
      for (std::vector<StringType>::const_iterator j = names.begin(); j != names.end(); j++) {
        if (optionName.compare(*j) == 0) {
          ConsumeArgToken();
          if (bHasValue) {
            return SetOptionValueFromString(*pOption, optionName, optionValue);
          } else {
            if (pOption->GetType() == ExAppValueTypeNone) {
              pOption->SetValueNone();
              return InvokeOnOptionComplete(*pOption);
            } else {
              m_pExpectValue = pOption;
              m_expectValueName = optionStem;
              return true;
            }
          }
        }
      }
    }

    SStreamType msg;
    msg << _T("Unrecognized option '") << optionStem << _T("'");
    AddError(msg.str());
    SetParseResult(ExAppParseResultUnrecognizedOption);
    ConsumeArgToken();
    return true;
  }
  
  bool HandleValue(const StringType& s) {
    bool bResult;
    bResult = SetOptionValueFromString(*m_pExpectValue, m_expectValueName, s);
    m_pExpectValue = NULL;
    ConsumeArgToken();
    return bResult;
  }
  
  bool HandlePositional(const StringType& s) {
    bool bResult = true;
    if (m_positionalIndex >= m_positionals.size()) {
      if (m_bWarnExtraPositionals) {
        SStreamType msg;
        msg << _T("Ignoring unexpected positional value '") << s << _T("'");
        AddWarning(msg.str());
      }
      m_nExtraPositionals++;
    } else {
      CExAppPositional& positional = *m_positionals[m_positionalIndex];
      bResult = SetPositionalValueFromString(positional, s);
      m_positionalIndex++;
    }
    ConsumeArgToken();
    return bResult;
  }
  
  bool InvokeOnOptionComplete(CExAppOption& option) {
    if (!option.OnComplete(*this)) {
      return false;
    }
    if (!OnOptionComplete(option)) {
      return false;
    }
    return true;
  }
  
  bool InvokeOnPositionalComplete(CExAppPositional& positional) {
    if (!positional.OnComplete(*this)) {
      return false;
    }
    if (!OnPositionalComplete(positional)) {
      return false;
    }
    return true;
  }
  
  StringType Trim(const StringType& str) {
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

  bool SetOptionValueFromString(CExAppOption& option, const StringType& optionName, const StringType& valueString) {
    SStreamType msg;
    CExAppValue::Int intValue;
    CExAppValue::Int32 int32Value;
    CExAppValue::Int64 int64Value;
    CExAppValue::UInt uintValue;
    CExAppValue::UInt32 uint32Value;
    CExAppValue::UInt64 uint64Value;
    CExAppValue::Float floatValue;
    CExAppValue::Double doubleValue;
    StringType trimmed = Trim(valueString);
    switch (option.GetType()) {
    case ExAppValueTypeNone:
      msg << "Option '" << optionName << "' cannot have a value";
      AddError(msg.str());
      SetParseResult(ExAppParseResultBadValue);
      return true;

    case ExAppValueTypeBool:
      if (trimmed.compare(_T("0")) == 0 || trimmed.compare(_T("false")) == 0 || trimmed.compare(_T("FALSE")) == 0) {
        option.SetValueBool(false);
        return InvokeOnOptionComplete(option);
      } else if (trimmed.compare(_T("1")) == 0 || trimmed.compare(_T("true")) == 0 || trimmed.compare(_T("TRUE")) == 0) {
        option.SetValueBool(true);
        return InvokeOnOptionComplete(option);
      } else {
        msg << "Option '" << optionName << "' requires a value that is one of 0/false/1/true";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }

    case ExAppValueTypeInt:
      if (!CExAppNumParse::ParseInt(trimmed, true, intValue)) {
        msg << "Value '" << trimmed << "' for '" << optionName << "' is not a valid decimal or hexadecimal integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      option.SetValueInt(intValue);
      return InvokeOnOptionComplete(option);

    case ExAppValueTypeInt32:
      if (!CExAppNumParse::ParseInt32(trimmed, true, int32Value)) {
        msg << "Value '" << trimmed << "' for '" << optionName << "' is not a valid decimal or hexadecimal 32-bit integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      option.SetValueInt32(int32Value);
      return InvokeOnOptionComplete(option);

    case ExAppValueTypeInt64:
      if (!CExAppNumParse::ParseInt64(trimmed, true, int64Value)) {
        msg << "Value '" << trimmed << "' for '" << optionName << "' is not a valid decimal or hexadecimal 64-bit integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      option.SetValueInt64(int64Value);
      return InvokeOnOptionComplete(option);

    case ExAppValueTypeUInt:
      if (!CExAppNumParse::ParseUInt(trimmed, true, uintValue)) {
        msg << "Value '" << trimmed << "' for '" << optionName << "' is not a valid decimal or hexadecimal unsigned integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      option.SetValueUInt(uintValue);
      return InvokeOnOptionComplete(option);

    case ExAppValueTypeUInt32:
      if (!CExAppNumParse::ParseUInt32(trimmed, true, uint32Value)) {
        msg << "Value '" << trimmed << "' for '" << optionName << "' is not a valid decimal or hexadecimal unsigned 32-bit integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      option.SetValueUInt32(uint32Value);
      return InvokeOnOptionComplete(option);

    case ExAppValueTypeUInt64:
      if (!CExAppNumParse::ParseUInt64(trimmed, true, uint64Value)) {
        msg << "Value '" << trimmed << "' for '" << optionName << "' is not a valid decimal or hexadecimal unsigned 64-bit integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      option.SetValueUInt64(uint64Value);
      return InvokeOnOptionComplete(option);

    case ExAppValueTypeUIntHex:
      if (!CExAppNumParse::ParseUIntHex(trimmed, uintValue)) {
        msg << "Value '" << trimmed << "' for '" << optionName << "' is not a valid hexadecimal unsigned integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      option.SetValueUInt(uintValue);
      return InvokeOnOptionComplete(option);

    case ExAppValueTypeUIntHex32:
      if (!CExAppNumParse::ParseUIntHex32(trimmed, uint32Value)) {
        msg << "Value '" << trimmed << "' for '" << optionName << "' is not a valid hexadecimal unsigned 32-bit integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      option.SetValueUInt32(uint32Value);
      return InvokeOnOptionComplete(option);

    case ExAppValueTypeUIntHex64:
      if (!CExAppNumParse::ParseUIntHex64(trimmed, uint64Value)) {
        msg << "Value '" << trimmed << "' for '" << optionName << "' is not a valid hexadecimal unsigned 64-bit integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      option.SetValueUInt64(uint64Value);
      return InvokeOnOptionComplete(option);

    case ExAppValueTypeFloat:
      if (!CExAppNumParse::ParseFloat(trimmed, floatValue)) {
        msg << "Value '" << trimmed << "' for '" << optionName << "' is not a valid floating point number";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      option.SetValueFloat(floatValue);
      return InvokeOnOptionComplete(option);

    case ExAppValueTypeDouble:
      if (!CExAppNumParse::ParseDouble(trimmed, doubleValue)) {
        msg << "Value '" << trimmed << "' for '" << optionName << "' is not a valid double-precision floating point number";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      option.SetValueDouble(doubleValue);
      return InvokeOnOptionComplete(option);

    case ExAppValueTypeString:
      // Don't use trimmed version of valueString
      option.SetValueString(valueString);
      InvokeOnOptionComplete(option);
      return true;

    default:
      assert(false);
      return false;
    }
  }
  
  bool SetPositionalValueFromString(CExAppPositional& positional, const StringType& valueString) {
    SStreamType msg;
    StringType positionalName = positional.GetNames()[0];
    CExAppValue::Int intValue;
    CExAppValue::Int32 int32Value;
    CExAppValue::Int64 int64Value;
    CExAppValue::UInt uintValue;
    CExAppValue::UInt32 uint32Value;
    CExAppValue::UInt64 uint64Value;
    CExAppValue::Float floatValue;
    CExAppValue::Double doubleValue;
    StringType trimmed = Trim(valueString);
    switch (positional.GetType()) {
    case ExAppValueTypeNone:
      assert(false);
      return false;

    case ExAppValueTypeBool:
      if (trimmed.compare(_T("0")) == 0 || trimmed.compare(_T("false")) == 0 || trimmed.compare(_T("FALSE")) == 0) {
        positional.SetValueBool(false);
        return InvokeOnPositionalComplete(positional);
      } else if (trimmed.compare(_T("1")) == 0 || trimmed.compare(_T("true")) == 0 || trimmed.compare(_T("TRUE")) == 0) {
        positional.SetValueBool(true);
        return InvokeOnPositionalComplete(positional);
      } else {
        msg << "Positional argument '" << positionalName << "' requires a value that is one of 0, false, 1 or true";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return false;
      }

    case ExAppValueTypeInt:
      if (!CExAppNumParse::ParseInt(trimmed, true, intValue)) {
        msg << "Value '" << trimmed << "' for positional argument '" << positionalName << "' is not a valid decimal or hexadecimal integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      positional.SetValueInt(intValue);
      return InvokeOnPositionalComplete(positional);

    case ExAppValueTypeInt32:
      if (!CExAppNumParse::ParseInt32(trimmed, true, int32Value)) {
        msg << "Value '" << trimmed << "' for positional argument '" << positionalName << "' is not a valid decimal or hexadecimal 32-bit integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      positional.SetValueInt32(int32Value);
      return InvokeOnPositionalComplete(positional);

    case ExAppValueTypeInt64:
      if (!CExAppNumParse::ParseInt64(trimmed, true, int64Value)) {
        msg << "Value '" << trimmed << "' for positional argument '" << positionalName << "' is not a valid decimal or hexadecimal 64-bit integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      positional.SetValueInt64(int64Value);
      return InvokeOnPositionalComplete(positional);

    case ExAppValueTypeUInt:
      if (!CExAppNumParse::ParseUInt(trimmed, true, uintValue)) {
        msg << "Value '" << trimmed << "' for positional argument '" << positionalName << "' is not a valid decimal or hexadecimal unsigned integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      positional.SetValueUInt(uintValue);
      return InvokeOnPositionalComplete(positional);

    case ExAppValueTypeUInt32:
      if (!CExAppNumParse::ParseUInt32(trimmed, true, uint32Value)) {
        msg << "Value '" << trimmed << "' for positional argument '" << positionalName << "' is not a valid decimal or hexadecimal unsigned 32-bit integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      positional.SetValueUInt32(uint32Value);
      return InvokeOnPositionalComplete(positional);

    case ExAppValueTypeUInt64:
      if (!CExAppNumParse::ParseUInt64(trimmed, true, uint64Value)) {
        msg << "Value '" << trimmed << "' for positional argument '" << positionalName << "' is not a valid decimal or hexadecimal unsigned 64-bit integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      positional.SetValueUInt64(uint64Value);
      return InvokeOnPositionalComplete(positional);

    case ExAppValueTypeUIntHex:
      if (!CExAppNumParse::ParseUIntHex(trimmed, uintValue)) {
        msg << "Value '" << trimmed << "' for positional argument '" << positionalName << "' is not a valid hexadecimal unsigned integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      positional.SetValueUInt(uintValue);
      return InvokeOnPositionalComplete(positional);

    case ExAppValueTypeUIntHex32:
      if (!CExAppNumParse::ParseUIntHex32(trimmed, uint32Value)) {
        msg << "Value '" << trimmed << "' for positional argument '" << positionalName << "' is not a valid hexadecimal unsigned 32-bit integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      positional.SetValueUInt32(uint32Value);
      return InvokeOnPositionalComplete(positional);

    case ExAppValueTypeUIntHex64:
      if (!CExAppNumParse::ParseUIntHex64(trimmed, uint64Value)) {
        msg << "Value '" << trimmed << "' for positional argument '" << positionalName << "' is not a valid hexadecimal unsigned 64-bit integer";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      positional.SetValueUInt64(uint64Value);
      return InvokeOnPositionalComplete(positional);

    case ExAppValueTypeFloat:
      if (!CExAppNumParse::ParseFloat(trimmed, floatValue)) {
        msg << "Value '" << trimmed << "' for positional argument '" << positionalName << "' is not a valid floating point number";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      positional.SetValueFloat(floatValue);
      return InvokeOnPositionalComplete(positional);

    case ExAppValueTypeDouble:
      if (!CExAppNumParse::ParseDouble(trimmed, doubleValue)) {
        msg << "Value '" << trimmed << "' for positional argument '" << positionalName << "' is not a valid double-precision floating point number";
        AddError(msg.str());
        SetParseResult(ExAppParseResultBadValue);
        return true;
      }
      positional.SetValueDouble(doubleValue);
      return InvokeOnPositionalComplete(positional);

    case ExAppValueTypeString:
      // Don't use trimmed version of string
      positional.SetValueString(trimmed);
      return InvokeOnPositionalComplete(positional);

    default:
      assert(false);
      return false;
    }
  }
  
protected:
  static const TCHAR m_primaryOptionChar = _T('-');
#ifdef _WIN32
  static const TCHAR m_secondaryOptionChar = _T('/');
#else
  static const TCHAR m_secondaryOptionChar = _T('-');
#endif
  CExAppOptionHelp m_helpOption;
  CExAppOptionLog m_logOption;
  StringType m_logPath;
#ifdef _UNICODE
  std::wostream* m_pLogStream;
#else
  std::ostream* m_pLogStream;
#endif
  std::vector<StringType> m_argv;
  StringType m_programName;
  std::vector<CExAppOption*> m_options;
  std::vector<CExAppPositional*> m_positionals;
  unsigned int m_numRequiredPositional;
  bool m_bWarnExtraPositionals;
  bool m_bOptionsFinished;
  size_t m_position;
  size_t m_nExtraPositionals;
  size_t m_positionalIndex;
  CExAppOption* m_pExpectValue;
  StringType m_expectValueName;
  ExAppParseResult m_parseResult;
  bool m_bParseAgain;
  bool m_bHelpRequested;
  CExAppMessageDisplay* m_pMessageDisplay;
  CExAppMessageDisplay m_defaultMessageDisplay;
  CExAppTermLayout m_bodyLayout;
  CExAppTermLayout m_formLayout;
  CExAppTermLayout m_optionLayout;
};

static bool CExAppOptionHelp_OnComplete(CExAppCmdLineArgs& args) {
  args.SetHelpRequested();
  args.SetParseResult(ExAppParseResultHelpOnly);
  return false; // Don't process any further command-line arguments
}  

static bool CExAppOptionLog_OnComplete(CExAppCmdLineArgs& args) {
  args.SetLogPath(args.GetLogOption().GetValueString().c_str());
  return true; // Process further command-line arguments
}

} // end of namespace AppFramework
} // end of namespace AlphaData

#endif
