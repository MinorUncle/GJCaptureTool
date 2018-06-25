//
//  GJList.h
//  GJLiveEngine
//
//  Created by melot on 2018/6/25.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#ifndef GJList_h
#define GJList_h
#include "GJLog.h"
#include "GMemCheck.h"

#include <stdio.h>
#include "GJPlatformHeader.h"

typedef struct _GJListNode {
    GUInt8* data;
    struct _GJListNode* next;
}GJListNode;

static inline GJListNode* listCreate(GHandle data){
    GJListNode* node = (GJListNode*)malloc(sizeof(GJListNode));
    node->data = data;
    node->next = GNULL;
    return node;
}
static inline GVoid listFree(GJListNode* node){
    free(node);
}

static inline GHandle listData(GJListNode* node){
    return node->data;
}

static inline GVoid listInsert(GJListNode* sup,GJListNode* next){
    GJAssert(sup != GNULL && next!= GNULL, "不能为GNULL");
    next->next = sup->next;
    sup->next = next;
}
GVoid listDelete(GJListNode* sup,GJListNode* next);
#endif /* GJList_h */
