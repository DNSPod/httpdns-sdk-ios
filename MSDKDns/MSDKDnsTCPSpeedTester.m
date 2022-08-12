/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import "MSDKDnsTCPSpeedTester.h"
#import "MSDKDnsParamsManager.h"
#import "MSDKDnsLog.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <fcntl.h>
#import <arpa/inet.h>
#import <netdb.h>
#include <sys/time.h>

static NSString *const testSpeedKey = @"testSpeed";
static NSString *const ipKey = @"ip";

@implementation MSDKDnsTCPSpeedTester

/**
 *
 - IP池在2个到9个范围内，才进行测速逻辑。
 -
 */
- (NSArray<NSString *> *)ipRankingWithIPs:(NSArray<NSString *> *)IPs host:(NSString *)host {
    if (!IPs || !host) {
        return nil;
    }
    if (IPs.count < 2 || IPs.count > 9) {
        return nil;
    }
    
    NSDictionary *dataSource = [[MSDKDnsParamsManager shareInstance] msdkDnsGetIPRankData];
    NSArray *allHost = [dataSource allKeys];
    if (!allHost || allHost.count == 0) {
        return nil;
    }
    if (![allHost containsObject:host]) {
        return nil;
    }
    
    int16_t port = 80;
    @try {
        id port_ = dataSource[host];
        port = [port_ integerValue];
    } @catch (NSException *exception) {}
    
    NSMutableArray<NSDictionary *> *IPSpeeds = [NSMutableArray arrayWithCapacity:IPs.count];
    for (NSString *ip in IPs) {
        float testSpeed =  [self testSpeedOf:ip port:port];
        MSDKDNSLOG(@"%@:%hd speed is %f",ip,port,testSpeed);
        if (testSpeed == 0) {
            testSpeed = MSDKDns_SOCKET_CONNECT_TIMEOUT_RTT;
        }
        NSMutableDictionary *IPSpeed = [NSMutableDictionary dictionaryWithCapacity:2];
        [IPSpeed setObject:@(testSpeed) forKey:testSpeedKey];
        [IPSpeed setObject:ip forKey:ipKey];
        [IPSpeeds addObject:IPSpeed];
    }
    
    NSArray *sortedIPSpeedsArray = [IPSpeeds sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        NSNumber *data1 = [NSNumber numberWithFloat:[[obj1 valueForKey:testSpeedKey] floatValue]];
        NSNumber *data2 = [NSNumber numberWithFloat:[[obj2 valueForKey:testSpeedKey] floatValue]];
        return [data1 compare:data2];
    }];
    
    NSMutableArray<NSString *> *sortedArrayIPs = [NSMutableArray arrayWithCapacity:IPs.count];
    for (NSDictionary *dict in sortedIPSpeedsArray) {
       NSString *ip = [dict objectForKey:ipKey];
        [sortedArrayIPs addObject:ip];
    }
    //保证数量一致，
    if (sortedArrayIPs.count == IPs.count) {
        return [sortedArrayIPs copy];
    }
    return nil;
}

/**
 *  @return 测速结果，单位时毫秒，MSDKDns_SOCKET_CONNECT_TIMEOUT_RTT 代表超时。
 */
- (float)testSpeedOf:(NSString *)ip port:(int16_t)port {
    NSString *oldIp = ip;
    //request time out
    float rtt = 0.0;
    //sock：将要被设置或者获取选项的套接字。
    int s = 0;
    struct sockaddr_in saddr;
    saddr.sin_family = AF_INET;
    saddr.sin_port = htons(port);
    saddr.sin_addr.s_addr = inet_addr([ip UTF8String]);
    if( (s=socket(AF_INET, SOCK_STREAM, 0)) < 0) {
        MSDKDNSLOG(@"ERROR:%s:%d, create socket failed.",__FUNCTION__,__LINE__);
        return 0;
    }
    NSDate *startTime = [NSDate date];
    NSDate *endTime;
    //为了设置connect超时 把socket设置称为非阻塞
    int flags = fcntl(s, F_GETFL,0);
    fcntl(s,F_SETFL, flags | O_NONBLOCK);
    int i = connect(s,(struct sockaddr*)&saddr, sizeof(saddr));
    if(i == 0) {
        //建立连接成功，返回rtt时间。 因为connect是非阻塞，所以这个时间就是一个函数执行的时间，毫秒级，没必要再测速了。
        close(s);
        return 1;
    }
    struct timeval tv;
    int valopt;
    socklen_t lon;
    tv.tv_sec = MSDKDns_SOCKET_CONNECT_TIMEOUT;
    tv.tv_usec = 0;
    
    fd_set myset;
    FD_ZERO(&myset);
    FD_SET(s, &myset);
    
    // MARK: - 使用select函数，对套接字的IO操作设置超时。
    /**
     select函数
     select是一种IO多路复用机制，它允许进程指示内核等待多个事件的任何一个发生，并且在有一个或者多个事件发生或者经历一段指定的时间后才唤醒它。
     connect本身并不具有设置超时功能，如果想对套接字的IO操作设置超时，可使用select函数。
     **/
    int maxfdp = s+1;
    int j = select(maxfdp, NULL, &myset, NULL, &tv);
    
    if (j == 0) {
        MSDKDNSLOG(@"INFO:%s:%d, test rtt of (%@) timeout.",__FUNCTION__,__LINE__, oldIp);
        rtt = MSDKDns_SOCKET_CONNECT_TIMEOUT_RTT;
        close(s);
        return rtt;
    }
    
    if (j < 0) {
        MSDKDNSLOG(@"ERROR:%s:%d, select function error.",__FUNCTION__,__LINE__);
        rtt = 0;
        close(s);
        return rtt;
    }
    /**
     对于select和非阻塞connect，注意两点：
     [1] 当连接成功建立时，描述符变成可写； [2] 当连接建立遇到错误时，描述符变为即可读，也可写，遇到这种情况，可调用getsockopt函数。
     **/
    lon = sizeof(int);
    //valopt 表示错误信息。
    getsockopt(s, SOL_SOCKET, SO_ERROR, (void*)(&valopt), &lon);
    if (valopt) {
        MSDKDNSLOG(@"ERROR:%s:%d, select function error.",__FUNCTION__,__LINE__);
        rtt = 0;
    } else {
        endTime = [NSDate date];
        rtt = [endTime timeIntervalSinceDate:startTime] * 1000;
    }
    close(s);
    return rtt;
}

@end
