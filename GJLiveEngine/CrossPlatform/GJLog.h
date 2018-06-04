/*
 *  Copyright (C) 2008-2009 Andrej Stepanchuk
 *  Copyright (C) 2009-2010 Howard Chu
 *
 *  This file is part of librtmp.
 *
 *  librtmp is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU Lesser General Public License as
 *  published by the Free Software Foundation; either version 2.1,
 *  or (at your option) any later version.
 *
 *  librtmp is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public License
 *  along with librtmp see the file COPYING.  If not, write to
 *  the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 *  Boston, MA  02110-1301, USA.
 *  http://www.gnu.org/copyleft/lgpl.html
 */

#ifndef __KK_LOG_H__
#define __KK_LOG_H__

#include <stdio.h>
#include <stdarg.h>
#include <stdint.h>
#include "GJPlatformHeader.h"
#ifdef __cplusplus
extern "C" {
#endif
/* Enable this to get full debugging */
/* #define _DEBUG */

#define GJ_DEBUG

#define DEFAULT_LOG GNULL

#define GJ_DEBUG_FREQUENTLY

typedef enum {
    GJ_LOGNONE,   ///永远不产生log
    GJ_LOGFORBID, //调试包会产生中断，
    GJ_LOGERROR,
    GJ_LOGWARNING,
    GJ_LOGDEBUG,
    GJ_LOGINFO,
    GJ_LOGALL
} GJ_LogLevel;

typedef struct _GJClass {
    GChar *     className;
    GJ_LogLevel dLevel;
} GJClass;

static const GJClass Default_NONE = {
    .className = GNULL,
    .dLevel    = GJ_LOGNONE,
};
#define LOG_NONE (&Default_NONE)

static const GJClass Default_FORBID = {
    .className = GNULL,
    .dLevel    = GJ_LOGFORBID,
};

#define LOG_FORBID (&Default_FORBID)

static const GJClass Default_ERROR = {
    .className = GNULL,
    .dLevel    = GJ_LOGERROR,
};
#define LOG_ERROR (&Default_ERROR)

static const GJClass Default_WARNING = {
    .className = GNULL,
    .dLevel    = GJ_LOGWARNING,
};
#define LOG_WARNING (&Default_WARNING)

static const GJClass Default_DEBUG = {
    .className = GNULL,
    .dLevel    = GJ_LOGDEBUG,
};
#define LOG_DEBUG (&Default_DEBUG)

static const GJClass Default_INFO = {
    .className = GNULL,
    .dLevel    = GJ_LOGINFO,
};
#define LOG_INFO (&Default_INFO)

static const GJClass Default_ALL = {
    .className = GNULL,
    .dLevel    = GJ_LOGALL,
};
#define LOG_ALL (&Default_ALL)

extern GJClass *defaultDebug;

typedef GVoid(GJ_LogCallback)(GJClass *logClass, GJ_LogLevel level, const char *pre, const char *fmt, va_list);

//小于GJ_debuglevel则显示
GVoid GJ_LogSetLevel(GJ_LogLevel lvl);

GVoid GJ_LogSetCallback(GJ_LogCallback *cb);
GVoid GJ_LogSetOutput(char *file);

GVoid GJ_Log(const GVoid *logClass, GJ_LogLevel level, const char *pre, const char *format, ...) __printflike(4, 5);
GVoid GJ_LogHex(GJ_LogLevel level, const GUInt8 *data, GUInt32 len);
GVoid GJ_LogHexString(GJ_LogLevel level, const GUInt8 *data, GUInt32 len);

//所有等级都会打印，但是大于GJ_LOGDEBUG模式会产生中断
GVoid GJ_LogAssert(GInt32 isTrue,const char *pre,const char *format, ...) __attribute__((format(printf, 3, 4)));
GBool GJ_LogCheckResult(GResult result, const char *pre, const char *format, ...);
GBool GJ_LogCheckBool(GBool result, const char *pre, const char *format, ...);

GJ_LogLevel GJ_LogGetLevel(GVoid);

#define GJCheckResult(isTrue, format, ...) GJ_LogCheckResult(isTrue, __func__, format, ##__VA_ARGS__)
#define GJCheckBool(isTrue, format, ...) GJ_LogCheckBool(isTrue, __func__, format, ##__VA_ARGS__)

#define GJAssert(isTrue, format, ...) GJ_LogAssert(isTrue, __func__, format, ##__VA_ARGS__)

#ifdef GJ_DEBUG

#define GJLOG(dclass, level, format, ...) GJ_Log((dclass), (level), __func__, format, ##__VA_ARGS__)

#ifdef GJ_DEBUG_FREQUENTLY

#define GJLOGFREQ(format, ...) GJ_Log(DEFAULT_LOG, GJ_LOGALL, __func__, format, ##__VA_ARGS__)
#else

#define GJLOGFREQ(level, format, ...)
#endif

#else
#define GJLOG(dclass, level, format, ...)
#define GJOLOG(switch, level, format, ...)
#define GJLOGFREQ(level, format, ...)
#endif
    
    
#ifdef __cplusplus
}
#endif

#endif
