/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import "MSDKDnsManager.h"
#import "MSDKDnsService.h"
#import "MSDKDnsLog.h"
#import "MSDKDnsDB.h"
#import "MSDKDnsInfoTool.h"
#import "MSDKDnsParamsManager.h"
#import "MSDKDnsNetworkManager.h"
#import "msdkdns_local_ip_stack.h"
#import "AttaReport.h"
#if defined(__has_include)
    #if __has_include("httpdnsIps.h")
        #include "httpdnsIps.h"
    #endif
#endif

@interface MSDKDnsManager ()

@property (strong, nonatomic, readwrite) NSMutableArray * serviceArray;
@property (strong, nonatomic, readwrite) NSMutableDictionary * domainDict;
@property (nonatomic, assign, readwrite) int serverIndex;
@property (nonatomic, strong, readwrite) NSDate *firstFailTime; // 记录首次失败的时间
@property (nonatomic, assign, readwrite) BOOL waitToSwitch; // 防止连续多次切换
// 延迟记录字典，记录哪些域名已经开启了延迟解析请求
@property (strong, nonatomic, readwrite) NSMutableDictionary* domainISOpenDelayDispatch;
@property (nonatomic, assign, readwrite) HttpDnsSdkStatus sdkStatus;
@property (nonatomic, strong, readwrite) NSArray * dnsServers;
@property (strong, nonatomic) NSMutableURLRequest *request;
@property (strong, nonatomic, readwrite) NSMutableDictionary * cacheDomainCountDict;

@end

@implementation MSDKDnsManager

- (void)dealloc {
    if (_domainDict) {
        [self.domainDict removeAllObjects];
        [self setDomainDict:nil];
    }
    if (_serviceArray) {
        [self.serviceArray removeAllObjects];
        [self setServiceArray:nil];
    }
    if (_cacheDomainCountDict) {
        [self.cacheDomainCountDict removeAllObjects];
        [self setCacheDomainCountDict:nil];
    }
}

#pragma mark - init

static MSDKDnsManager * gSharedInstance = nil;
+ (instancetype)shareInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSharedInstance = [[MSDKDnsManager alloc] init];
    });
    return gSharedInstance;
}

- (instancetype) init {
    if (self = [super init]) {
        _serverIndex = 0;
        _firstFailTime = nil;
        _waitToSwitch = NO;
        _serviceArray = [[NSMutableArray alloc] init];
        _sdkStatus = net_undetected;
        _dnsServers = [self defaultServers];
        _cacheDomainCountDict = [[NSMutableDictionary alloc] init];
    }
    return self;
}

#pragma mark - getHostByDomain

#pragma mark sync

- (NSDictionary *)getHostsByNames:(NSArray *)domains verbose:(BOOL)verbose {
    // 获取当前ipv4/ipv6/双栈网络环境
    msdkdns::MSDKDNS_TLocalIPStack netStack = [self detectAddressType];
    __block float timeOut = 2.0;
    __block NSDictionary * cacheDomainDict = nil;
    dispatch_sync([MSDKDnsInfoTool msdkdns_queue], ^{
        if (domains && [domains count] > 0 && _domainDict) {
            cacheDomainDict = [[NSDictionary alloc] initWithDictionary:_domainDict];
        }
        timeOut = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMTimeOut];
    });
    // 待查询数组
    NSArray *toCheckDomains = [self getCheckDomains:domains dict:cacheDomainDict netStack:netStack];
    // 全部有缓存时，直接返回
    if([toCheckDomains count] == 0) {
        // NSLog(@"有缓存");
        NSDictionary * result = verbose ?
            [self fullResultDictionary:domains fromCache:cacheDomainDict] :
            [self resultDictionary:domains fromCache:cacheDomainDict];
        return result;
    }
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        int dnsId = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsId];
        NSString * dnsKey = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsKey];
        if (!self.serviceArray) {
            self.serviceArray = [[NSMutableArray alloc] init];
        }
        HttpDnsEncryptType encryptType = [[MSDKDnsParamsManager shareInstance] msdkDnsGetEncryptType];
        MSDKDnsService * dnsService = [[MSDKDnsService alloc] init];
        [self.serviceArray addObject:dnsService];
        __weak __typeof__(self) weakSelf = self;
        [dnsService getHostsByNames:toCheckDomains timeOut:timeOut dnsId:dnsId dnsKey:dnsKey netStack:netStack encryptType:encryptType returnIps:^() {
            __strong __typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                [toCheckDomains enumerateObjectsUsingBlock:^(id _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    [strongSelf uploadReport:NO domain:obj netStack:netStack];
                }];
                [strongSelf dnsHasDone:dnsService];
            }
            dispatch_semaphore_signal(sema);
        }];
    });
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, timeOut * NSEC_PER_SEC));
    cacheDomainDict = nil;
    dispatch_sync([MSDKDnsInfoTool msdkdns_queue], ^{
        if (domains && [domains count] > 0 && _domainDict) {
            cacheDomainDict = [[NSDictionary alloc] initWithDictionary:_domainDict];
        }
    });
    NSDictionary * result = verbose?
        [self fullResultDictionary:domains fromCache:cacheDomainDict] :
        [self resultDictionary:domains fromCache:cacheDomainDict];
    return result;
}

// 
- (NSDictionary *)getHostsByNamesEnableExpired:(NSArray *)domains verbose:(BOOL)verbose {
    // 获取当前ipv4/ipv6/双栈网络环境
    msdkdns::MSDKDNS_TLocalIPStack netStack = [self detectAddressType];
    __block float timeOut = 2.0;
    __block NSDictionary * cacheDomainDict = nil;
    dispatch_sync([MSDKDnsInfoTool msdkdns_queue], ^{
        if (domains && [domains count] > 0 && _domainDict) {
            cacheDomainDict = [[NSDictionary alloc] initWithDictionary:_domainDict];
        }
        timeOut = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMTimeOut];
    });
    // 待查询数组
    NSMutableArray *toCheckDomains = [NSMutableArray array];
    // 需要排除结果的域名数组
    NSMutableArray *toEmptyDomains = [NSMutableArray array];
    // 查找缓存，不存在或者ttl超时则放入待查询数组，ttl超时还放入排除结果的数组以便如果禁用返回ttl过期的解析结果则进行排除结果
    for (int i = 0; i < [domains count]; i++) {
        NSString *domain = [domains objectAtIndex:i];
        if ([[self domainCache:cacheDomainDict check:domain] isEqualToString:MSDKDnsDomainCacheEmpty]) {
            [toCheckDomains addObject:domain];
        } else if ([[self domainCache:cacheDomainDict check:domain] isEqualToString:MSDKDnsDomainCacheExpired]) {
            [toCheckDomains addObject:domain];
            [toEmptyDomains addObject:domain];
        } else {
            MSDKDNSLOG(@"%@ TTL has not expiried,return result from cache directly!", domain);
            dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
                [self uploadReport:YES domain:domain netStack:netStack];
            });
        }
    }
    // 当待查询数组中存在数据的时候，就开启异步线程执行解析操作，并且更新缓存
    if (toCheckDomains && [toCheckDomains count] != 0) {
        dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
            if (!self.serviceArray) {
                self.serviceArray = [[NSMutableArray alloc] init];
            }
            int dnsId = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsId];
            NSString * dnsKey = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsKey];
            HttpDnsEncryptType encryptType = [[MSDKDnsParamsManager shareInstance] msdkDnsGetEncryptType];
            MSDKDnsService * dnsService = [[MSDKDnsService alloc] init];
            [self.serviceArray addObject:dnsService];
            __weak __typeof__(self) weakSelf = self;
            //进行httpdns请求
            [dnsService getHostsByNames:toCheckDomains timeOut:timeOut dnsId:dnsId dnsKey:dnsKey netStack:netStack encryptType:encryptType from:MSDKDnsEventHttpDnsExpiredAsync returnIps:^{
                __strong __typeof(self) strongSelf = weakSelf;
                if (strongSelf) {
                    [toCheckDomains enumerateObjectsUsingBlock:^(id _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                        [strongSelf uploadReport:NO domain:obj netStack:netStack];
                    }];
                    [strongSelf dnsHasDone:dnsService];
                }
            }];
        });
    }
    NSDictionary * result = verbose?
        [self fullResultDictionaryEnableExpired:domains fromCache:cacheDomainDict toEmpty:toEmptyDomains] :
        [self resultDictionaryEnableExpired:domains fromCache:cacheDomainDict toEmpty:toEmptyDomains];
    
    [self excuteOptimismReport:domains result:result verbose:verbose];
    
    return result;
}

