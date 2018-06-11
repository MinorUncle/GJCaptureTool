//
//  GJMessageDispatcher.h
//  GJLiveEngine
//
//  Created by melot on 2018/2/24.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#ifndef GJMessageDispatcher_h
#define GJMessageDispatcher_h
#include "GJPlatformHeader.h"

#include <stdio.h>

typedef struct _GJMessageDispatcher GJMessageDispatcher;
typedef struct _GJMessage GJMessage;
typedef void (*MessageHandle)(GHandle sender, GHandle receiver,GInt32 type,GLong arg);
GJMessageDispatcher* defaultDispatcher();
//void destroyDispatcher(GJMessageDispatcher* dispatcher);
//void deliveryMessage(GJMessageDispatcher* dispatcher,MessageHandle handle,GHandle sender,GHandle receive,GInt32 type,GLong arg);

void defauleDeliveryMessage0(MessageHandle handle,GHandle sender,GHandle receive,GInt32 type);
void defauleDeliveryMessage1(MessageHandle handle,GHandle sender,GHandle receive,GInt32 type,GLong arg);

#endif /* GJMessageDispatcher_h */
