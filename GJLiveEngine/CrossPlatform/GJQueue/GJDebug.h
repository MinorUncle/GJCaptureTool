//
//  GJDebug.h
//  GJQueue
//
//  Created by mac on 17/2/22.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJDebug_h
#define GJDebug_h
#include <assert.h>

#ifdef DEBUG
#define GJLOG(format, ...) NSLog(format,##__VA_ARGS__)
#define GJPrintf(format, ...) printf(format,##__VA_ARGS__)

#if __DARWIN_UNIX03
#define	GJAssert(e,format, ...) do{\
if(!(e)){\
printf(format,##__VA_ARGS__);\
}\
(__builtin_expect(!(e), 0) ? __assert_rtn(__func__, __FILE__, __LINE__, #e) : (void)0);\
}while(0)
#else /* !__DARWIN_UNIX03 */
#define assert(e)  do{\
if(!(e)){\
printf(format,##__VA_ARGS__);\
}\
(__builtin_expect(!(e), 0) ? __assert (#e, __FILE__, __LINE__) : (void)0)\
}while(0)
#endif /* __DARWIN_UNIX03 */

#else
#define GJLOG(format, ...)
#define GJPrintf(format, ...)
#define	GJAssert(e) ((void)0)

#endif
#endif /* GJDebug_h */
