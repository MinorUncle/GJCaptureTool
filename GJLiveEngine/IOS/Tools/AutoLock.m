//
//  AutoLock.m
//  GJLiveEngine
//
//  Created by melot on 2018/5/15.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#import "AutoLock.h"

@implementation AutoLock
- (instancetype)initWithLock:(NSObject<NSLocking>*)lock
{
    self = [super init];
    if (self) {
        _lock = lock;
        [_lock lock];
    }
    return self;
}
-(void)dealloc{
    [_lock unlock];
}
+(instancetype) local:(NSObject<NSLocking>*)lock{
    return [[AutoLock alloc]initWithLock:lock];
}
@end
