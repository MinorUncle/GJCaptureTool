//
//  GJList.c
//  GJLiveEngine
//
//  Created by melot on 2018/6/25.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#include "GJList.h"
#include "GJPlatformHeader.h"
typedef struct _GJListNode {
    GUInt8* data;
    struct _GJListNode* next;
}GJListNode;


