/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import "msdkdns_local_ip_stack.h"

@interface MSDKDnsService : NSObject

- (void)getHostsByNames:(NSArray *)domains timeOut:(float)timeOut dnsId:(int)dnsId dnsKey:(NSString *)dnsKey netStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack encryptType:(NSInteger)encryptType returnIps:(void (^)())handler;

- (void)getHostsByNames:(NSArray *)domains timeOut:(float)timeOut dnsId:(int)dnsId dnsKey:(NSString *)dnsKey netStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack encryptType:(NSInteger)encryptType from:(NSString *)origin returnIps:(void (^)())handler;

/**
 * 获取三网域名的IP地址
 */
- (void)getHttpDNSDomainIPsByNames:(NSArray *)domains
                timeOut:(float)timeOut
                  dnsId:(int)dnsId
                 dnsKey:(NSString *)dnsKey
               netStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack
            encryptType:(NSInteger)encryptType
               httpOnly:(BOOL)httpOnly
                   from:(NSString *)origin
                         returnIps:(void (^)())handler;

@end
