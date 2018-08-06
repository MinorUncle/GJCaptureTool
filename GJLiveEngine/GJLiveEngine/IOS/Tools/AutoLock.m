//
//  AutoLock.m
//  GJLiveEngine
//
//  Created by melot on 2018/5/15.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#import "AutoLock.h"

@implementation AutoLock
- (instancetype)initWithLock:(NSObject<NSLocking> *)lock name:(NSString*)name{
    self = [super init];
    if (self && lock) {
        _lock = lock;
        _tracker = name;
        NSLog(@"lock local:%@ name:%@",_lock,name);
        [_lock lock];
        
    }
    return self;
}

- (void)dealloc {
    NSLog(@"lock unlock:%@  name:%@",_lock,_tracker);
    [_lock unlock];
}

+ (instancetype)local:(NSObject<NSLocking> *)lock name:(NSString*)name{
    return [[AutoLock alloc] initWithLock:lock name:name];
}
@end
