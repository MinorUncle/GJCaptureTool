//
//  GJDNSCache.c
//  GJLiveEngine
//
//  Created by melot on 2018/5/14.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#include "GJDNSCache.h"
#include <netdb.h>
#include <arpa/inet.h>
#include <string.h>
#include <pthread.h>
#include "GMemCheck.h"

typedef struct DNSInfo{
    char* hostname;
    char* port;
    struct GJDNSInfo* next;
}GJDNSInfo;

typedef struct GJDNS{
    GJDNSInfo* info;
    pthread_mutex_t lock;
    
}GJDNS;

static GJDNS* _shareDNS;

GJDNS* shareDNS(){
    if (_shareDNS == GNULL) {
        _shareDNS = malloc(sizeof(GJDNSInfo));
        pthread_mutex_init(&_shareDNS->lock, NULL);
    }
    return _shareDNS;
}


GBool getIPWithAddr(const char* addr,char* outIpAddr,GInt index){
    struct addrinfo hints = { 0 }, *ai, *cur_ai;
    
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    
    char* hostStart = strstr(addr,"//")+2;
    char* hostEnd = strchr(hostStart, '/');
    
    char* portStart = strchr(hostStart, ':');
    char* portEnd = GNULL;
    if (portStart != GNULL) {
        portEnd = hostEnd;
        hostEnd = portStart;
        portStart++;//去除冒号
    }
    size_t hostLen = hostEnd - hostStart;
    memcpy(outIpAddr, addr, hostStart - addr);//pre;
    
    char* hostname = outIpAddr + (hostStart - addr);
    memcpy(hostname, hostStart, hostLen);//hostname
    hostname[hostLen] = 0;
    
    char* port = hostname + hostLen + 1;
    if (portStart != GNULL) {
        memcpy(port, portStart, portEnd - portStart);
        port[portEnd - portStart] = 0;
    }else{
        sprintf(port, "%d",1935);
    }
    
    int ret = getaddrinfo(hostname, port, &hints, &ai);
    if (ret) {
        return GFalse;
    }else{
        cur_ai = ai;
        while (cur_ai) {
            struct sockaddr_in* inaddr =  (struct sockaddr_in*)cur_ai->ai_addr;
            char* ip = inet_ntoa(inaddr->sin_addr);
            sprintf(hostname, "%s:%s%s",ip,port,hostEnd);
            cur_ai = cur_ai->ai_next;
        }
    }
    return GTrue;
}