- (void)excuteOptimismReport:(NSArray *)domains result:(NSDictionary *)result verbose:(BOOL)verbose {
    // 当开启乐观DNS之后，如果结果为0则上报errorCode=3，要所有域名解析的结果都为0
    BOOL needReport = NO;
    if (verbose) {
        for (int i = 0; i < [domains count]; i++) {
            NSString *domain = [domains objectAtIndex:i];
            NSDictionary *domainData = result[domain];
            if (domainData && domainData.count > 0) {
                needReport = NO;
                break;
            } else {
                needReport = YES;
            }
        }
    } else {
        for (int i = 0; i < [domains count]; i++) {
            NSString *domain = [domains objectAtIndex:i];
            NSArray *domainResArray = result[domain];
            if (domainResArray && domainResArray.count > 0) {
                if ([domainResArray[0] isEqualToString:@"0"] && [domainResArray[1] isEqualToString:@"0"]) {
                    needReport = YES;
                } else {
                    needReport = NO;
                    break;
                }
            } else {
                needReport = YES;
            }
        }
    }
    if (needReport && domains) {
        for (int i = 0; i < [domains count]; i++) {
            NSString *domain = [domains objectAtIndex:i];
            [[AttaReport sharedInstance] reportEvent:@{
                MSDKDns_ErrorCode: MSDKDns_NoData,
                @"eventName": MSDKDnsEventHttpDnsCached,
                @"dnsIp": [[MSDKDnsManager shareInstance] currentDnsServer],
                @"req_dn": domain,
                @"req_type": @"a",
                @"req_timeout": @0,
                @"req_ttl": @0,
                @"req_query": @0,
                @"req_ip": @"",
                @"spend": @0,
                @"statusCode": @0,
                @"count": @1,
                @"isCache": @1,
            }];
        }
    }
}

#pragma mark async

- (void)getHostsByNames:(NSArray *)domains
                verbose:(BOOL)verbose
              returnIps:(void (^)(NSDictionary * ipsDict))handler {
    [self getHostsByNames:domains verbose:verbose from:MSDKDnsEventHttpDnsNormal returnIps:handler];
}

- (void)getHostsByNames:(NSArray *)domains
                verbose:(BOOL)verbose
                from:(NSString *)origin
              returnIps:(void (^)(NSDictionary * ipsDict))handler {
    // 获取当前ipv4/ipv6/双栈网络环境
    msdkdns::MSDKDNS_TLocalIPStack netStack = [self detectAddressType];
    __block float timeOut = 2.0;
    __block NSDictionary * cacheDomainDict = nil;
    dispatch_sync([MSDKDnsInfoTool msdkdns_queue], ^{
        if (domains && [domains count] > 0 && _domainDict) {
            cacheDomainDict = [[NSDictionary alloc] initWithDictionary:_domainDict];
        }
        timeOut = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMTimeOut];
    });
    // 待查询数组
    NSArray *toCheckDomains = [self getCheckDomains:domains dict:cacheDomainDict netStack:netStack];
    // 全部有缓存时，直接返回
    if([toCheckDomains count] == 0) {
        NSDictionary * result = verbose ?
            [self fullResultDictionary:domains fromCache:cacheDomainDict] :
            [self resultDictionary:domains fromCache:cacheDomainDict];
        if (handler) {
            handler(result);
        }
        return;
    }
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        if (!self.serviceArray) {
            self.serviceArray = [[NSMutableArray alloc] init];
        }
        int dnsId = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsId];
        NSString * dnsKey = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsKey];
        //进行httpdns请求
        MSDKDnsService * dnsService = [[MSDKDnsService alloc] init];
        [self.serviceArray addObject:dnsService];
        __weak __typeof__(self) weakSelf = self;
        HttpDnsEncryptType encryptType = [[MSDKDnsParamsManager shareInstance] msdkDnsGetEncryptType];
        [dnsService getHostsByNames:toCheckDomains timeOut:timeOut dnsId:dnsId dnsKey:dnsKey netStack:netStack encryptType:encryptType from:origin returnIps:^() {
            __strong __typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                [toCheckDomains enumerateObjectsUsingBlock:^(id _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    [strongSelf uploadReport:NO domain:obj netStack:netStack];
                }];
                [strongSelf dnsHasDone:dnsService];
                NSDictionary * result = verbose ?
                    [strongSelf fullResultDictionary:domains fromCache:self.domainDict] :
                    [strongSelf resultDictionary:domains fromCache:self.domainDict];
                if (handler) {
                    handler(result);
                }
            }
        }];
    });
    
}

- (NSArray *)getCheckDomains:(NSArray *)domains dict:(NSDictionary *)cacheDomainDict netStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack {
    // 待查询数组
    NSMutableArray *toCheckDomains = [NSMutableArray array];
    // 查找缓存，缓存中有HttpDns数据且ttl未超时则直接返回结果,不存在或者ttl超时则放入待查询数组
    for (int i = 0; i < [domains count]; i++) {
        NSString *domain = [domains objectAtIndex:i];
        if (![[self domainCache:cacheDomainDict check:domain] isEqualToString:MSDKDnsDomainCacheHit]) {
            [toCheckDomains addObject:domain];
        } else {
            MSDKDNSLOG(@"%@ TTL has not expiried,return result from cache directly!", domain);
            dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
                [self uploadReport:YES domain:domain netStack:netStack];
            });
        }
    }
    return toCheckDomains;
}

#pragma mark 发送解析请求刷新缓存

- (void)refreshCacheDelay:(NSArray *)domains clearDispatchTag:(BOOL)needClear {
    // 获取当前ipv4/ipv6/双栈网络环境
    msdkdns::MSDKDNS_TLocalIPStack netStack = [self detectAddressType];
    __block float timeOut = 2.0;
    timeOut = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMTimeOut];
    //进行httpdns请求
    int dnsId = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsId];
    NSString * dnsKey = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsKey];
    HttpDnsEncryptType encryptType = [[MSDKDnsParamsManager shareInstance] msdkDnsGetEncryptType];
    
    MSDKDnsService * dnsService = [[MSDKDnsService alloc] init];
    [dnsService getHostsByNames:domains timeOut:timeOut dnsId:dnsId dnsKey:dnsKey netStack:netStack encryptType:encryptType from:MSDKDnsEventHttpDnsAutoRefresh returnIps:^{
        if(needClear){
            // 当请求结束了需要将该域名开启的标志清除，方便下次继续开启延迟解析请求
            // NSLog(@"延时更新请求结束!请求域名为%@",domains);
            [self msdkDnsClearDomainsOpenDelayDispatch:domains];
        }
    }];
}

