//
//  GJList.c
//  GJLiveEngine
//
//  Created by melot on 2018/6/25.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#include "GJList.h"



GVoid listDelete(GJListNode* sup,GJListNode* next){
    GJAssert(sup != GNULL && next!= GNULL, "不能为GNULL");
    while (sup) {
        if (sup->next == next) {
            sup->next = next->next;
            break;
        }
        sup = sup->next;
    }
}
