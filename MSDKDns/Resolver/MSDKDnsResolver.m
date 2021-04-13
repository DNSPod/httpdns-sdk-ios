/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import "MSDKDnsResolver.h"
#import "MSDKDnsLog.h"
#import <arpa/inet.h>
#import <netdb.h>

@implementation MSDKDnsResolver

- (void)dealloc {
    [self setDomainInfo:nil];
    [self setErrorInfo:nil];
    [self setStartDate:nil];
    [self setDelegate:nil];
}

- (void)startWithDomain:(NSString *)domain TimeOut:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey NetStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack {
    self.startDate = [NSDate date];
}

- (BOOL)isIPLegal:(NSArray *)ipsArray Use4A:(BOOL)use4A {
    BOOL isIPLegal = YES;
    
    if (ipsArray && ipsArray.count > 0) {
        for (int i = 0; i < [ipsArray count]; i++) {
            NSString * ip = [ipsArray objectAtIndex:i];
            const char *utf8 = [ip UTF8String];
            int success = 0;
            if (use4A) {
                struct in6_addr dst6;
                success = inet_pton(AF_INET6, utf8, &dst6);
            } else {
                struct in_addr dst;
                success = inet_pton(AF_INET, utf8, &dst);
            }
            if (success != 1) {
                isIPLegal = NO;
                break;
            }
            continue;
        }
    } else {
        isIPLegal = NO;
    }
    return isIPLegal;
}

- (int)dnsTimeConsuming {
    NSDate *currentTime = [NSDate date];
    NSTimeInterval timeConsuming = [currentTime timeIntervalSinceDate:self.startDate];
    return (int)(timeConsuming * 1000);
}

@end