- (void)preResolveDomains {
    __block NSArray * domains = nil;
    dispatch_sync([MSDKDnsInfoTool msdkdns_queue], ^{
       domains = [[MSDKDnsParamsManager shareInstance] msdkDnsGetPreResolvedDomains];
    });
    if (domains && [domains count] > 0) {
        MSDKDNSLOG(@"preResolve domains: %@", [domains componentsJoinedByString:@","] );
        [self getHostsByNames:domains verbose:NO from:MSDKDnsEventHttpDnsPreResolved returnIps:^(NSDictionary *ipsDict) {
            if (ipsDict) {
                MSDKDNSLOG(@"preResolve domains success.");
            } else {
                MSDKDNSLOG(@"preResolve domains failed.");
            }
        }];
    }
}

#pragma mark - dns resolve

- (NSArray *)resultArray: (NSString *)domain fromCache:(NSDictionary *)domainDict {
    NSMutableArray * ipResult = [@[@"0", @"0"] mutableCopy];
    BOOL httpOnly = [[MSDKDnsParamsManager shareInstance] msdkDnsGetHttpOnly];
    if (domainDict) {
        NSDictionary * cacheDict = domainDict[domain];
        if (cacheDict && [cacheDict isKindOfClass:[NSDictionary class]]) {
            
            NSDictionary * hresultDict_A = cacheDict[kMSDKHttpDnsCache_A];
            NSDictionary * hresultDict_4A = cacheDict[kMSDKHttpDnsCache_4A];
            
            if (!httpOnly) {
                NSDictionary * lresultDict = cacheDict[kMSDKLocalDnsCache];
                if (lresultDict && [lresultDict isKindOfClass:[NSDictionary class]]) {
                    ipResult = [lresultDict[kIP] mutableCopy];
                }
            }
            if (hresultDict_A && [hresultDict_A isKindOfClass:[NSDictionary class]]) {
                NSArray * ipsArray = hresultDict_A[kIP];
                if (ipsArray && [ipsArray isKindOfClass:[NSArray class]] && ipsArray.count > 0) {
                    ipResult[0] = ipsArray[0];
                }
            }
            if (hresultDict_4A && [hresultDict_4A isKindOfClass:[NSDictionary class]]) {
                NSArray * ipsArray = hresultDict_4A[kIP];
                if (ipsArray && [ipsArray isKindOfClass:[NSArray class]] && ipsArray.count > 0) {
                    ipResult[1] = ipsArray[0];
                }
            }
        }
    }
    return ipResult;
}

- (NSDictionary *)resultDictionary: (NSArray *)domains fromCache:(NSDictionary *)domainDict {
    NSMutableDictionary *resultDict = [NSMutableDictionary dictionary];
    for (int i = 0; i < [domains count]; i++) {
        NSString *domain = [domains objectAtIndex:i];
        NSArray *arr = [self resultArray:domain fromCache:domainDict];
        [resultDict setObject:arr forKey:domain];
    }
    return resultDict;
}

- (NSDictionary *)fullResultDictionary: (NSArray *)domains fromCache:(NSDictionary *)domainDict {
    BOOL httpOnly = [[MSDKDnsParamsManager shareInstance] msdkDnsGetHttpOnly];
    NSMutableDictionary *resultDict = [NSMutableDictionary dictionary];
    for (int i = 0; i < [domains count]; i++) {
        NSString *domain = [domains objectAtIndex:i];
        NSMutableDictionary * ipResult = [NSMutableDictionary dictionary];
        if (domainDict) {
            NSDictionary * cacheDict = domainDict[domain];
            if (cacheDict && [cacheDict isKindOfClass:[NSDictionary class]]) {
                NSDictionary * hresultDict_A = cacheDict[kMSDKHttpDnsCache_A];
                NSDictionary * hresultDict_4A = cacheDict[kMSDKHttpDnsCache_4A];
                if (!httpOnly) {
                    NSDictionary * localResultDict = cacheDict[kMSDKLocalDnsCache];
                    if (localResultDict && [localResultDict isKindOfClass:[NSDictionary class]]) {
                        NSArray *ipsArray = [localResultDict[kIP] mutableCopy];
                        if (ipsArray.count == 2) {
                            [ipResult setObject:@[ipsArray[0]] forKey:@"ipv4"];
                            [ipResult setObject:@[ipsArray[1]] forKey:@"ipv6"];
                        }
                    }
                }
                if (hresultDict_A && [hresultDict_A isKindOfClass:[NSDictionary class]]) {
                    NSArray * ipsArray = hresultDict_A[kIP];
                    if (ipsArray && [ipsArray isKindOfClass:[NSArray class]] && ipsArray.count > 0) {
                        [ipResult setObject:ipsArray forKey:@"ipv4"];
                    }
                }
                if (hresultDict_4A && [hresultDict_4A isKindOfClass:[NSDictionary class]]) {
                    NSArray * ipsArray = hresultDict_4A[kIP];
                    if (ipsArray && [ipsArray isKindOfClass:[NSArray class]] && ipsArray.count > 0) {
                        [ipResult setObject:ipsArray forKey:@"ipv6"];
                    }
                }
            }
        }
        [resultDict setObject:ipResult forKey:domain];
    }
    return resultDict;
}

- (NSDictionary *)resultDictionaryEnableExpired: (NSArray *)domains fromCache:(NSDictionary *)domainDict toEmpty:(NSArray *)emptyDomains {
    NSMutableDictionary *resultDict = [NSMutableDictionary dictionary];
    BOOL expiredIPEnabled = [[MSDKDnsParamsManager shareInstance] msdkDnsGetExpiredIPEnabled];
    for (int i = 0; i < [domains count]; i++) {
        NSString *domain = [domains objectAtIndex:i];
        NSArray *arr = [self resultArray:domain fromCache:domainDict];
        BOOL domainNeedEmpty = [emptyDomains containsObject:domain];
        // 缓存过期，并且没有开启使用过期缓存
        if (domainNeedEmpty && !expiredIPEnabled) {
            [resultDict setObject:@[@0,@0] forKey:domain];
        } else {
            [resultDict setObject:arr forKey:domain];
        }
    }
    return resultDict;
}

