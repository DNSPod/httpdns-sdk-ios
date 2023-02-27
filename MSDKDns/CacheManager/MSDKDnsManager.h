/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import "MSDKDnsPrivate.h"
#import "MSDKDns.h"

#if defined(__has_include)
    #if __has_include(<MSDK/BeaconBaseInterface.h>)
        #include <MSDK/BeaconBaseInterface.h>
    #endif

    #if __has_include("BeaconAPI_Base/BeaconBaseInterface.h")
        #include "BeaconAPI_Base/BeaconBaseInterface.h"
    #endif
#endif

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
- (void)cacheDomainInfo:(NSDictionary *)domainInfo Domain:(NSString *)domain;
- (void)clearCacheForDomain:(NSString *)domain;
- (void)clearCacheForDomains:(NSArray *)domains;
- (void)clearAllCache;
- (NSDictionary *)getDnsDetail:(NSString *)domain;

- (NSString *)currentDnsServer;
- (void)switchDnsServer;
- (void)switchToMainServer;

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
- (void)fetchConfig:(int) mdnsId MEncryptType:(HttpDnsEncryptType)mdnsEncryptType MDnsKey:(NSString *)mdnsKey MToken:(NSString* )mdnsToken;
/*
 * 获取三网域名解析IP
 */
- (void)detectHttpDnsServers;
- (int)getAddressType;
@end
