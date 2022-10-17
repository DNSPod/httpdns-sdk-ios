/**
 * Copyright (c) Tencent. All rights reserved.
 */

#ifndef HttpsDnsResolver_h
#define HttpsDnsResolver_h

#import "MSDKDnsResolver.h"

@interface HttpsDnsResolver : MSDKDnsResolver

@property (nonatomic, assign) NSInteger statusCode;
@property (strong, nonatomic) NSString * errorCode;

- (void)startWithDomains:(NSArray *)domains TimeOut:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey NetStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack encryptType:(NSInteger)encryptType;

@end

#endif /* HttpsResolver_h */
