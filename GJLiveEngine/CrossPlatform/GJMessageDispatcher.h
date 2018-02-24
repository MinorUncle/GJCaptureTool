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
typedef void (*MessageHandle)(GHandle receive,GInt32 type,GVoid* arg);
GJMessage* createMessage(MessageHandle handle,GHandle receive,GInt32 type,GVoid* arg);
GJMessageDispatcher* defaultDispatcher();
void destroyDispatcher(GJMessageDispatcher* dispatcher);
void deliveryMessage(GJMessageDispatcher* dispatcher,GJMessage* message);
#endif /* GJMessageDispatcher_h */