- (NSDictionary *)fullResultDictionaryEnableExpired: (NSArray *)domains fromCache:(NSDictionary *)domainDict toEmpty:(NSArray *)emptyDomains {
    NSMutableDictionary *resultDict = [NSMutableDictionary dictionary];
    BOOL expiredIPEnabled = [[MSDKDnsParamsManager shareInstance] msdkDnsGetExpiredIPEnabled];
    BOOL httpOnly = [[MSDKDnsParamsManager shareInstance] msdkDnsGetHttpOnly];
    for (int i = 0; i < [domains count]; i++) {
        NSString *domain = [domains objectAtIndex:i];
        BOOL domainNeedEmpty = [emptyDomains containsObject:domain];
        NSMutableDictionary * ipResult = [NSMutableDictionary dictionary];
        if (domainDict) {
            NSDictionary * cacheDict = domainDict[domain];
            if (cacheDict && [cacheDict isKindOfClass:[NSDictionary class]]) {
                
                NSDictionary * hresultDict_A = cacheDict[kMSDKHttpDnsCache_A];
                NSDictionary * hresultDict_4A = cacheDict[kMSDKHttpDnsCache_4A];
                if (!httpOnly) {
                    NSDictionary * lresultDict = cacheDict[kMSDKLocalDnsCache];
                    BOOL isExistLocalResult = lresultDict && [lresultDict isKindOfClass:[NSDictionary class]];
                    if (isExistLocalResult) {
                        NSArray *ipsArray = [lresultDict[kIP] mutableCopy];
                        if (ipsArray.count == 2) {
                            // 缓存过期，并且没有开启使用过期缓存
                            if (domainNeedEmpty && !expiredIPEnabled) {
                                [ipResult setObject:@[@0] forKey:@"ipv4"];
                                [ipResult setObject:@[@0] forKey:@"ipv6"];
                            } else {
                                [ipResult setObject:@[ipsArray[0]] forKey:@"ipv4"];
                                [ipResult setObject:@[ipsArray[1]] forKey:@"ipv6"];
                            }
                        }
                    }
                }
                BOOL isExistHttpResultA = hresultDict_A && [hresultDict_A isKindOfClass:[NSDictionary class]];
                if (isExistHttpResultA) {
                    NSArray * ipsArray = hresultDict_A[kIP];
                    BOOL isExistIpsArray = ipsArray && [ipsArray isKindOfClass:[NSArray class]] && ipsArray.count > 0;
                    if (isExistIpsArray) {
                        // 缓存过期，并且没有开启使用过期缓存
                        if (domainNeedEmpty && !expiredIPEnabled) {
                            [ipResult setObject:@[@0] forKey:@"ipv4"];
                        } else {
                            [ipResult setObject:ipsArray forKey:@"ipv4"];
                        }
                    }
                }
                BOOL isExistHttpResult4A = hresultDict_4A && [hresultDict_4A isKindOfClass:[NSDictionary class]];
                if (isExistHttpResult4A) {
                    NSArray * ipsArray = hresultDict_4A[kIP];
                    BOOL isExistIpsArray = ipsArray && [ipsArray isKindOfClass:[NSArray class]] && ipsArray.count > 0;
                    if (isExistIpsArray) {
                        // 缓存过期，并且没有开启使用过期缓存
                        if (domainNeedEmpty && !expiredIPEnabled) {
                            [ipResult setObject:@[@0] forKey:@"ipv6"];
                        } else {
                            [ipResult setObject:ipsArray forKey:@"ipv6"];
                        }
                    }
                }
            }
        }
        [resultDict setObject:ipResult forKey:domain];
    }
    return resultDict;
}

- (void)dnsHasDone:(MSDKDnsService *)service {
    NSArray * tmpArray = [NSArray arrayWithArray:self.serviceArray];
    NSMutableArray * tmp = [[NSMutableArray alloc] init];
    for (MSDKDnsService * dnsService in tmpArray) {
        if (dnsService == service) {
            [tmp addObject:dnsService];
            break;
        }
    }
    [self.serviceArray removeObjectsInArray:tmp];
}

- (NSDictionary *) getDnsDetail:(NSString *) domain {
    __block NSDictionary * cacheDomainDict = nil;
    dispatch_sync([MSDKDnsInfoTool msdkdns_queue], ^{
        if (domain && _domainDict) {
            cacheDomainDict = [[NSDictionary alloc] initWithDictionary:_domainDict];
        }
    });
    NSMutableDictionary * detailDict = [@{@"v4_ips": @"",
                                          @"v6_ips": @"",
                                          @"v4_ttl": @"",
                                          @"v6_ttl": @"",
                                          @"v4_client_ip": @"",
                                          @"v6_client_ip": @""} mutableCopy];
    if (cacheDomainDict) {
        NSDictionary * domainInfo = cacheDomainDict[domain];
        if (domainInfo && [domainInfo isKindOfClass:[NSDictionary class]]) {
            NSDictionary * cacheDict_A = domainInfo[kMSDKHttpDnsCache_A];
            if (cacheDict_A && [cacheDict_A isKindOfClass:[NSDictionary class]]) {
                detailDict[@"v4_ips"] = [MSDKDnsInfoTool getIPsStringFromIPsArray:cacheDict_A[kIP]];
                detailDict[@"v4_ttl"] = cacheDict_A[kTTL];
                detailDict[@"v4_client_ip"] = cacheDict_A[kClientIP];
            }
            NSDictionary * cacheDict_4A = domainInfo[kMSDKHttpDnsCache_4A];
            if (cacheDict_4A && [cacheDict_4A isKindOfClass:[NSDictionary class]]) {
                detailDict[@"v6_ips"] = [MSDKDnsInfoTool getIPsStringFromIPsArray:cacheDict_4A[kIP]];
                detailDict[@"v6_ttl"] = cacheDict_4A[kTTL];
                detailDict[@"v6_client_ip"] = cacheDict_4A[kClientIP];
            }
        }
    }
    return detailDict;
}

#pragma mark - clear cache

- (void)cacheDomainInfo:(NSDictionary *)domainInfo domain:(NSString *)domain {
    if (domain && domain.length > 0 && domainInfo && domainInfo.count > 0) {
        MSDKDNSLOG(@"Cache domain:%@ %@", domain, domainInfo);
        //结果存缓存
        if (!self.domainDict) {
            self.domainDict = [[NSMutableDictionary alloc] init];
        }
        [self.domainDict setObject:domainInfo forKey:domain];
    }
}

- (void)clearCacheForDomain:(NSString *)domain {
    if (domain && domain.length > 0) {
        MSDKDNSLOG(@"Clear cache for domain:%@",domain);
        if (self.domainDict) {
            [self.domainDict removeObjectForKey:domain];
        }
    }
}

- (void)clearCacheForDomains:(NSArray *)domains {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        for(int i = 0; i < [domains count]; i++) {
            if ([[domains objectAtIndex:i] isKindOfClass:[NSString class]]) {
                NSString* domain = [domains objectAtIndex:i];
                [self clearCacheForDomain:domain];
            }
        }
        BOOL persistCacheIPEnabled = [[MSDKDnsParamsManager shareInstance] msdkDnsGetPersistCacheIPEnabled];
        // 当持久化缓存开启的情况下，同时删除本地持久化缓存中的缓存
        if (persistCacheIPEnabled && domains && domains.count > 0) {
            [[MSDKDnsDB shareInstance] deleteDBData:domains];
        }
    });
}

- (void)clearAllCache {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        MSDKDNSLOG(@"MSDKDns cleared all caches!");
        if (self.domainDict) {
            [self.domainDict removeAllObjects];
            self.domainDict = nil;
        }
        BOOL persistCacheIPEnabled = [[MSDKDnsParamsManager shareInstance] msdkDnsGetPersistCacheIPEnabled];
        // 当持久化缓存开启的情况下，清除持久化缓存中的数据
        if (persistCacheIPEnabled) {
            //查询前清除缓存
            [[MSDKDnsDB shareInstance] deleteAllData];
        }
    });
}

