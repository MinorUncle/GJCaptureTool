//
//  AutoLock.h
//  GJLiveEngine
//
//  Created by melot on 2018/5/15.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AutoLock : NSObject {
    NSObject<NSLocking> *_lock;
}
+ (instancetype)local:(NSObject<NSLocking> *)lock;
@end

#define AUTO_LOCK(lock)                  \
    AutoLock *a = [AutoLock local:lock]; \
    a           = a;
