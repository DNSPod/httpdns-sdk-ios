/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import "MSDKDnsPrivate.h"
#import "msdkdns_local_ip_stack.h"

@class MSDKDnsResolver;

@protocol MSDKDnsResolverDelegate <NSObject>
@optional

- (void)resolver:(MSDKDnsResolver *)resolver didGetDomainInfo:(NSDictionary *)domainInfo;
- (void)resolver:(MSDKDnsResolver *)resolver getDomainError:(NSString *)errorInfo retry:(BOOL)retry;

@end

@interface MSDKDnsResolver : NSObject

@property (assign, nonatomic) BOOL isFinished;
@property (assign, nonatomic) BOOL isSucceed;
@property (strong, nonatomic) NSDictionary * domainInfo;
@property (strong, nonatomic) NSString * errorInfo;
@property (strong, nonatomic) NSDate * startDate;
@property (weak, nonatomic) id <MSDKDnsResolverDelegate> delegate;
@property (strong, nonatomic) NSString* cacheKey;

- (void)startWithDomains:(NSArray *)domains
                 TimeOut:(float)timeOut
                   DnsId:(int)dnsId
               DnsServer:(NSString *)dnsServer
               DnsRouter:(NSString *)dnsRouter
                  DnsKey:(NSString *)dnsKey
                DnsToken:(NSString *)dnsToken
                NetStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack
             encryptType:(NSInteger)encryptType;
- (BOOL)isIPLegal:(NSArray *)ipsArray Use4A:(BOOL)use4A;
- (int)dnsTimeConsuming;

@end
