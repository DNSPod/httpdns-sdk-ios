/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import "MSDKDnsManager.h"
#import "MSDKDnsService.h"
#import "MSDKDnsLog.h"
#import "MSDKDns.h"
#import "MSDKDnsInfoTool.h"
#import "MSDKDnsParamsManager.h"
#import "MSDKDnsNetworkManager.h"
#import "msdkdns_local_ip_stack.h"
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
}

#pragma mark - init

static MSDKDnsManager * _sharedInstance = nil;
+ (instancetype)shareInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[MSDKDnsManager alloc] init];
    });
    return _sharedInstance;
}

- (instancetype) init {
    if (self = [super init]) {
        _serverIndex = 0;
        _firstFailTime = nil;
        _waitToSwitch = NO;
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
    NSMutableArray *toCheckDomains = [NSMutableArray array];
    // 查找缓存，缓存中有HttpDns数据且ttl未超时则直接返回结果,不存在或者ttl超时则放入待查询数组
    for (int i = 0; i < [domains count]; i++) {
        NSString *domain = [domains objectAtIndex:i];
        if (![self domianCache:cacheDomainDict hit:domain]) {
            [toCheckDomains addObject:domain];
        } else {
            MSDKDNSLOG(@"%@ TTL has not expiried,return result from cache directly!", domain);
            dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
                [self uploadReport:YES Domain:domain NetStack:netStack];
            });
        }
    }
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
        if (!_serviceArray) {
            self.serviceArray = [[NSMutableArray alloc] init];
        }
        int dnsId = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsId];
        NSString * dnsKey = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsKey];
        HttpDnsEncryptType encryptType = [[MSDKDnsParamsManager shareInstance] msdkDnsGetEncryptType];
        //进行httpdns请求
        MSDKDnsService * dnsService = [[MSDKDnsService alloc] init];
        [self.serviceArray addObject:dnsService];
        __weak __typeof__(self) weakSelf = self;
        // NSLog(@"%@, MSDKDns Result is toCheckDomains",toCheckDomains);
        [dnsService getHostsByNames:toCheckDomains TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:netStack encryptType:encryptType returnIps:^() {
            __strong __typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                [toCheckDomains enumerateObjectsUsingBlock:^(id _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    [strongSelf uploadReport:NO Domain:obj NetStack:netStack];
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
        if ([[self domianCache:cacheDomainDict check:domain] isEqualToString:MSDKDnsDomainCacheEmpty]) {
            [toCheckDomains addObject:domain];
        } else if ([[self domianCache:cacheDomainDict check:domain] isEqualToString:MSDKDnsDomainCacheExpired]) {
            [toCheckDomains addObject:domain];
            [toEmptyDomains addObject:domain];
        } else {
            MSDKDNSLOG(@"%@ TTL has not expiried,return result from cache directly!", domain);
            dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
                [self uploadReport:YES Domain:domain NetStack:netStack];
            });
        }
    }
    // 当待查询数组中存在数据的时候，就开启异步线程执行解析操作，并且更新缓存
    if (toCheckDomains && [toCheckDomains count] != 0) {
        dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
            if (!_serviceArray) {
                self.serviceArray = [[NSMutableArray alloc] init];
            }
            int dnsId = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsId];
            NSString * dnsKey = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsKey];
            HttpDnsEncryptType encryptType = [[MSDKDnsParamsManager shareInstance] msdkDnsGetEncryptType];
            MSDKDnsService * dnsService = [[MSDKDnsService alloc] init];
            [self.serviceArray addObject:dnsService];
            __weak __typeof__(self) weakSelf = self;
            //进行httpdns请求
            [dnsService getHostsByNames:toCheckDomains TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:netStack encryptType:encryptType returnIps:^() {
                __strong __typeof(self) strongSelf = weakSelf;
                if (strongSelf) {
                    [toCheckDomains enumerateObjectsUsingBlock:^(id _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                        [strongSelf uploadReport:NO Domain:obj NetStack:netStack];
                    }];
                    [strongSelf dnsHasDone:dnsService];
                }
            }];
        });
    }
    NSDictionary * result = verbose?
        [self fullResultDictionaryEnableExpired:domains fromCache:cacheDomainDict toEmpty:toEmptyDomains] :
        [self resultDictionaryEnableExpired:domains fromCache:cacheDomainDict toEmpty:toEmptyDomains];
    return result;
}

