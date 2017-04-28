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


typedef enum
{
    GJ_LOGNONE,
    GJ_LOGERROR,
    GJ_LOGWARNING,
    GJ_LOGDEBUG,
    GJ_LOGINFO,
    GJ_LOGALL
} GJ_LogLevel;

extern GJ_LogLevel GJ_debuglevel;

typedef GVoid (GJ_LogCallback)(GInt32 level, const char *fmt, va_list);

//小于GJ_debuglevel则显示
GVoid GJ_LogSetLevel(GJ_LogLevel lvl);
    
    
    
    
GVoid GJ_LogSetCallback(GJ_LogCallback *cb);
GVoid GJ_LogSetOutput(FILE *file);
    
GVoid GJ_Log(GInt32 level, const char *format, ...);
GVoid GJ_LogHex(GInt32 level, const GUInt8 *data, GUInt32 len);
GVoid GJ_LogHexString(GInt32 level, const GUInt8 *data, GUInt32 len);

//所有等级都会打印，但是大于GJ_LOGDEBUG模式会产生中断
GVoid GJ_LogAssert(GInt32 isTrue,const char *format, ...);

GJ_LogLevel GJ_LogGetLevel(GVoid);
    
    
    
    
#ifdef GJ_DEBUG
#define GJLOG(level, format, ...) GJ_Log(level,format,##__VA_ARGS__)
#define GJAssert(isTrue, format, ...) GJ_LogAssert(isTrue,format,##__VA_ARGS__)
#else
#define GJLOG(level, format, ...)
#define GJAssert(isTrue, format, ...)
#endif

#ifdef __cplusplus
}
#endif

#endif
