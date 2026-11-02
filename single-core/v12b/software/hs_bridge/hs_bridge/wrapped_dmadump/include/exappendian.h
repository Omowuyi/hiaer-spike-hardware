#ifndef _ADATA_APP_FRAMEWORK_EXAPPENDIAN_H
#define _ADATA_APP_FRAMEWORK_EXAPPENDIAN_H

#ifdef _WIN32

# include <windows.h>

# if defined(_M_IX86) || defined(_M_IA64) || defined(_M_X64)

#   define cpu_to_be8(x) x
#   define cpu_to_be16(x) x
#   define cpu_to_be32(x) x
#   define cpu_to_be64(x) x
#   define cpu_to_le8(x) x
#   define cpu_to_le16(x) x
#   define cpu_to_le32(x) x
#   define cpu_to_le64(x) x

#   define be8_to_cpu(x) x
#   define be16_to_cpu(x) x
#   define be32_to_cpu(x) x
#   define be64_to_cpu(x) x
#   define le8_to_cpu(x) x
#   define le16_to_cpu(x) x
#   define le32_to_cpu(x) x
#   define le64_to_cpu(x) x

# else

#   error Unsupported CPU architecture - please fix this file in order to support your CPU architecture!

# endif

#elif defined(__linux)
  
# include <asm/byteorder.h>

# define cpu_to_be8(x) x
# define cpu_to_be16(x) __cpu_to_be16(x)
# define cpu_to_be32(x) __cpu_to_be32(x)
# define cpu_to_be64(x) __cpu_to_be64(x)
# define cpu_to_le8(x) x
# define cpu_to_le16(x) __cpu_to_le16(x)
# define cpu_to_le32(x) __cpu_to_le32(x)
# define cpu_to_le64(x) __cpu_to_le64(x)

# define be8_to_cpu(x) x
# define be16_to_cpu(x) __be16_to_cpu(x)
# define be32_to_cpu(x) __be32_to_cpu(x)
# define be64_to_cpu(x) __be64_to_cpu(x)
# define le8_to_cpu(x) x
# define le16_to_cpu(x) __le16_to_cpu(x)
# define le32_to_cpu(x) __le32_to_cpu(x)
# define le64_to_cpu(x) __le64_to_cpu(x)

#elif defined(__VXWORKS__) || defined(__vxworks)

# include <vxWorks.h>

# if defined(_BYTE_ORDER)
#   if (_BYTE_ORDER == _BIG_ENDIAN)

/* Big-endian byte order */

#     if defined(_WRS_INLINE)
_WRS_INLINE uint64_t
#     else
static __inline__ uint64_t
#     endif
cpu_to_le64(
  uint64_t x)
{
  return ((x        & (uint64_t)0x000000ff) << 56) | ((x        & (uint64_t)0x0000ff00) << 40) | ((x        & (uint64_t)0x00ff0000) << 24) | ((x        & (uint64_t)0xff000000) <<  8) |
         ((x >>  8) & (uint64_t)0xff000000)        | ((x >> 24) & (uint64_t)0x00ff0000)        | ((x >> 40) & (uint64_t)0x0000ff00)        | ((x >> 56) & (uint64_t)0x000000ff);
}

#     if defined(_WRS_INLINE)
_WRS_INLINE uint32_t
#     else
static __inline__ uint32_t
#     endif
cpu_to_le32(
  uint32_t x)
{
  return ((x & (uint32_t)0x00ff) << 24) | ((x & (uint32_t)0xff00) << 8) | ((x >> 8) & (uint32_t)0xff00) | ((x >> 24) & (uint32_t)0x00ff);
}

#     if defined(_WRS_INLINE)
_WRS_INLINE uint16_t
#     else
static __inline__ uint16_t
#     endif
cpu_to_le16(
  uint16_t x)
{
  return ((x & (uint16_t)0xff) << 8) | ((x >> 8) & (uint16_t)0xff);
}

#     define cpu_to_le8(x)  (x)
#     define le64_to_cpu(x) cpu_to_le64(x)
#     define le32_to_cpu(x) cpu_to_le32(x)
#     define le16_to_cpu(x) cpu_to_le16(x)
#     define le8_to_cpu(x)  (x)

#     define cpu_to_be64(x) cpu_to_le64(x)
#     define cpu_to_be32(x) cpu_to_le32(x)
#     define cpu_to_be16(x) cpu_to_le16(x)
#     define cpu_to_be8(x)  (x)
#     define be64_to_cpu(x) cpu_to_le64(x)
#     define be32_to_cpu(x) cpu_to_le32(x)
#     define be16_to_cpu(x) cpu_to_le16(x)
#     define be8_to_cpu(x)  (x)

#   else /* end of (_BYTE_ORDER == _BIG_ENDIAN) */

/* Little-endian byte order */

#     define cpu_to_le64(x) (x)
#     define cpu_to_le32(x) (x)
#     define cpu_to_le16(x) (x)
#     define cpu_to_le8(x)  (x)
#     define le64_to_cpu(x) (x)
#     define le32_to_cpu(x) (x)
#     define le16_to_cpu(x) (x)
#     define le8_to_cpu(x)  (x)

#     define cpu_to_be64(x) cpu_to_le64(x)
#     define cpu_to_be32(x) cpu_to_le32(x)
#     define cpu_to_be16(x) cpu_to_le16(x)
#     define cpu_to_be8(x)  (x)
#     define be64_to_cpu(x) cpu_to_be64(x)
#     define be32_to_cpu(x) cpu_to_le32(x)
#     define be16_to_cpu(x) cpu_to_le16(x)
#     define be8_to_cpu(x)  (x)

#   endif /* end of !(_BYTE_ORDER == _BIG_ENDIAN) */
# else

#   error Macro _BYTE_ORDER is not defined. Cannot detect endianness of this architecture.

# endif

#else
  
# error Cannot detect platform at compile-time. Build will fail.

#endif

#endif