- (BOOL)isOpenOptimismCache {
    BOOL persistCacheIPEnabled = [[MSDKDnsParamsManager shareInstance] msdkDnsGetPersistCacheIPEnabled];
    BOOL expiredIPEnabled = [[MSDKDnsParamsManager shareInstance] msdkDnsGetExpiredIPEnabled];
    if (persistCacheIPEnabled && expiredIPEnabled) {
        return YES;
    }
    return NO;
}

#pragma mark - uploadReport
- (void)hitCacheAttaUploadReport:(NSString *)domain {
    // 检查控制台解析监控上报开关是否开启
    if ([[MSDKDnsParamsManager shareInstance] msdkDnsGetEnableReport]) {
        if (self.cacheDomainCountDict) {
            NSNumber *num = self.cacheDomainCountDict[domain];
            if (num) {
                int numInt = num.intValue + 1;
                [self.cacheDomainCountDict setValue:[NSNumber numberWithInt:numInt] forKey:domain];
            } else {
                [self.cacheDomainCountDict setValue:[NSNumber numberWithInt:1] forKey:domain];
            }
        
            if ([[AttaReport sharedInstance] shoulReportDnsSpend]) {
                NSArray *dictKey = [self.cacheDomainCountDict allKeys];
                NSInteger length = [dictKey count];
                for (int i = 0; i < length; i++) {
                    id domainKey = [dictKey objectAtIndex:i];
                    NSNumber *cacheCount = [self.cacheDomainCountDict objectForKey:domainKey];
                    [[AttaReport sharedInstance] reportEvent:@{
                        MSDKDns_ErrorCode: MSDKDns_Success,
                        @"eventName": MSDKDnsEventHttpDnsCached,
                        @"dnsIp": [[MSDKDnsManager shareInstance] currentDnsServer],
                        @"req_dn": domainKey,
                        @"req_type": @"a",
                        @"req_timeout": @0,
                        @"req_ttl": @0,
                        @"req_query": @0,
                        @"req_ip": @"",
                        @"spend": @0,
                        @"statusCode": @0,
                        @"count": cacheCount,
                        @"isCache": @1,
                    }];
                }
                [self.cacheDomainCountDict removeAllObjects];
             }
        }
    }
}

- (void)uploadReport:(BOOL)isFromCache domain:(NSString *)domain netStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack {
    // 命中缓存进行atta上报
    if (isFromCache) {
        [self hitCacheAttaUploadReport:domain];
    }
    // 接口传参
    NSString *eventName = MSDKDnsEventName;
    
    NSMutableDictionary *params = [self formatParams:isFromCache domain:domain netStack:netStack];
    
    MSDKDNSLOG(@"api name:%@, data:%@", eventName, params);

}

