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

typedef struct _GMemCheckInfo{
    GInt is19911024;
    GSize_t size;
}GMemCheckInfo;

#undef malloc
#undef free
#undef calloc
#undef realloc
void    *malloc(size_t __size) __result_use_check __alloc_size(1);
void     free(void *);
void    *realloc(void *__ptr, size_t __size) __result_use_check __alloc_size(2);
void    *calloc(size_t __count, size_t __size) __result_use_check __alloc_size(1,2);

GVoid* GMalloc(GSize_t __size){
    GUInt8* data = (GUInt8*)malloc(__size+sizeof(GMemCheckInfo)*2);
    GMemCheckInfo* info = (GMemCheckInfo*)data;
    info->is19911024 = 19911024;
    info->size = __size;
    
    info = (GMemCheckInfo*)(data + sizeof(GMemCheckInfo) + __size);
    info->is19911024 = 19911024;
    info->size = __size;
    
    return data + sizeof(GMemCheckInfo);
}

GVoid GFree(GVoid *__ptr){
    
    GUInt8* data = (GUInt8*)__ptr;
    GMemCheckInfo* head = (GMemCheckInfo*)(data - sizeof(GMemCheckInfo));
    GMemCheckInfo* tail = (GMemCheckInfo*)(data + head->size);
    assert(head->size == tail->size);
    assert(head->is19911024 == 19911024);
    assert(tail->is19911024 == 19911024);
    head->size = tail->size = 0;
    head->is19911024 = tail->is19911024 = 0;
    free(data - sizeof(GMemCheckInfo));
}

GVoid *GRealloc(GVoid *__ptr, GSize_t __size){
    if (__ptr == GNULL) {
        return GMalloc(__size);
    }else{
        
         GUInt8* data = (GUInt8*)__ptr;
         GMemCheckInfo* head = (GMemCheckInfo*)(data - sizeof(GMemCheckInfo));
         GMemCheckInfo* tail = (GMemCheckInfo*)(data + head->size);
         assert(head->size == tail->size);
         assert(head->is19911024 == 19911024);
         assert(tail->is19911024 == 19911024);
         
         head = realloc(head,__size+sizeof(GMemCheckInfo)*2);
         head->is19911024 = 19911024;
         head->size = __size;
         
         tail = (GMemCheckInfo*)((GUInt8*)head + sizeof(GMemCheckInfo) + __size);
         tail->is19911024 = 19911024;
         tail->size = __size;
         return head+1;

        
//        GUInt8* data = (GUInt8*)__ptr;
//        GMemCheckInfo* head = (GMemCheckInfo*)(data - sizeof(GMemCheckInfo));
//        GMemCheckInfo* tail = (GMemCheckInfo*)(data + head->size);
//        assert(head->size == tail->size);
//        assert(head->is19911024 == 19911024);
//        assert(tail->is19911024 == 19911024);
//
//        data = (data - sizeof(GMemCheckInfo));
//        data = (GUInt8*)realloc(data,__size+sizeof(GMemCheckInfo)*2);
//        GMemCheckInfo* info = (GMemCheckInfo*)data;
//        info->is19911024 = 19911024;
//        info->size = __size;
//
//        info = (GMemCheckInfo*)(data + sizeof(GMemCheckInfo) + __size);
//        info->is19911024 = 19911024;
//        info->size = __size;
//        return data + sizeof(GMemCheckInfo);
    }
}

GVoid* GCalloc(GSize_t __count, GSize_t __size){
    GSize_t size = (__size+sizeof(GMemCheckInfo)*2) * __count - sizeof(GMemCheckInfo)*2;
    GUInt8* data = (GUInt8*)calloc(__count,__size+sizeof(GMemCheckInfo)*2);
    GMemCheckInfo* info = (GMemCheckInfo*)data;
    info->is19911024 = 19911024;
    info->size = size;
    
    info = (GMemCheckInfo*)(data + sizeof(GMemCheckInfo) + size);
    info->is19911024 = 19911024;
    info->size = size;
    
    return data + sizeof(GMemCheckInfo);
    
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

