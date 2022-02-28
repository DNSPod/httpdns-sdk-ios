/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import "msdkdns_local_ip_stack.h"

@interface MSDKDnsService : NSObject

- (void)getHostsByNames:(NSArray *)domains
                TimeOut:(float)timeOut
                  DnsId:(int)dnsId
              DnsServer:(NSString *)dnsServer
              DnsRouter:(NSString *)dnsRouter
                 DnsKey:(NSString *)dnsKey
               DnsToken:(NSString *)dnsToken
               NetStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack
            encryptType:(NSInteger)encryptType
               httpOnly:(BOOL)httpOnly
           enableReport:(BOOL)enableReport
             retryCount:(NSUInteger)retryCount
              returnIps:(void (^)())handler;

@end