- (NSMutableDictionary *)formatParams:(BOOL)isFromCache domain:(NSString *)domain netStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack {
    MSDKDNSLOG(@"domain:%@",domain);
    //dns结束时上报结果
    NSMutableDictionary * params = [NSMutableDictionary new];
    
    //SDKVersion
    [params setValue:MSDKDns_Version forKey:kMSDKDnsSDK_Version];
    
    //appId
    NSString * appID = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMAppId];
    if (appID) {
        [params setValue:appID forKey:kMSDKDnsAppID];
    } else {
        [params setValue:HTTP_DNS_UNKNOWN_STR forKey:kMSDKDnsAppID];
    }
    
    //id & key
    int dnsID = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsId];
    [params setValue:[NSString stringWithFormat:@"%d", dnsID] forKey:kMSDKDnsID];
    NSString * dnsKeyStr = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsKey];
    if (dnsKeyStr) {
        [params setValue:dnsKeyStr forKey:kMSDKDnsKEY];
    } else {
        [params setValue:HTTP_DNS_UNKNOWN_STR forKey:kMSDKDnsKEY];
    }
    
    //userId
    NSString * uuidStr = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMOpenId];
    if (uuidStr) {
        [params setValue:uuidStr forKey:kMSDKDnsUserID];
    } else {
        [params setValue:HTTP_DNS_UNKNOWN_STR forKey:kMSDKDnsUserID];
    }
    
    //netType
    NSString * networkType = [[MSDKDnsNetworkManager shareInstance] networkType];
    [params setValue:networkType forKey:kMSDKDnsNetType];
    
    //domain
    NSString * domain_string = HTTP_DNS_UNKNOWN_STR;
    if (domain) {
        domain_string = domain;
    }
    [params setValue:domain_string forKey:kMSDKDnsDomain];
    
    //netStack
    [params setValue:@(netStack) forKey:kMSDKDnsNet_Stack];
    
    //isCache
    [params setValue:[NSNumber numberWithBool:NO] forKey:kMSDKDns_A_IsCache];
    [params setValue:[NSNumber numberWithBool:NO] forKey:kMSDKDns_4A_IsCache];
    
    NSString * clientIP_A = @"";
    NSString * clientIP_4A = @"";
    NSString * httpDnsIP_A = @"";
    NSString * httpDnsIP_4A = @"";
    NSString * httpDnsTimeConsuming_A = @"";
    NSString * httpDnsTimeConsuming_4A = @"";
    NSString * httpDnsTTL_A = @"";
    NSString * httpDnsTTL_4A = @"";
    NSString * httpDnsErrCode_A = @"";
    NSString * httpDnsErrCode_4A = @"";
    NSString * httpDnsErrCode_BOTH = @"";
    NSString * httpDnsErrMsg_A = @"";
    NSString * httpDnsErrMsg_4A = @"";
    NSString * httpDnsErrMsg_BOTH = @"";
    NSString * httpDnsRetry_A = @"";
    NSString * httpDnsRetry_4A = @"";
    NSString * httpDnsRetry_BOTH = @"";
    NSString * cache_A = @"";
    NSString * cache_4A = @"";
    NSString * dns_A = @"0";
    NSString * dns_4A = @"0";
    NSString * localDnsIPs = @"";
    NSString * localDnsTimeConsuming = @"";
    NSString * channel = @"";
    
    NSDictionary * cacheDict = [self domainDict];
    if (cacheDict && domain) {
        NSDictionary * cacheInfo = cacheDict[domain];
        if (cacheInfo) {
            
            NSDictionary * localDnsCache = cacheInfo[kMSDKLocalDnsCache];
            if (localDnsCache) {
                NSArray * ipsArray = localDnsCache[kIP];
                if (ipsArray && [ipsArray count] == 2) {
                    dns_A = ipsArray[0];
                    dns_4A = ipsArray[1];
                    localDnsIPs = [MSDKDnsInfoTool getIPsStringFromIPsArray:ipsArray];
                }
                localDnsTimeConsuming = localDnsCache[kDnsTimeConsuming];
            }
            
            NSDictionary * httpDnsCache_A = cacheInfo[kMSDKHttpDnsCache_A];
            if (httpDnsCache_A) {
                
                clientIP_A = httpDnsCache_A[kClientIP];
                NSArray * ipsArray = httpDnsCache_A[kIP];
                if (ipsArray && [ipsArray isKindOfClass:[NSArray class]] && ipsArray.count > 0) {
                    dns_A = ipsArray[0];
                    httpDnsIP_A = [MSDKDnsInfoTool getIPsStringFromIPsArray:ipsArray];
                }
                
                httpDnsTimeConsuming_A = httpDnsCache_A[kDnsTimeConsuming];
                httpDnsTTL_A = httpDnsCache_A[kTTL];
                cache_A = @(isFromCache).stringValue;
                channel = httpDnsCache_A[kChannel];
                //isCache
                [params setValue:[NSNumber numberWithBool:isFromCache] forKey:kMSDKDns_A_IsCache];
            }
            
            NSDictionary * httpDnsCache_4A = cacheInfo[kMSDKHttpDnsCache_4A];
            if (httpDnsCache_4A) {
                
                clientIP_4A = httpDnsCache_4A[kClientIP];
                NSArray * ipsArray = httpDnsCache_4A[kIP];
                if (ipsArray && [ipsArray isKindOfClass:[NSArray class]] && ipsArray.count > 0) {
                    dns_4A = ipsArray[0];
                    httpDnsIP_4A = [MSDKDnsInfoTool getIPsStringFromIPsArray:ipsArray];
                }
                
                httpDnsTimeConsuming_4A = httpDnsCache_4A[kDnsTimeConsuming];
                httpDnsTTL_4A = httpDnsCache_4A[kTTL];
                cache_4A = @(isFromCache).stringValue;
                channel = httpDnsCache_4A[kChannel];
                //isCache
                [params setValue:[NSNumber numberWithBool:isFromCache] forKey:kMSDKDns_4A_IsCache];
            }
            
            NSDictionary * httpDnsInfo_A = cacheInfo[kMSDKHttpDnsInfo_A];
            if (httpDnsInfo_A) {
                httpDnsErrCode_A = httpDnsInfo_A[kDnsErrCode];
                httpDnsErrMsg_A = httpDnsInfo_A[kDnsErrMsg];
                httpDnsRetry_A = httpDnsInfo_A[kDnsRetry];
            }
            
            NSDictionary * httpDnsInfo_4A = cacheInfo[kMSDKHttpDnsInfo_4A];
            if (httpDnsInfo_4A) {
                httpDnsErrCode_4A = httpDnsInfo_A[kDnsErrCode];
                httpDnsErrMsg_4A = httpDnsInfo_A[kDnsErrMsg];
                httpDnsRetry_4A = httpDnsInfo_A[kDnsRetry];
            }
            
            NSDictionary * httpDnsInfo_BOTH = cacheInfo[kMSDKHttpDnsInfo_BOTH];
            if (httpDnsInfo_BOTH) {
                httpDnsErrCode_BOTH = httpDnsInfo_BOTH[kDnsErrCode];
                httpDnsErrMsg_BOTH = httpDnsInfo_BOTH[kDnsErrMsg];
                httpDnsRetry_BOTH = httpDnsInfo_BOTH[kDnsRetry];
            }
        }
    }
    
    //Channel
    [params setValue:channel forKey:kMSDKDnsChannel];
    
    //clientIP
    [params setValue:clientIP_A forKey:kMSDKDns_A_ClientIP];
    [params setValue:clientIP_4A forKey:kMSDKDns_4A_ClientIP];
    
    //hdns_ip
    [params setValue:httpDnsIP_A forKey:kMSDKDns_A_IP];
    [params setValue:httpDnsIP_4A forKey:kMSDKDns_4A_IP];
    
    //ldns_ip
    [params setValue:localDnsIPs forKey:kMSDKDnsLDNS_IP];
    
    //hdns_time
    [params setValue:httpDnsTimeConsuming_A forKey:kMSDKDns_A_Time];
    [params setValue:httpDnsTimeConsuming_4A forKey:kMSDKDns_4A_Time];
    
    //ldns_time
    [params setValue:localDnsTimeConsuming forKey:kMSDKDnsLDNS_Time];
    
    //TTL
    [params setValue:httpDnsTTL_A forKey:kMSDKDns_A_TTL];
    [params setValue:httpDnsTTL_4A forKey:kMSDKDns_4A_TTL];
    
    //ErrCode
    [params setValue:httpDnsErrCode_A forKey:kMSDKDns_A_ErrCode];
    [params setValue:httpDnsErrCode_4A forKey:kMSDKDns_4A_ErrCode];
    [params setValue:httpDnsErrCode_BOTH forKey:kMSDKDns_BOTH_ErrCode];
    
    //ErrMsg
    [params setValue:httpDnsErrMsg_A forKey:kMSDKDns_A_ErrMsg];
    [params setValue:httpDnsErrMsg_4A forKey:kMSDKDns_4A_ErrMsg];
    [params setValue:httpDnsErrMsg_BOTH forKey:kMSDKDns_BOTH_ErrMsg];
    
    //Retry
    [params setValue:httpDnsRetry_A forKey:kMSDKDns_A_Retry];
    [params setValue:httpDnsRetry_4A forKey:kMSDKDns_4A_Retry];
    [params setValue:httpDnsRetry_BOTH forKey:kMSDKDns_BOTH_Retry];
    
    //dns
    [params setValue:dns_A forKey:kMSDKDns_DNS_A_IP];
    [params setValue:dns_4A forKey:kMSDKDns_DNS_4A_IP];

    return params;
}

# pragma mark - check caches

// 检查缓存状态
- (NSString *) domainCache:(NSDictionary *)cache check:(NSString *)domain {
    NSDictionary * domainInfo = cache[domain];
    if (domainInfo && [domainInfo isKindOfClass:[NSDictionary class]]) {
        NSDictionary * cacheDict = domainInfo[kMSDKHttpDnsCache_A];
        if (!cacheDict || ![cacheDict isKindOfClass:[NSDictionary class]]) {
            cacheDict = domainInfo[kMSDKHttpDnsCache_4A];
        }
        if (cacheDict && [cacheDict isKindOfClass:[NSDictionary class]]) {
            NSString * ttlExpried = cacheDict[kTTLExpired];
            double timeInterval = [[NSDate date] timeIntervalSince1970];
            if (timeInterval <= ttlExpried.doubleValue) {
                return MSDKDnsDomainCacheHit;
            } else {
                return MSDKDnsDomainCacheExpired;
            }
        }
    }
    return MSDKDnsDomainCacheEmpty;
}

- (void)loadIPsFromPersistCacheAsync {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        NSDictionary *result = [[MSDKDnsDB shareInstance] getDataFromDB];
        MSDKDNSLOG(@"loadDB domainInfo = %@",result);
        NSMutableArray *expiredDomains = [[NSMutableArray alloc] init];
        for (NSString *domain in result) {
            NSDictionary *domainInfo = [result valueForKey:domain];
            if ([self isDomainCacheExpired:domainInfo]) {
                [expiredDomains addObject:domain];
            }
            [self cacheDomainInfo:domainInfo domain:domain];
        }
        // 删除本地持久化缓存中过期缓存
        if (expiredDomains && expiredDomains.count > 0){
            [[MSDKDnsDB shareInstance] deleteDBData:expiredDomains];
        }
    });
}

- (BOOL)isDomainCacheExpired: (NSDictionary *)domainInfo {
    NSDictionary *httpDnsIPV4Info = [domainInfo valueForKey:kMSDKHttpDnsCache_A];
    NSDictionary *httpDnsIPV6Info = [domainInfo valueForKey:kMSDKHttpDnsCache_4A];
    NSMutableString *expiredTime = [[NSMutableString alloc] init];
    double nowTime = [[NSDate date] timeIntervalSince1970];
    if (httpDnsIPV4Info) {
        NSString *ipv4ExpiredTime = [httpDnsIPV4Info valueForKey:kTTLExpired];
        if (ipv4ExpiredTime) {
            expiredTime = [[NSMutableString alloc]initWithString:ipv4ExpiredTime];
        }
    }
    if (httpDnsIPV6Info) {
        NSString *ipv6ExpiredTime = [httpDnsIPV6Info valueForKey:kTTLExpired];
        if (ipv6ExpiredTime) {
            expiredTime = [[NSMutableString alloc]initWithString:ipv6ExpiredTime];
        }
    }
    if (expiredTime && nowTime <= expiredTime.doubleValue) {
        return false;
    }
    return true;
}

