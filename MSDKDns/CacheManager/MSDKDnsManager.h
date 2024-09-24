/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import "MSDKDnsPrivate.h"
#import "MSDKDns.h"

@class MSDKDnsService;

typedef enum {
    net_undetected = 0,
    net_detecting = 1,
    net_detected = 2,
} HttpDnsSdkStatus;

@interface MSDKDnsManager : NSObject

@property (strong, nonatomic, readonly) NSMutableDictionary * domainDict;
@property (assign, nonatomic, readonly) HttpDnsSdkStatus sdkStatus;

+ (instancetype)shareInstance;

- (void)getHostsByNames:(NSArray *)domains verbose:(BOOL)verbose returnIps:(void (^)(NSDictionary * ipsDict))handler;
- (NSDictionary *)getHostsByNames:(NSArray *)domains verbose:(BOOL)verbose;
- (NSDictionary *)getHostsByNamesEnableExpired:(NSArray *)domains verbose:(BOOL)verbose;
- (void)refreshCacheDelay:(NSArray *)domains clearDispatchTag:(BOOL)needClear;
- (void)preResolveDomains;
- (void)dnsHasDone:(MSDKDnsService *)service;
- (void)cacheDomainInfo:(NSDictionary *)domainInfo domain:(NSString *)domain;
- (void)clearCacheForDomain:(NSString *)domain;
- (void)clearCacheForDomains:(NSArray<NSString *> *)domains;
- (void)clearAllCache;
- (BOOL)isOpenOptimismCache;
- (NSDictionary *)getDnsDetail:(NSString *)domain;

- (NSString *)currentDnsServer;
- (void)switchDnsServer;

// 添加domain进入延迟记录字典里面
- (void)msdkDnsAddDomainOpenDelayDispatch: (NSString *)domain;
- (void)msdkDnsClearDomainOpenDelayDispatch:(NSString *)domain;
// 批量删除
- (void)msdkDnsClearDomainsOpenDelayDispatch:(NSArray *)domains;
- (NSMutableDictionary *)msdkDnsGetDomainISOpenDelayDispatch;
- (void)loadIPsFromPersistCacheAsync;
/*
 * 获取底层配置
 */
- (void)fetchConfig:(int) mdnsId encryptType:(HttpDnsEncryptType)mdnsEncryptType dnsKey:(NSString *)mdnsKey token:(NSString* )mdnsToken;
/*
 * 获取三网域名解析IP
 */
- (void)detectHttpDnsServers;
- (int)getAddressType;
@end
