//
//  GMemCheck.c
//  libQueue
//
//  Created by 未成年大叔 on 2017/12/31.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GMemCheck.h"
#include <stdlib.h>


#if MENORY_CHECK
#include <assert.h>

typedef struct _GMemCheckInfoHead{
    GLong is19911024;
    GLong size;
}GMemCheckInfoHead;
typedef struct _GMemCheckInfoTail{
    GLong size;
    GLong is19911024;
}GMemCheckInfoTail;

#undef malloc
#undef free
#undef calloc
#undef realloc
void    *malloc(size_t __size) __result_use_check __alloc_size(1);
void     free(void *);
void    *realloc(void *__ptr, size_t __size) __result_use_check __alloc_size(2);
void    *calloc(size_t __count, size_t __size) __result_use_check __alloc_size(1,2);

GVoid* GMalloc(GSize_t __size){
    GUInt8* data = (GUInt8*)malloc(__size+sizeof(GMemCheckInfoHead) + sizeof(GMemCheckInfoTail));
    GMemCheckInfoHead* head = (GMemCheckInfoHead*)data;
    head->is19911024 = 19911024;
    head->size = __size;
    
    GMemCheckInfoTail* tail  = (GMemCheckInfoTail*)(data + sizeof(GMemCheckInfoHead) + __size);
    tail->is19911024 = 19911024;
    tail->size = __size;
    
    return data + sizeof(GMemCheckInfoHead);
}

GVoid GFree(GVoid *__ptr){
    
    GUInt8* data = (GUInt8*)__ptr;
    GMemCheckInfoHead* head = (GMemCheckInfoHead*)(data - sizeof(GMemCheckInfoHead));
    GMemCheckInfoTail* tail = (GMemCheckInfoTail*)(data + head->size);
    assert(head->size == tail->size);
    assert(head->is19911024 == 19911024);
    assert(tail->is19911024 == 19911024);
    head->size = tail->size = 0;
    head->is19911024 = tail->is19911024 = 0;
    free(data - sizeof(GMemCheckInfoHead));
}

GVoid *GRealloc(GVoid *__ptr, GSize_t __size){
    if (__ptr == GNULL) {
        return GMalloc(__size);
    }else{
        
         GUInt8* data = (GUInt8*)__ptr;
         GMemCheckInfoHead* head = (GMemCheckInfoHead*)(data - sizeof(GMemCheckInfoHead));
         GMemCheckInfoTail* tail = (GMemCheckInfoTail*)(data + head->size);
         assert(head->size == tail->size);
         assert(head->is19911024 == 19911024);
         assert(tail->is19911024 == 19911024);
         
         head = realloc(head,__size+sizeof(GMemCheckInfoHead) + sizeof(GMemCheckInfoTail));
         head->is19911024 = 19911024;
         head->size = __size;
         
         tail = (GMemCheckInfoTail*)((GUInt8*)head + sizeof(GMemCheckInfoHead) + __size);
         tail->is19911024 = 19911024;
         tail->size = __size;
         return head+1;
    }
}

GVoid* GCalloc(GSize_t __count, GSize_t __size){
    GSize_t checkSize = sizeof(GMemCheckInfoHead) + sizeof(GMemCheckInfoTail);
    GUInt8* data = (GUInt8*)calloc(__count,__size + checkSize);//第一个需要head,最后一个需要tail, 每个都必须一样大，所以每个都分配一个head和一个tail，
    GSize_t size = (__size+ checkSize) * __count - checkSize;//要减去第一个head和最后一个tail,
    GMemCheckInfoHead* head = (GMemCheckInfoHead*)data;
    head->is19911024 = 19911024;
    head->size = size;
    
    GMemCheckInfoTail* tail = (GMemCheckInfoTail*)(data + sizeof(GMemCheckInfoHead) + size);
    tail->is19911024 = 19911024;
    tail->size = size;
    
    return data + sizeof(GMemCheckInfoHead);
    
}

#define malloc GMalloc
#define free GFree
#define realloc GRealloc
#define calloc GCalloc

#else

#undef malloc
#undef free
#undef realloc
#undef calloc

void    *malloc(size_t __size) __result_use_check __alloc_size(1);
void     free(void *);
void    *realloc(void *__ptr, size_t __size) __result_use_check __alloc_size(2);
void    *calloc(size_t __count, size_t __size) __result_use_check __alloc_size(1,2);

GVoid* GMalloc(GSize_t __size){
    return malloc(__size);
}

GVoid* GCalloc(size_t __count, GSize_t __size){
    return calloc(__count, __size);
}

GVoid GFree(GVoid *__ptr){
    free(__ptr);
}

GVoid *GRealloc(GVoid *__ptr, GSize_t __size){
    return realloc(__ptr,__size);
}
#endif