# pragma mark - detect address type
- (msdkdns::MSDKDNS_TLocalIPStack)detectAddressType {
    msdkdns::MSDKDNS_TLocalIPStack netStack = msdkdns::MSDKDNS_ELocalIPStack_None;
    switch ([[MSDKDnsParamsManager shareInstance] msdkDnsGetAddressType]) {
        case HttpDnsAddressTypeIPv4:
            netStack = msdkdns::MSDKDNS_ELocalIPStack_IPv4;
            break;
        case HttpDnsAddressTypeIPv6:
            netStack = msdkdns::MSDKDNS_ELocalIPStack_IPv6;
            break;
        case HttpDnsAddressTypeDual:
            netStack = msdkdns::MSDKDNS_ELocalIPStack_Dual;
            break;
        default:
            netStack = msdkdns::msdkdns_detect_local_ip_stack();
            break;
    }
    return netStack;
}

- (int)getAddressType {
    return [self detectAddressType];
}


# pragma mark - servers

- (void)fetchConfig:(int) mdnsId encryptType:(HttpDnsEncryptType)mdnsEncryptType dnsKey:(NSString *)mdnsKey token:(NSString* )mdnsToken {
    
    NSString *ipAddress = @"";
#ifdef httpdnsIps_h
#if IS_INTL
    ipAddress = MSDKDnsFetchConfigHttpUrl_INTL;
#else
    ipAddress = MSDKDnsFetchConfigHttpUrl;
#endif
#endif
    
    NSString *protocol = @"http";
    NSString *alg = @"des";
    if (mdnsEncryptType == HttpDnsEncryptTypeAES) {
        alg = @"aes";
    } else if (mdnsEncryptType == HttpDnsEncryptTypeHTTPS) {
#ifdef httpdnsIps_h
#if IS_INTL
        ipAddress = @"";
#else
        ipAddress = MSDKDnsFetchConfigHttpsUrl;
#endif
#endif
        protocol = @"https";
    }
    
    NSString * urlStr = [NSString stringWithFormat:@"%@://%@/conf?id=%d&alg=%@", protocol, ipAddress, mdnsId, alg];
    
    if (mdnsEncryptType == HttpDnsEncryptTypeHTTPS) {
        urlStr = [NSString stringWithFormat:@"%@://%@/conf?token=%@", protocol, ipAddress, mdnsToken];
    }
    
//    NSLog(@"urlStr ==== %@", urlStr);
    //    NSURL *url = [NSURL URLWithString:@"http://182.254.60.40/conf?id=96157&alg=des"];
    NSURL *url = [NSURL URLWithString:urlStr];
    self.request = [NSMutableURLRequest requestWithURL:url];
    NSURLSessionDataTask *dataTask = [[NSURLSession sharedSession] dataTaskWithRequest:self.request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (data && (error == nil)) {
            // 网络访问成功，解析数据
            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if(![str isEqualToString:@""]){
//                NSLog(@"data is %@",str);
                if (mdnsEncryptType != HttpDnsEncryptTypeHTTPS && mdnsKey && mdnsKey.length > 0) {
                    if (mdnsEncryptType == 0) {
                        str = [MSDKDnsInfoTool decryptUseDES:str key:mdnsKey];
                    } else {
                        str = [MSDKDnsInfoTool decryptUseAES:str key:mdnsKey];
                    }
                }
                NSDictionary *configDict = [self parseAllConfigString:str];
                if(configDict && [configDict objectForKey:@"log"]){
                    NSString *logValue = [configDict objectForKey:@"log"];
                    [[MSDKDnsParamsManager shareInstance] msdkDnsSetEnableReport:[logValue isEqualToString:@"1"]?YES:NO];
                    MSDKDNSLOG(@"Successfully get configuration.config data is %@, %@",str,configDict);
                }else{
//                    MSDKDNSLOG(@"Failed to get configuration，error：%@",str);
                }
                // NSLog(@"configDict = %@",configDict);
//                暂时测试，默认开启探测三网域名IP
                // [[MSDKDnsManager shareInstance] detectHttpDnsServers];
                if(configDict && [configDict objectForKey:@"domain"]){
                    NSString *domainValue = [configDict objectForKey:@"domain"];
                    if ([domainValue isEqualToString:@"1"]) {
                        [[MSDKDnsParamsManager shareInstance] msdkDnsSetEnableDetectHostServer:YES];
                        [[MSDKDnsManager shareInstance] detectHttpDnsServers];
                    }
                    // MSDKDNSLOG(@"Successfully get configuration.config data is %@, %@",str,configDict);
                }
            }
        } else {
            // 网络访问失败
            MSDKDNSLOG(@"Failed to get configuration，error：%@",error);
        }
    }];
    [dataTask resume];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * __nullable credential))completionHandler {
    if (!challenge) {
        return;
    }

    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    NSURLCredential *credential = nil;

    //获取原始域名信息
    NSString *host = [[self.request allHTTPHeaderFields] objectForKey:@"host"];
    if (!host) {
        host = self.request.URL.host;
    }
    if ([challenge.protectionSpace.authenticationMethod  isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if ([self evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:host]) {
            disposition = NSURLSessionAuthChallengeUseCredential;
            credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        } else {
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        }
    } else {
        disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    }
    completionHandler(disposition,credential);
}


- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust forDomain:(NSString *)domain {
    /*
     * 创建证书校验策略
     */
    NSMutableArray *policies = [NSMutableArray array];
    if (domain) {
        [policies addObject:(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];
    } else {
        [policies addObject:(__bridge_transfer id)SecPolicyCreateBasicX509()];
    }
    
    /*
     * 绑定校验策略到服务端的证书上
     */
    SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies);
    
    /*
     * 评估当前serverTrust是否可信任，
     * 官方建议在result = kSecTrustResultUnspecified 或 kSecTrustResultProceed
     * 的情况下serverTrust可以被验证通过，https://developer.apple.com/library/ios/technotes/tn2232/_index.html
     * 关于SecTrustResultType的详细信息请参考SecTrust.h
     */
    SecTrustResultType result;
    SecTrustEvaluate(serverTrust, &result);
    
    return (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
}

//将获取到的配置string转换为数据字典格式
- (NSDictionary *)parseAllConfigString:(NSString *)configString {
    NSArray *array = [configString componentsSeparatedByString:@"|"];
    if (array && array.count >= 2) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for (int i = 0; i < array.count; i++) {
            NSString *item = array[i];
            if(item){
                NSArray * itemArr = [item componentsSeparatedByString:@":"];
                if (itemArr && [itemArr count] == 2) {
                    NSString *key = itemArr[0];
                    NSString *value = itemArr[1];
                    [result setObject:value forKey:key];
                }
            }
        }
        return result;
    }
    return nil;
}

- (void)detectHttpDnsServers {
    // 先重置为兜底ip
    [self resetDnsServers:nil];
    // https 协议下不进行三网探测
    if ([[MSDKDnsParamsManager shareInstance] msdkDnsGetEncryptType] == HttpDnsEncryptTypeHTTPS) {
        return;
    }
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        NSString *domain = @"";
        int dnsId = 0;
        NSString *dnsKey = @"";
#ifdef httpdnsIps_h
    #if IS_INTL
        domain = MSDKDnsServerDomain_INTL;
        dnsId = MSDKDnsId_INTL;
        dnsKey = MSDKDnsKey_INTL;
    #else
        domain = MSDKDnsServerDomain;
        dnsId = MSDKDnsId;
        dnsKey = MSDKDnsKey;
    #endif
#endif
        if (![domain isEqualToString:@""] && dnsId != 0 && ![dnsKey isEqualToString:@""]) {
            NSArray *domains = @[domain];
            msdkdns::MSDKDNS_TLocalIPStack netStack = msdkdns::MSDKDNS_ELocalIPStack_IPv4;
            BOOL httpOnly = true;
            HttpDnsEncryptType encryptType = HttpDnsEncryptTypeDES;
            MSDKDnsService * dnsService = [[MSDKDnsService alloc] init];
            __weak __typeof__(self) weakSelf = self;
            __block float timeOut = 2.0;
            self.sdkStatus = net_detecting;
            [dnsService getHttpDNSDomainIPsByNames:domains
                                           timeOut:timeOut
                                             dnsId:dnsId
                                            dnsKey:dnsKey
                                          netStack:netStack
                                       encryptType:encryptType
                                          httpOnly:httpOnly
                                              from:MSDKDnsEventHttpDnsGetHTTPDNSDomainIP
                                         returnIps:^{
                __strong __typeof(self) strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf uploadReport:NO domain:domain netStack:netStack];
                    NSDictionary * result = [strongSelf fullResultDictionary:domains fromCache:self.domainDict];
                    NSDictionary *ips = [result objectForKey:domain];
                    NSLog(@"ips === %@", ips);
                    NSArray *ipv4s = [ips objectForKey:@"ipv4"];
                    NSArray *ipv6s = [ips objectForKey:@"ipv6"];
                    if (ipv4s && [ipv4s count] > 0) {
                        [self resetDnsServers:ipv4s];
                        self.sdkStatus = net_detected;
                    } else if (ipv6s && [ipv6s count] > 0) {
                        [self resetDnsServers:ipv6s];
                        self.sdkStatus = net_detected;
                    } else {
                        self.sdkStatus = net_undetected;
                    }
                }
            }];
        } else {
            MSDKDNSLOG(@"三网解析域名、dnsId或者dnsKey配置为空.");
        }
    });
}

