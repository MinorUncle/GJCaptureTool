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
    GHandle sender;
    GHandle receiver;
    GInt8 type;
    GLong arg;
};

struct _GJMessageDispatcher{
    pthread_t thread;
    GBool   running;
    GChar*  threadName;
    GJQueue* messageQueue;
};

static GJMessageDispatcher* staticDispatcher;
static int dispatcherGuard;
GJMessage* createMessage(MessageHandle handle,GHandle sender,GHandle receive,GInt32 type,GLong arg){
    GJMessage* message = malloc(sizeof(GJMessage));
    message->handle = handle;
    message->sender = sender;
    message->receiver = receive;
    message->type = type;
    message->arg = arg;
    return message;
}

static GHandle messageRunLoop(GHandle parm) {
    GJMessageDispatcher* dispatcher = parm;
    GJMessage* message;
    pthread_setname_np(dispatcher->threadName);
    while (dispatcher->running && queuePop(dispatcher->messageQueue, (GHandle*)&message, GINT32_MAX)) {
        message->handle(message->sender,message->receiver,message->type,message->arg);
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
            staticDispatcher->threadName = "messageRunLoop";
            GResult result = pthread_create(&staticDispatcher->thread , GNULL, messageRunLoop, staticDispatcher);
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

void deliveryMessage(GJMessageDispatcher* dispatcher,MessageHandle handle,GHandle sender,GHandle receive,GInt32 type,GLong arg){
    
    queuePush(dispatcher->messageQueue, createMessage(handle, sender, receive, type, arg), GINT32_MAX);
}

void defauleDeliveryMessage0(MessageHandle handle,GHandle sender,GHandle receive,GInt32 type){
    queuePush(defaultDispatcher()->messageQueue, createMessage(handle, sender, receive, type, 0), GINT32_MAX);
}
void defauleDeliveryMessage1(MessageHandle handle,GHandle sender,GHandle receive,GInt32 type,GLong arg){
    queuePush(defaultDispatcher()->messageQueue, createMessage(handle, sender, receive, type, arg), GINT32_MAX);
}
