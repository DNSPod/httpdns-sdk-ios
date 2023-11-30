/**
 * Copyright (c) Tencent. All rights reserved.
 */

#ifndef HttpsDnsResolver_h
#define HttpsDnsResolver_h

#import "MSDKDnsResolver.h"

@interface HttpsDnsResolver : MSDKDnsResolver

@property (nonatomic, assign) NSInteger statusCode;
@property (strong, nonatomic) NSString * errorCode;

- (void)startWithDomains:(NSArray *)domains timeOut:(float)timeOut dnsId:(int)dnsId dnsKey:(NSString *)dnsKey netStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack encryptType:(NSInteger)encryptType;

@end

#endif /* HttpsResolver_h */
