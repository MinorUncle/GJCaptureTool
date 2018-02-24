//
//  GJMessageDispatcher.c
//  GJLiveEngine
//
//  Created by melot on 2018/2/24.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#include "GJMessageDispatcher.h"
#include "GJBridegContext.h"
#include "GJQueue.h"

struct _GJMessage{
    MessageHandle handle;
    GHandle receive;
    GInt8 type;
    GHandle arg;
};

struct _GJMessageDispatcher{
    pthread_t thread;
    GBool   running;
    GJQueue* messageQueue;
};

static GJMessageDispatcher* staticDispatcher;
static int dispatcherGuard;
GJMessage* createMessage(MessageHandle handle,GHandle receive,GInt32 type,GVoid* arg){
    GJMessage* message = malloc(sizeof(GJMessage));
    message->handle = handle;
    message->receive = receive;
    message->type = type;
    message->arg = arg;
    return message;
}

static GHandle messageRunLoop(GHandle parm) {
    GJMessageDispatcher* dispatcher = parm;
    GJMessage* message;
    while (dispatcher->running && queuePop(dispatcher->messageQueue, (GHandle*)&message, GINT32_MAX)) {
        message->handle(message->receive,message->type,message->arg);
        free(message);
    }
    return GNULL;
}

GJMessageDispatcher* defaultDispatcher(){
    while(staticDispatcher == GNULL) {
        if (!__sync_fetch_and_add(&dispatcherGuard,1)) {
            staticDispatcher = (GJMessageDispatcher*)calloc(sizeof(GJMessageDispatcher),1);
            queueCreate(&staticDispatcher->messageQueue, 10, GTrue, GTrue);
            staticDispatcher->running = GTrue;
            GResult result = pthread_create(&staticDispatcher->thread , GNULL, messageRunLoop, &defaultDispatcher);
            if (result) {
                free(staticDispatcher);
                staticDispatcher = GNULL;
            }
        }
    }
    return staticDispatcher;
}

void destroyDispatcher(GJMessageDispatcher* dispatcher){
    if (dispatcher) {
        dispatcher->running = GFalse;
        pthread_join(dispatcher->thread, GNULL);
        GHandle message;
        while (queuePop(dispatcher->messageQueue, &message, 0)) {
            GJLOG(GNULL, GJ_LOGFORBID, "还有没有分发的消息");
            free(message);
        }
        queueFree(&dispatcher->messageQueue);
        free(dispatcher);
        dispatcher = GNULL;
        dispatcherGuard = 0;
    }
}

void deliveryMessage(GJMessageDispatcher* dispatcher,GJMessage* message){
    queuePush(dispatcher->messageQueue, message, GINT32_MAX);
}
