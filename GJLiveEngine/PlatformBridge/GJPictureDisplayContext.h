//
//  GJPictureDisplayContext.h
//  GJCaptureTool
//
//  Created by melot on 2017/5/16.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJPictureDisplayContext_h
#define GJPictureDisplayContext_h
#include "GJLiveDefine.h"
#include <stdio.h>
typedef struct _GJPictureDisplayContext{
    GHandle obaque;
    GBool (*displayInit) (struct _GJPictureDisplayContext* context,GJPixelFormat format);
    GVoid (*displayView) (struct _GJPictureDisplayContext* context,GHandle image);
}GJPictureDisplayContext;
#endif /* GJPictureDisplayContext_h */
