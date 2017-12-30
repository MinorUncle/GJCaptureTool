//
//  GJPictureDisplayContext.c
//  GJCaptureTool
//
//  Created by melot on 2017/5/16.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJBridegContext.h"
#include "GJLog.h"
GBool pipleNodeInit(GJPipleNode* node,NodeReceiveDataFunc receiveData){
    GJAssert(node && node->lock == GNULL && node->subNodes == GNULL, "重复初始化，或者初始化前没有清零");
    node->lock = malloc(sizeof(pthread_rwlock_t));
    node->receiveData = GNULL;
    node->subCount = 0;
    node->receiveData = receiveData;
    GInt result = pthread_rwlock_init(node->lock, GNULL);
    GJAssert(result == 0, "pthread_rwlock_init error");
    return result == 0;
}

GBool pipleNodeUnInit(GJPipleNode* node){
    GJAssert(node->subCount == 0 && node->subNodes == GNULL, "存在连接的节点未初始化");
    if (node->lock) {
        pthread_rwlock_destroy(node->lock);
        free(node->lock);
        node->lock = GNULL;
    }
    return GTrue;
}


GBool pipleConnectNode(GJPipleNode* superNode,GJPipleNode* subNode){
    GJAssert(superNode && superNode->lock != GNULL, "GJPipleConnectNode error");
    pthread_rwlock_wrlock(superNode->lock);
    GBool find = GFalse;
    for (int i = 0; i< superNode->subCount; i++) {
        if (superNode->subNodes[i] == subNode) {
            find = GTrue;
        }
    }
    if (!find) {
        superNode->subNodes = realloc(superNode->subNodes, sizeof(GJPipleNode*)*superNode->subCount+1);
        superNode->subNodes[superNode->subCount++] = subNode;
    }
    pthread_rwlock_unlock(superNode->lock);
    return GTrue;
}

GBool pipleDisConnectNode(GJPipleNode* superNode, GJPipleNode* subNode){
    GJAssert(superNode && superNode->lock != GNULL, "GJPipleDisConnectNode error");
    pthread_rwlock_wrlock(superNode->lock);
    GBool find = GFalse;
    for (int i = 0; i< superNode->subCount; i++) {
        if (find) {
            superNode->subNodes[i-1] = superNode->subNodes[i];
        }else if (superNode->subNodes[i] == subNode) {
            find = GTrue;
        }
    }
    if (find) {
        superNode->subCount--;
        if (superNode->subCount == 0) {
            free(superNode->subNodes);
            superNode->subNodes = GNULL;
        }else{
            superNode->subNodes = realloc(superNode->subNodes, sizeof(GJPipleNode*)*superNode->subCount);
        }
    }
    pthread_rwlock_unlock(superNode->lock);
    return GTrue;
}


