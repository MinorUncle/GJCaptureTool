//
//  GJPictureDisplayContext.c
//  GJCaptureTool
//
//  Created by melot on 2017/5/16.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJBridegContext.h"
#include "GJLog.h"
static GBool pipleProduceDataCallback(GJPipleNode* node, GJRetainBuffer* data,GJMediaType dataType){
    pipleNodeLock(node);
    for (int i = 0; i < node->subCount; i++) {
        node->subNodes[i]->receiveData(node->subNodes[i],data,dataType);
    }
    pipleNodeUnLock(node);
    return GTrue;
}

NodeFlowDataFunc pipleNodeFlowFunc(GJPipleNode* node){
    return pipleProduceDataCallback;
}

NodeFlowDataFunc pipleNodeInit(GJPipleNode* node,NodeFlowDataFunc receiveData){
    GJAssert(node && node->lock == GNULL && node->subNodes == GNULL, "重复初始化，或者初始化前没有清零");
    node->lock = malloc(sizeof(pthread_mutex_t));
    node->receiveData = GNULL;
    node->subCount = 0;
    node->receiveData = receiveData;
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    GInt result = pthread_mutex_init(node->lock, &attr);
    pthread_mutexattr_destroy(&attr);
    GJAssert(result == 0, "pthread_rwlock_init error");
    return pipleProduceDataCallback;
}

GBool pipleNodeUnInit(GJPipleNode* node){
    GJAssert(node->subCount == 0 && node->subNodes == GNULL, "存在连接的节点未初始化,或者没有断开连接");
    if (node->lock) {
        pthread_mutex_destroy(node->lock);
        free(node->lock);
        node->lock = GNULL;
    }
    return GTrue;
}


GBool pipleConnectNode(GJPipleNode* superNode,GJPipleNode* subNode){
    GJAssert(superNode && superNode->lock != GNULL && subNode, "GJPipleConnectNode error");
    pthread_mutex_lock(superNode->lock);
    GBool find = GFalse;
    for (int i = 0; i< superNode->subCount; i++) {
        if (superNode->subNodes[i] == subNode) {
            find = GTrue;
        }
    }
    if (!find) {
        superNode->subNodes = realloc(superNode->subNodes, sizeof(GJPipleNode*)*(superNode->subCount+1));
        superNode->subNodes[superNode->subCount++] = subNode;
    }
    pthread_mutex_unlock(superNode->lock);
    return GTrue;
}

GBool pipleDisConnectNode(GJPipleNode* superNode, GJPipleNode* subNode){
    GJAssert(superNode && superNode->lock != GNULL, "GJPipleDisConnectNode error");
    pthread_mutex_lock(superNode->lock);
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
    pthread_mutex_unlock(superNode->lock);
    return GTrue;
}


