//
//  GMemCheck.h
//  libQueue
//
//  Created by 未成年大叔 on 2017/12/31.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GMemCheck_h
#define GMemCheck_h

#include <stdio.h>
#include <stdlib.h>
#include "GJPlatformHeader.h"

GVoid* GMalloc(GSize_t __size);
GVoid GFree(GVoid *__ptr);
GVoid *GRealloc(GVoid *__ptr, GSize_t __size);
GVoid* GCalloc(GSize_t __count, GSize_t __size);

#if MENORY_CHECK
#define GMemCheck(_x)                                                                    \
do{     GUInt8* data = (GUInt8*)(_x);                                                      \
        GMemCheckInfo* head = (GMemCheckInfo*)(data - sizeof(GMemCheckInfo));               \
        GMemCheckInfo* tail = (GMemCheckInfo*)(data + head->size);                          \
        assert(head->size == tail->size);                                                   \
        assert(head->is19911024 == 19911024);                                               \
        assert(tail->is19911024 == 19911024);                                               \
}while(0)
#else
    #define GMemCheck(__ptr)
#endif

#endif /* GMemCheck_h */