#pragma mark async

- (void)getHostsByNames:(NSArray *)domains
                verbose:(BOOL)verbose
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
    NSMutableArray *toCheckDomains = [NSMutableArray array];
    // 查找缓存，缓存中有HttpDns数据且ttl未超时则直接返回结果,不存在或者ttl超时则放入待查询数组
    for (int i = 0; i < [domains count]; i++) {
        NSString *domain = [domains objectAtIndex:i];
        if (![self domianCache:cacheDomainDict hit:domain]) {
            [toCheckDomains addObject:domain];
        } else {
            MSDKDNSLOG(@"%@ TTL has not expiried,return result from cache directly!", domain);
            dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
                [self uploadReport:YES Domain:domain NetStack:netStack];
            });
        }
    }
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
        if (!_serviceArray) {
            self.serviceArray = [[NSMutableArray alloc] init];
        }
        int dnsId = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsId];
        NSString * dnsKey = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsKey];
        //进行httpdns请求
        MSDKDnsService * dnsService = [[MSDKDnsService alloc] init];
        [self.serviceArray addObject:dnsService];
        __weak __typeof__(self) weakSelf = self;
        HttpDnsEncryptType encryptType = [[MSDKDnsParamsManager shareInstance] msdkDnsGetEncryptType];
        [dnsService getHostsByNames:toCheckDomains TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:netStack encryptType:encryptType returnIps:^() {
            __strong __typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                [toCheckDomains enumerateObjectsUsingBlock:^(id _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    [strongSelf uploadReport:NO Domain:obj NetStack:netStack];
                }];
                [strongSelf dnsHasDone:dnsService];
                NSDictionary * result = verbose ?
                    [strongSelf fullResultDictionary:domains fromCache:_domainDict] :
                    [strongSelf resultDictionary:domains fromCache:_domainDict];
                if (handler) {
                    handler(result);
                }
            }
        }];
    });
    
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
    [dnsService getHostsByNames:domains TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:netStack encryptType:encryptType returnIps:^{
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
        [self getHostsByNames:domains verbose:NO returnIps:^(NSDictionary *ipsDict) {
            if (ipsDict) {
                MSDKDNSLOG(@"preResolve domains success.");
            } else {
                MSDKDNSLOG(@"preResolve domains failed.");
            }
        }];
    }
}

#pragma mark - dns resolve

