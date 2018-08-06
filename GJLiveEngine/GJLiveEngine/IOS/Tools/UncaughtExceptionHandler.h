//
//  UncaughtExceptionHandler.h
//  GJLiveEngine
//
//  Created by melot on 2018/6/8.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface UncaughtExceptionHandler : NSObject
{
    BOOL dismissed;
}

+ (void)InstallUncaughtExceptionHandler;

@end
