//
//  GJPlatformHeader.h
//  GJQueue
//
//  Created by melot on 2017/4/28.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJPlatformHeader_h
#define GJPlatformHeader_h


#include <stdio.h>
#include "GJPlatformHeader.h"

#define GTrue 1
#define GFalse 0
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
#define GUINT64_MAX GINT64_MAX*2+1
#define GUINT64_MIN 0

typedef uint8_t             GUInt8;
typedef int8_t              GInt8;
typedef uint16_t            GUInt16;
typedef int16_t             GInt16;
typedef uint32_t            GUInt32;
typedef int32_t             GInt32;
typedef uint64_t            GUInt64;
typedef int64_t             GInt64;
typedef long                GLong;
typedef unsigned long       GULong;
typedef float               GFloat32;
typedef double              GFloat64;
typedef GInt8               GBool;
typedef char                GChar;
typedef unsigned char       GUChar;

typedef void                GVoid;
typedef void*               GHandle;

typedef int64_t             GTime;
#define G_TIME_INVALID             -2147483646



typedef int32_t             GResult;
#define GOK                 0
#define GERR_NOMEM          1
#define GERR_TIMEDOUT       2

#define GMIN(A,B)	({ __typeof__(A) __a = (A); __typeof__(B) __b = (B); __a < __b ? __a : __b; })
#define GMAX(A,B)	({ __typeof__(A) __a = (A); __typeof__(B) __b = (B); __a < __b ? __b : __a; })


#if defined( __cplusplus )
#   define QUEUE_DEFAULT(x) =x
#else
#   define QUEUE_DEFAULT(x)
#endif

#endif /* GJPlatformHeader_h */
