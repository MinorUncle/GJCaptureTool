//
//  GJUtil.h
//  GJCaptureTool
//
//  Created by melot on 2017/5/11.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJUtil_h
#define GJUtil_h
#include "GJPlatformHeader.h"

/**
 获得当前时间

 @return scale in us
 */
GTime GJ_Gettime();

GInt32 GJ_GetCPUCount();
GFloat32 GJ_GetCPUUsage();

#endif /* GJUtil_h */
