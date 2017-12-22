//
//  GJPictureDisplayContext.c
//  GJCaptureTool
//
//  Created by melot on 2017/5/16.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJBridegContext.h"
#include "GJLog.h"
static inline GBool isSubNode(GJPipleNode* superNode,GJPipleNode* subNode){
    GBool findNode = GFalse;
    for (int i = 0; i<superNode->subCount; i++) {
        if (superNode->subNodes[i] == subNode) {
            findNode = GTrue;
            break;
        }
    }
    return GTrue;
}
static inline GBool isSuperNode(GJPipleNode* subNode,GJPipleNode* superNode){
    GBool findNode = GFalse;
    for (int i = 0; i<subNode->superCount; i++) {
        if (subNode->superNodes[i] == superNode) {
            findNode = GTrue;
            break;
        }
    }
    return GTrue;
}

static inline GVoid subAddSuper(GJPipleNode* subNode,GJPipleNode* superNode){
    if (subNode->superNodes == GNULL) {
        subNode->superNodes = malloc(sizeof(GJPipleNode*));
        subNode->superCount = 1;
    }else{
        if (!isSuperNode(subNode, superNode)) {
            subNode->superCount++;
            subNode->superNodes = (GJPipleNode**)realloc(subNode->superNodes, sizeof(GJPipleNode*)*subNode->superCount);
            subNode->superNodes[subNode->superCount-1] = superNode;
        }
    }
}

static inline GVoid superAddSub(GJPipleNode* superNode,GJPipleNode* subNode){
    if (superNode->subNodes == GNULL) {
        superNode->subNodes = malloc(sizeof(GJPipleNode*));
        superNode->subCount = 1;
    }else{
        if (!isSubNode(superNode, subNode)) {
            superNode->subCount++;
            superNode->subNodes = (GJPipleNode**)realloc(superNode->subNodes, sizeof(GJPipleNode*)*superNode->subCount);
            superNode->subNodes[superNode->subCount-1] = subNode;
        }
    }
}

static inline GVoid superDelSub(GJPipleNode* superNode,GJPipleNode* subNode){
#ifdef DEBUG
    GJAssert(isSubNode(superNode, subNode), "check error");
#endif
    GBool found = GFalse;
    for (int i = 0 ; i < superNode->subCount; i++) {
        if (!found) {
            if (superNode->subNodes[i] == subNode) {
                found = GTrue;
            }
        }else{
            superNode->subNodes[i-1] = superNode->subNodes[i];
        }
    }
    
    if (found) {
        superNode->subCount--;
        if (superNode->subCount > 0) {
            superNode->subNodes = (GJPipleNode**)realloc(superNode->subNodes, sizeof(GJPipleNode*)*superNode->subCount);
        }else{
            free(superNode->subNodes);
            superNode->subNodes = GNULL;
        }
    }

}
static inline GVoid subDelSuper(GJPipleNode* subNode,GJPipleNode* superNode){
    GBool found = GFalse;
    for (int i = 0 ; i < subNode->superCount; i++) {
        if (!found) {
            if (subNode->superNodes[i] == superNode) {
                found = GTrue;
            }
        }else{
            subNode->superNodes[i-1] = subNode->superNodes[i];
        }
    }
    
    if (found) {
        subNode->superCount--;
        if (subNode->superCount > 0) {
            subNode->superNodes = (GJPipleNode**)realloc(subNode->superNodes, sizeof(GJPipleNode*)*subNode->superCount);
        }else{
            free(subNode->superNodes);
            subNode->superNodes = GNULL;
        }
    }
}

GBool GJPipleConnectNode(GJPipleNode* superNode,GJPipleNode* subNode){
#ifdef DEBUG
    GBool isSuper = isSuperNode(subNode, superNode);
    GBool isSub = isSubNode(superNode, subNode);
    GJAssert(isSub == isSuper, "check error");
    GJAssert(isSub == GFalse, "check error");
#endif
    superAddSub(superNode, subNode);
    subAddSuper(subNode, superNode);
#ifdef DEBUG
    isSuper = isSuperNode(subNode, superNode);
    isSub = isSubNode(superNode, subNode);
    GJAssert(isSub == isSuper, "check error");
    GJAssert(isSub == GTrue, "check error");
#endif
    return GTrue;
}

GBool GJPilpeIsOrphan(GJPipleNode* node){
    return node->superCount > 0;
}
GVoid GJPipleDestoryOrphanNode(GJPipleNode* node){
    GJAssert(GJPilpeIsOrphan(node), "check error");
    for (int i = 0; i<node->subCount ;i++) {
        subDelSuper(node->subNodes[i], node);
        if (GJPilpeIsOrphan(node->superNodes[i])) {
            GJPipleDestoryOrphanNode(node->subNodes[i]);
        }
    }
    free(node->subNodes);
    node->subCount = 0;
    node->subNodes = GNULL;
    if (node->nodeDealloc) {
        node->nodeDealloc();
    }
}

GBool GJPipleDisConnectNode(GJPipleNode* superNode, GJPipleNode* subNode, GBool destoryOrphan){
#ifdef DEBUG
    GBool isSuper = isSuperNode(subNode, superNode);
    GBool isSub = isSubNode(superNode, subNode);
    GJAssert(isSub == isSuper, "check error");
    GJAssert(isSub == GTrue, "check error");
#endif
    superDelSub(superNode, subNode);
    subDelSuper(subNode, superNode);
    if (GJPilpeIsOrphan(subNode)) {
        GJPipleDestoryOrphanNode(subNode);
    }
#ifdef DEBUG
    isSuper = isSuperNode(subNode, superNode);
    isSub = isSubNode(superNode, subNode);
    GJAssert(isSub == isSuper, "check error");
    GJAssert(isSub == GFalse, "check error");
#endif
    return GTrue;
}

//GBool GJPipleDisConnectNode(GJPipleNode* superNode, GJPipleNode* subNode, GBool destoryIncomplete){
//#ifdef DEBUG
//    GBool isSuper = isSuperNode(subNode, superNode);
//    GBool isSub = isSubNode(superNode, subNode);
//    GJAssert(isSub == isSuper, "check error");
//    GJAssert(isSub == GTrue, "check error");
//#endif
//    GBool findNode = GFalse;
//    for (int i = 0; i<superNode->subCount; i++) {
//        if (findNode) {
//            superNode->subNodes[i-1] = superNode->subNodes[i];
//        }else{
//            if (superNode->subNodes[i] == subNode) {
//                findNode = GTrue;
//                if(destoryIncomplete){
//                    GJPipleDestoryTree(subNode);
//                }else{
//                    free(subNode->subNodes);
//                    subNode->subNodes = GNULL;
//                    if (subNode->nodeDealloc) {
//                        subNode->nodeDealloc();
//                    }
//                }
//            }
//        }
//    }
//    if (findNode) {
//        superNode->subCount--;
//        superNode->subNodes = (GJPipleNode**)realloc(superNode->subNodes, sizeof(GJPipleNode*)*superNode->subCount);
//        GJAssert(superNode->subCount >= 0,"error");
//    }
//    return GTrue;
//}