- (NSString *)getIPsStringFromIPsArray:(NSArray *)ipsArray {
    NSMutableString *ipsStr = [NSMutableString stringWithString:@""];
    if (ipsArray && [ipsArray isKindOfClass:[NSArray class]] && ipsArray.count > 0) {
        for (int i = 0; i < ipsArray.count; i++) {
            NSString *ip = ipsArray[i];
            if (i != ipsArray.count - 1) {
                [ipsStr appendFormat:@"%@,",ip];
            } else {
                [ipsStr appendString:ip];
            }
        }
    }
    return ipsStr;
}

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
    NSMutableDictionary *resultDict = [NSMutableDictionary dictionary];
    for (int i = 0; i < [domains count]; i++) {
        NSString *domain = [domains objectAtIndex:i];
        NSMutableDictionary * ipResult = [NSMutableDictionary dictionary];
        BOOL httpOnly = [[MSDKDnsParamsManager shareInstance] msdkDnsGetHttpOnly];
        if (domainDict) {
            NSDictionary * cacheDict = domainDict[domain];
            if (cacheDict && [cacheDict isKindOfClass:[NSDictionary class]]) {
                
                NSDictionary * hresultDict_A = cacheDict[kMSDKHttpDnsCache_A];
                NSDictionary * hresultDict_4A = cacheDict[kMSDKHttpDnsCache_4A];
                
                if (!httpOnly) {
                    NSDictionary * lresultDict = cacheDict[kMSDKLocalDnsCache];
                    if (lresultDict && [lresultDict isKindOfClass:[NSDictionary class]]) {
                        NSArray *ipsArray = [lresultDict[kIP] mutableCopy];
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
    for (int i = 0; i < [domains count]; i++) {
        NSString *domain = [domains objectAtIndex:i];
        BOOL domainNeedEmpty = [emptyDomains containsObject:domain];
        NSMutableDictionary * ipResult = [NSMutableDictionary dictionary];
        BOOL httpOnly = [[MSDKDnsParamsManager shareInstance] msdkDnsGetHttpOnly];
        if (domainDict) {
            NSDictionary * cacheDict = domainDict[domain];
            if (cacheDict && [cacheDict isKindOfClass:[NSDictionary class]]) {
                
                NSDictionary * hresultDict_A = cacheDict[kMSDKHttpDnsCache_A];
                NSDictionary * hresultDict_4A = cacheDict[kMSDKHttpDnsCache_4A];
                
                if (!httpOnly) {
                    NSDictionary * lresultDict = cacheDict[kMSDKLocalDnsCache];
                    if (lresultDict && [lresultDict isKindOfClass:[NSDictionary class]]) {
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
                if (hresultDict_A && [hresultDict_A isKindOfClass:[NSDictionary class]]) {
                    NSArray * ipsArray = hresultDict_A[kIP];
                    if (ipsArray && [ipsArray isKindOfClass:[NSArray class]] && ipsArray.count > 0) {
                        // 缓存过期，并且没有开启使用过期缓存
                        if (domainNeedEmpty && !expiredIPEnabled) {
                            [ipResult setObject:@[@0] forKey:@"ipv4"];
                        } else {
                            [ipResult setObject:ipsArray forKey:@"ipv4"];
                        }
                    }
                }
                if (hresultDict_4A && [hresultDict_4A isKindOfClass:[NSDictionary class]]) {
                    NSArray * ipsArray = hresultDict_4A[kIP];
                    if (ipsArray && [ipsArray isKindOfClass:[NSArray class]] && ipsArray.count > 0) {
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
                detailDict[@"v4_ips"] = [self getIPsStringFromIPsArray:cacheDict_A[kIP]];
                detailDict[@"v4_ttl"] = cacheDict_A[kTTL];
                detailDict[@"v4_client_ip"] = cacheDict_A[kClientIP];
            }
            NSDictionary * cacheDict_4A = domainInfo[kMSDKHttpDnsCache_4A];
            if (cacheDict_4A && [cacheDict_4A isKindOfClass:[NSDictionary class]]) {
                detailDict[@"v6_ips"] = [self getIPsStringFromIPsArray:cacheDict_4A[kIP]];
                detailDict[@"v6_ttl"] = cacheDict_4A[kTTL];
                detailDict[@"v6_client_ip"] = cacheDict_4A[kClientIP];
            }
        }
    }
    return detailDict;
}

#pragma mark - clear cache

- (void)cacheDomainInfo:(NSDictionary *)domainInfo Domain:(NSString *)domain {
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
    for(int i = 0; i < [domains count]; i++) {
        NSString* domain = [domains objectAtIndex:i];
        [self clearCacheForDomain:domain];
    }
}

- (void)clearAllCache {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        MSDKDNSLOG(@"MSDKDns clearCache");
        if (self.domainDict) {
            [self.domainDict removeAllObjects];
            self.domainDict = nil;
        }
    });
}

#pragma mark - uploadReport
- (void)uploadReport:(BOOL)isFromCache Domain:(NSString *)domain NetStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack {
    Class beaconClass = NSClassFromString(@"BeaconBaseInterface");
    if (beaconClass == 0x0) {
        MSDKDNSLOG(@"Beacon framework is not imported");
        return;
    }

    // 反射调用
    // [BeaconBaseInterface onUserAction:MSDKDnsEventName isSucceed:YES elapse:0 size:0 params:params];
    SEL methodSelector = NSSelectorFromString(@"onUserAction:isSucceed:elapse:size:params:");
    NSMethodSignature *methodSignature = [beaconClass methodSignatureForSelector:methodSelector];
    NSInvocation *myInvocation = [NSInvocation invocationWithMethodSignature:methodSignature];
    [myInvocation setTarget:beaconClass];
    [myInvocation setSelector:methodSelector];
    // 接口传参
    NSString *eventName = MSDKDnsEventName;
    [myInvocation setArgument:&eventName atIndex:2];
    BOOL success = YES;
    [myInvocation setArgument:&success atIndex:3];
    NSUInteger elapse = 0;
    [myInvocation setArgument:&elapse atIndex:4];
    NSUInteger size = 0;
    [myInvocation setArgument:&size atIndex:5];
    NSMutableDictionary *params = [self formatParams:isFromCache Domain:domain NetStack:netStack];
    [myInvocation setArgument:&params atIndex:6];
    // 在调用结束前，保持参数
    [myInvocation retainArguments];

    [myInvocation invoke];

    MSDKDNSLOG(@"ReportingEvent, name:%@, events:%@", eventName, params);
}

- (NSMutableDictionary *)formatParams:(BOOL)isFromCache Domain:(NSString *)domain NetStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack {
    MSDKDNSLOG(@"uploadReport %@",domain);
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
    
    //SSID
//    NSString * ssid = [MSDKDnsInfoTool wifiSSID];
//    [params setValue:ssid forKey:kMSDKDnsSSID];
    
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
    
    NSDictionary * cacheDict = [[MSDKDnsManager shareInstance] domainDict];
    if (cacheDict && domain) {
        NSDictionary * cacheInfo = cacheDict[domain];
        if (cacheInfo) {
            
            NSDictionary * localDnsCache = cacheInfo[kMSDKLocalDnsCache];
            if (localDnsCache) {
                NSArray * ipsArray = localDnsCache[kIP];
                if (ipsArray && [ipsArray count] == 2) {
                    dns_A = ipsArray[0];
                    dns_4A = ipsArray[1];
                    localDnsIPs = [self getIPsStringFromIPsArray:ipsArray];
                }
                localDnsTimeConsuming = localDnsCache[kDnsTimeConsuming];
            }
            
            NSDictionary * httpDnsCache_A = cacheInfo[kMSDKHttpDnsCache_A];
            if (httpDnsCache_A) {
                
                clientIP_A = httpDnsCache_A[kClientIP];
                NSArray * ipsArray = httpDnsCache_A[kIP];
                if (ipsArray && [ipsArray isKindOfClass:[NSArray class]] && ipsArray.count > 0) {
                    dns_A = ipsArray[0];
                    httpDnsIP_A = [self getIPsStringFromIPsArray:ipsArray];
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
                    httpDnsIP_4A = [self getIPsStringFromIPsArray:ipsArray];
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
// 检查是否命中缓存
- (BOOL) domianCache:(NSDictionary *)cache hit:(NSString *)domain {
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
                return YES;
            }
        }
    }
    return NO;
}

# pragma mark - check caches
// 检查缓存状态
- (NSString *) domianCache:(NSDictionary *)cache check:(NSString *)domain {
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


# pragma mark - servers
- (NSString *)currentDnsServer {
    int index = self.serverIndex;
    if (index < [[[MSDKDnsParamsManager shareInstance] msdkDnsGetServerIps] count]) {
        return  [[[MSDKDnsParamsManager shareInstance] msdkDnsGetServerIps] objectAtIndex:index];
    }
    return  [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsIp];
}

- (void)switchDnsServer {
    if (self.waitToSwitch) {
        return;
    }
    self.waitToSwitch = YES;
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        if (self.serverIndex < [[[MSDKDnsParamsManager shareInstance] msdkDnsGetServerIps] count] - 1) {
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
