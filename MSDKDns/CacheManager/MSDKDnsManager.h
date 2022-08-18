/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import "MSDKDnsPrivate.h"

#if defined(__has_include)
    #if __has_include(<MSDK/BeaconBaseInterface.h>)
        #include <MSDK/BeaconBaseInterface.h>
    #endif

    #if __has_include("BeaconAPI_Base/BeaconBaseInterface.h")
        #include "BeaconAPI_Base/BeaconBaseInterface.h"
    #endif
#endif

@class MSDKDnsService;

@interface MSDKDnsManager : NSObject

@property (strong, nonatomic, readonly) NSMutableDictionary * domainDict;

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
@end
