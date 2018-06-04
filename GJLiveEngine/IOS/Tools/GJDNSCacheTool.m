//
//  GJDNSCacheTool.m
//  GJLiveEngine
//
//  Created by melot on 2018/5/14.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#import "GJDNSCacheTool.h"
#import "AutoLock.h"
#import <Foundation/Foundation.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <string.h>
@interface GJDNSInfo : NSObject
@property (nonatomic, copy) NSString *                    hostname;
@property (nonatomic, copy) NSString *                    port;
@property (nonatomic, retain) NSMutableArray<NSString *> *cacheIPs;
@end
@implementation GJDNSInfo
- (instancetype)initWithHostname:(char *)hostname port:(char *)port {
    self = [super init];
    if (self) {
        _hostname = [NSString stringWithUTF8String:hostname];
        _port     = [NSString stringWithUTF8String:port];
        _cacheIPs = [NSMutableArray array];
    }
    return self;
}
- (void)appendIP:(char *)ip {
    NSString *sIP = [NSString stringWithUTF8String:ip];
    if (![_cacheIPs containsObject:sIP]) {
        [_cacheIPs addObject:sIP];
    }
}
- (void)delIP:(char *)ip {
    [_cacheIPs removeObject:[NSString stringWithUTF8String:ip]];
}
@end
@interface GJDNSCacheTool : NSObject {
    NSLock *_lock;
    NSMutableDictionary<NSString *, GJDNSInfo *> *_nodes;
}
@end

static GJDNSCacheTool *_shareDNSCache;

@implementation GJDNSCacheTool
+ (instancetype)shareNDSCache {
    if (_shareDNSCache == nil) {
        _shareDNSCache = [[GJDNSCacheTool alloc] init];
    }
    return _shareDNSCache;
}
+ (instancetype)allocWithZone:(struct _NSZone *)zone {

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shareDNSCache         = [super allocWithZone:zone];
        _shareDNSCache->_lock  = [[NSLock alloc] init];
        _shareDNSCache->_nodes = [NSMutableDictionary dictionaryWithCapacity:1];
    });
    return _shareDNSCache;
}

- (GJDNSInfo *)getNodeWithHostname:(char *)hostname port:(char *)port {
    NSString *key = [NSString stringWithFormat:@"%s:%s", hostname, port];

    return _nodes[key];
}

- (void)updateDNSNode:(GJDNSInfo *)node {
    NSString *key = [NSString stringWithFormat:@"%@:%@", node.hostname, node.port];
    _nodes[key]   = node;
}

bool isIP(const char *s) {
    int s1, s2, s3, s4;
    if (sscanf(s, "%d.%d.%d.%d", &s1, &s2, &s3, &s4) != 4) {
        return false;
    }
    if ((s1 & 0xffffff00) || (s2 & 0xffffff00) || (s3 & 0xffffff00) || (s4 & 0xffffff00)) {
        return false;
    } else {
        return true;
    }
}

- (BOOL)getIPWithAddr:(const char *)addr outip:(char *)outIpAddr index:(int)index {
    AUTO_LOCK(_lock);
    struct addrinfo hints = {0}, *ai, *cur_ai;

    hints.ai_family   = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    char *hostStart = strstr(addr, "//") + 2;
    char *hostEnd   = strchr(hostStart, '/');

    char *portStart = strchr(hostStart, ':');
    char *portEnd   = NULL;
    if (portStart != NULL) {
        portEnd = hostEnd;
        hostEnd = portStart;
        portStart++; //去除冒号
    }
    size_t hostLen = hostEnd - hostStart;
    memcpy(outIpAddr, addr, hostStart - addr); //pre;

    char *hostname = outIpAddr + (hostStart - addr);
    memcpy(hostname, hostStart, hostLen); //hostname
    hostname[hostLen] = 0;

    if (isIP(hostname)) {
        if (index > 0) {
            return NO;
        }
        sprintf(outIpAddr, "%s", addr);
        return YES;
    }

    char *port = hostname + hostLen + 1;
    if (portStart != NULL) {
        memcpy(port, portStart, portEnd - portStart);
        port[portEnd - portStart] = 0;
    } else {
        sprintf(port, "%d", 1935);
    }
    const char *ipAddr = NULL;
    GJDNSInfo *node    = [[GJDNSCacheTool shareNDSCache] getNodeWithHostname:hostname port:port];
    if (node) {
        if (node.cacheIPs.count > index) {
            ipAddr = [node.cacheIPs objectAtIndex:index].UTF8String;
        }
        if (ipAddr) {
            sprintf(hostname, "%s:%s%s", ipAddr, port, hostEnd);

            //提高优先级
            [node.cacheIPs exchangeObjectAtIndex:index withObjectAtIndex:0];
            return YES;
        }
    }
    //没有就更新
    //没有了就更新
    int ret = getaddrinfo(hostname, port, &hints, &ai);
    if (ret) {
        return NO;
    } else {
        if (node == nil) node = [[GJDNSInfo alloc] initWithHostname:hostname port:port];

        cur_ai = ai;
        while (cur_ai) {
            struct sockaddr_in *inaddr = (struct sockaddr_in *) cur_ai->ai_addr;
            char *              ip     = inet_ntoa(inaddr->sin_addr);
            [node appendIP:ip];
            cur_ai = cur_ai->ai_next;
        }
        [[GJDNSCacheTool shareNDSCache] updateDNSNode:node];
        if (node.cacheIPs.count > index) {
            ipAddr = [node.cacheIPs objectAtIndex:index].UTF8String;
        }
        if (ipAddr) {
            sprintf(hostname, "%s:%s%s", ipAddr, port, hostEnd);

            //提高优先级
            [node.cacheIPs exchangeObjectAtIndex:index withObjectAtIndex:0];
            return YES;
        } else {
            return NO;
        }
    }
}
@end

GBool getIPWithAddr(const char *addr, char *outIpAddr, int index) {
    return [[GJDNSCacheTool shareNDSCache] getIPWithAddr:addr outip:outIpAddr index:index];
}