- (NSString *)currentDnsServer {
    int index = self.serverIndex;
    if (self.dnsServers != nil && [self.dnsServers count] > 0 && index >= 0 && index < [self.dnsServers count]) {
        return self.dnsServers[index];
    }
    return  [[self defaultServers] firstObject];
}

- (void)switchDnsServer {
    if (self.waitToSwitch) {
        return;
    }
    self.waitToSwitch = YES;
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        if (self.serverIndex < [self.dnsServers count] - 1) {
            self.serverIndex += 1;
            if (!self.firstFailTime) {
                self.firstFailTime = [NSDate date];
                // 一定时间后自动切回主ip
                __weak __typeof__(self) weakSelf = self;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,[[MSDKDnsParamsManager shareInstance] msdkDnsGetMinutesBeforeSwitchToMain] * 60 * NSEC_PER_SEC), [MSDKDnsInfoTool msdkdns_queue], ^{
                    if (weakSelf.firstFailTime && [[NSDate date] timeIntervalSinceDate:weakSelf.firstFailTime] >= [[MSDKDnsParamsManager shareInstance] msdkDnsGetMinutesBeforeSwitchToMain] * 60) {
                        MSDKDNSLOG(@"auto reset server index, use main ip now.");
                        weakSelf.serverIndex = 0;
                        weakSelf.firstFailTime = nil;
                    }
                });
            }
        } else {
            self.serverIndex = 0;
            self.firstFailTime = nil;
        }
        self.waitToSwitch = NO;
    });
}

- (void)switchToMainServer {
    if (self.serverIndex == 0) {
        return;
    }
    MSDKDNSLOG(@"switch back to main server ip.");
    self.waitToSwitch = YES;
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.serverIndex = 0;
        self.firstFailTime = nil;
        self.waitToSwitch = NO;
    });
}

- (void)resetDnsServers:(NSArray *)servers {
    self.waitToSwitch = YES;
    dispatch_barrier_async([MSDKDnsInfoTool msdkdns_resolver_queue], ^{
        NSMutableArray *array = [[NSMutableArray alloc] init];
        if (servers && [servers count] > 0) {
            [array addObjectsFromArray: servers];
        }
        [array addObjectsFromArray:[self defaultServers]];
        self.serverIndex = 0;
        self.dnsServers = array;
        self.waitToSwitch = NO;
    });
}

- (NSArray *)defaultServers {
    NSMutableArray *servers = [[NSMutableArray alloc] init];
#ifdef httpdnsIps_h
    #if IS_INTL
        if ([[MSDKDnsParamsManager shareInstance] msdkDnsGetEncryptType] != HttpDnsEncryptTypeHTTPS) {
            [servers addObjectsFromArray: MSDKDnsHttpServerIps_INTL];
        } else {
            // 国际站SDK暂不支持HTTPS解析
        }
    #else
        if ([[MSDKDnsParamsManager shareInstance] msdkDnsGetEncryptType] == HttpDnsEncryptTypeHTTPS) {
            [servers addObjectsFromArray: MSDKDnsHttpsServerIps];
        } else {
            [servers addObjectsFromArray: MSDKDnsHttpServerIps];
        }
    #endif
#endif
    return servers;
}

# pragma mark - operate delay tag

- (void)msdkDnsAddDomainOpenDelayDispatch: (NSString *)domain {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        if (domain && domain.length > 0) {
            MSDKDNSLOG(@"domainISOpenDelayDispatch add domain:%@", domain);
            if (!self.domainISOpenDelayDispatch) {
                self.domainISOpenDelayDispatch = [[NSMutableDictionary alloc] init];
            }
            [self.domainISOpenDelayDispatch setObject:@YES forKey:domain];
        }
    });
}

- (void)msdkDnsClearDomainOpenDelayDispatch:(NSString *)domain {
    if (domain && domain.length > 0) {
        //  NSLog(@"请求结束，清除标志.请求域名为%@",domain);
        MSDKDNSLOG(@"The cache update request end! request domain:%@",domain);
        MSDKDNSLOG(@"domainISOpenDelayDispatch remove domain:%@", domain);
        if (self.domainISOpenDelayDispatch) {
            [self.domainISOpenDelayDispatch removeObjectForKey:domain];
        }
    }
}

- (void)msdkDnsClearDomainsOpenDelayDispatch:(NSArray *)domains {
    for(int i = 0; i < [domains count]; i++) {
        NSString* domain = [domains objectAtIndex:i];
        [self msdkDnsClearDomainOpenDelayDispatch:domain];
    }
}

- (NSMutableDictionary *)msdkDnsGetDomainISOpenDelayDispatch {
    return _domainISOpenDelayDispatch;
}

@end
