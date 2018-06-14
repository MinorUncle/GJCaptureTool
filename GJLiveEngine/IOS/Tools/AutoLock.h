//
//  AutoLock.h
//  GJLiveEngine
//
//  Created by melot on 2018/5/15.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
//不能用此类，因为有时候不会马上释放
@interface AutoLock : NSObject {
    NSObject<NSLocking> *_lock;
    NSString* _tracker;
}
+ (instancetype)local:(NSObject<NSLocking> *)lock name:(NSString*)name;
@end

#define AUTO_LOCK(lock)                  \
    AutoLock *a = [AutoLock local:lock name:[NSString stringWithFormat:@"%s",__func__]]; \
    a = a;
