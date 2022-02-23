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
@end
