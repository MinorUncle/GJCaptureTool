//
//  GJPlatformHeader.h
//  GJQueue
//
//  Created by melot on 2017/4/28.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJPlatformHeader_h
#define GJPlatformHeader_h

#ifdef DEBUG
#define MEMORY_CHECK 1
#else
#define MEMORY_CHECK 0
#endif
#define CLOSE_WHILE_STREAM_COMPLETE 0
#define DEFAULT_TRACKER __func__

#include <stdio.h>

#define offsetof(t, d) __builtin_offsetof(t, d)




#define GTrue (GInt8)1
#define GFalse (GInt8)0
#define GNULL NULL

#define GINT8_MAX 127
#define GINT8_MIN -127
#define GUINT8_MAX 255
#define GUINT8_MIN 0

#define GINT16_MAX 32767
#define GINT16_MIN -32767
#define GUINT16_MAX 65535
#define GUINT16_MIN 0

#define GINT32_MAX 2147483647
#define GINT32_MIN -2147483647
#define GUINT32_MAX 4294967296
#define GUINT32_MIN 0

#define GINT64_MAX 9223372036854775807LL
#define GINT64_MIN -9223372036854775807LL
#define GUINT64_MAX (GINT64_MAX<<1+1)
#define GUINT64_MIN 0

typedef uint8_t             GUInt8;
typedef int8_t              GInt8;
typedef uint16_t            GUInt16;
typedef int16_t             GInt16;
typedef uint32_t            GUInt32;
typedef int32_t             GInt32;
typedef uint64_t            GUInt64;
typedef int64_t             GInt64;
typedef int                 GInt;

typedef long                GLong;
typedef unsigned long       GULong;
typedef float               GFloat32;
typedef double              GFloat64;
typedef GInt8               GBool;
typedef char                GChar;
typedef unsigned char       GUChar;

typedef void                GVoid;
typedef void*               GHandle;

typedef size_t              GSize_t;

typedef int32_t             GResult;

#define GOK                 0
#define GERR_NOMEM          1
#define GERR_TIMEDOUT       2



#define GMIN(A,B)	({ __typeof__(A) __a = (A); __typeof__(B) __b = (B); __a < __b ? __a : __b; })
#define GMAX(A,B)	({ __typeof__(A) __a = (A); __typeof__(B) __b = (B); __a < __b ? __b : __a; })
#define GFloatEqual(A,B)({GFloat32 d = (GFloat32)A - (GFloat32)B;d > -0.00001 && d < 0.00001;})
#if defined( __cplusplus )
#   define DEFAULT_PARAM(x) =x
#else
#   define DEFAULT_PARAM(x)
#endif

#define  GALIGN(A,B) ((A) & ~(B-1))

#endif /* GJPlatformHeader_h */
