/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import "LocalDnsResolver.h"
#import "MSDKDnsLog.h"
#import <arpa/inet.h>
#import "MSDKDnsInfoTool.h"
#import "MSDKDnsLog.h"
#include <netdb.h>
#include <sys/socket.h>

@interface LocalDnsResolver ()

@property (assign, atomic) BOOL hasDelegated;

@end

@implementation LocalDnsResolver

- (void)startWithDomains:(NSArray *)domains timeOut:(float)timeOut dnsId:(int)dnsId dnsKey:(NSString *)dnsKey netStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack {
    [super startWithDomains:domains timeOut:timeOut dnsId:dnsId dnsKey:dnsKey netStack:netStack];
    MSDKDNSLOG(@"LocalDns domain is %@, timeOut is %f", domains, timeOut);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, timeOut * NSEC_PER_SEC), [MSDKDnsInfoTool msdkdns_local_queue], ^{
        [self localDnsTimeout];
    });
    self.domainInfo = nil;
    self.isFinished = NO;
    self.isSucceed = NO;
    self.hasDelegated = NO;
    [self getLocalDnsWithDomains:domains netStack:netStack];
}

- (void)getLocalDnsWithDomains:(NSArray *)domains netStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack {
    MSDKDNSLOG(@"getLocalDnsWithDomains: %@", domains);
    NSMutableDictionary *domainInfo = [NSMutableDictionary dictionary];
    for(int i = 0; i < [domains count]; i++) {
        NSString *domain = [domains objectAtIndex:i];
        NSArray * ipsArray = [self addressesForHostname:domain netStack:netStack];
        NSString *timeConsuming = [NSString stringWithFormat:@"%d", [self dnsTimeConsuming]];
        [domainInfo setObject:@{kIP:ipsArray, kDnsTimeConsuming:timeConsuming} forKey:domain];
    }
    
    dispatch_async([MSDKDnsInfoTool msdkdns_local_queue], ^{
        if (!self.hasDelegated) {
            self.hasDelegated = YES;
            MSDKDNSLOG(@"LocalDns Succeed");
            self.domainInfo = domainInfo;
            self.isFinished = YES;
            self.isSucceed = YES;
            
            if (self.delegate && [self.delegate respondsToSelector:@selector(resolver:didGetDomainInfo:)]) {
                [self.delegate resolver:self didGetDomainInfo:self.domainInfo];
            }
        }
    });
}

- (void)localDnsTimeout {
    if (!self.hasDelegated) {
        self.hasDelegated = YES;
        MSDKDNSLOG(@"LocalDns timeout");
        self.domainInfo = nil;
        self.isFinished = YES;
        self.isSucceed = NO;
        self.errorInfo = @"LocalDns timeout";
        if (self.delegate && [self.delegate respondsToSelector:@selector(resolver:getDomainError:retry:)]) {
            [self.delegate resolver:self getDomainError:self.errorInfo retry:NO];
        }
    }
}

- (NSArray *)addressesForHostname:(NSString *)hostname netStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack {
    const char * hostnameC = [hostname UTF8String];
    
    struct addrinfo hints, * res, * res0;
    struct sockaddr_in * s4;
    struct sockaddr_in6 * s6;
    int retval;
    char buf[64];
    NSMutableArray *result; //the array which will be return
    NSMutableArray *result4; //the array of IPv4, to order them at the end
    NSString *previousIP = nil;
    
    memset (&hints, 0, sizeof (struct addrinfo));
    hints.ai_flags = AI_CANONNAME;
    //AI_ADDRCONFIG, AI_ALL, AI_CANONNAME,  AI_NUMERICHOST
    //AI_NUMERICSERV, AI_PASSIVE, OR AI_V4MAPPED
    
    switch (netStack) {
        case msdkdns::MSDKDNS_ELocalIPStack_IPv6:
            hints.ai_family = AF_INET6;
            break;
        case msdkdns::MSDKDNS_ELocalIPStack_IPv4:
            hints.ai_family = AF_INET;
            break;
        default:
            hints.ai_family = PF_UNSPEC;
            break;
    }
    
    retval = getaddrinfo(hostnameC, NULL, &hints, &res0);
    if (retval == 0) {
        result = [[NSMutableArray alloc] init];
        result4 = [[NSMutableArray alloc] init];
        for (res = res0; res; res = res->ai_next) {
            switch (res->ai_family){
                case AF_INET6:
                    s6 = (struct sockaddr_in6 *)res->ai_addr;
                    if (inet_ntop(res->ai_family, (void *)&(s6->sin6_addr), buf, sizeof(buf)) == NULL) {
                        MSDKDNSLOG(@"inet_ntop failed for v6!\n");
                    } else {
                        //surprisingly every address is in double, let's add this test
                        if ((![previousIP isEqualToString:[NSString stringWithUTF8String:buf]]) && ![result containsObject:[NSString stringWithUTF8String:buf]]) {
                            [result addObject:[NSString stringWithUTF8String:buf]];
                        }
                    }
                    break;
                    
                case AF_INET:
                    s4 = (struct sockaddr_in *)res->ai_addr;
                    if (inet_ntop(res->ai_family, (void *)&(s4->sin_addr), buf, sizeof(buf)) == NULL) {
                        MSDKDNSLOG(@"inet_ntop failed for v4!\n");
                    } else {
                        //surprisingly every address is in double, let's add this test
                        if ((![previousIP isEqualToString:[NSString stringWithUTF8String:buf]]) && ![result4 containsObject:[NSString stringWithUTF8String:buf]]) {
                            [result4 addObject:[NSString stringWithUTF8String:buf]];
                        }
                    }
                    break;
                default:
                    MSDKDNSLOG(@"Neither IPv4 nor IPv6!");
            }
            //surprisingly every address is in double, let's add this test
            previousIP = [NSString stringWithUTF8String:buf];
        }
        freeaddrinfo(res0);
    }
    //只返回解析到的第一个ipv4地址，及第一个ipv6地址（如存在）
    if (result && [result count] > 0) {
        NSString* ipv6 = @"0";
        for (int i = 0; i < [result count]; i++) {
            if (result[i] && [self isIPValid:result[i]]) {
                NSString *regex = @"([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::ffff(:0{1,4}){0,1}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])";
                NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", regex];
                BOOL isValid = [predicate evaluateWithObject:result[i]];
                if (isValid) {
                    ipv6 = result[i];
                    break;
                }
            }
        }
        if (result4 && [result4 count] > 0 && [self isIPValid:result4[0]]) {
            return @[result4[0], ipv6];
        } else {
            return @[@"0", ipv6];
        }
    } else {
        if (result4 && [result4 count] > 0 && [self isIPValid:result4[0]]) {
            return @[result4[0], @"0"];
        } else {
            return @[@"0",@"0"];
        }
    }
}

- (BOOL)isIPValid:(NSString *)ip {
    const char *utf8 = [ip UTF8String];
    int success;
    struct in_addr dst;
    success = inet_pton(AF_INET, utf8, &dst);
    if (success != 1) {
        struct in6_addr dst6;
        success = inet_pton(AF_INET6, utf8, &dst6);
    }
    return success == 1;
}

@end
