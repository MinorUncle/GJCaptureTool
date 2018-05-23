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

#endif /* GMemCheck_h */
