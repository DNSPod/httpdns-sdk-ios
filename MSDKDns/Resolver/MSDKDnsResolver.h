/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import "MSDKDnsPrivate.h"
#import "msdkdns_local_ip_stack.h"

typedef enum {
    HttpDnsTypeIPv4 = 1, // 只支持ipv4
    HttpDnsTypeIPv6 = 2, // 只支持ipv6
    HttpDnsTypeDual = 3, // 支持双协议栈
} HttpDnsIPType;

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

- (void)startWithDomains:(NSArray *)domains timeOut:(float)timeOut dnsId:(int)dnsId dnsKey:(NSString *)dnsKey netStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack;
- (BOOL)isIPLegal:(NSArray *)ipsArray use4A:(BOOL)use4A;
- (int)dnsTimeConsuming;

@end
