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
#import "MSDKDnsUUIDManager.h"

static const NSString * BeaconAppkey = @"DOU0FVFIN4G5KYK";

@interface MSDKDnsManager ()

@property (strong, nonatomic, readwrite) NSMutableArray * serviceArray;
@property (strong, nonatomic, readwrite) NSMutableDictionary * domainDict;
@property (strong, nonatomic, readwrite) id beaconInstance;

@end

@implementation MSDKDnsManager

+(id)reflectInvocation:(id)target selector:(SEL)selector params:(NSArray*)params
{
    NSMethodSignature *methodSignature = [target methodSignatureForSelector:selector];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
    [invocation setTarget:target];
    [invocation setSelector:selector];
    if (params && params.count > 0) {
        for (int i = 0; i < params.count; i++) {
            id arg = [params objectAtIndex:i];
            [invocation setArgument:&arg atIndex:2+i];
        }
        [invocation retainArguments];
    }
    [invocation invoke];
    // 判断是否有返回值
    if (methodSignature.methodReturnLength) {
        __weak id weakReturnValue;
        [invocation getReturnValue:&weakReturnValue];
        id returnValue = weakReturnValue;
        return returnValue;
    }
    return nil;
}

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

static MSDKDnsManager * _sharedInstance = nil;
+ (instancetype)shareInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[MSDKDnsManager alloc] init];
        [_sharedInstance initBeaconReport];
    });
    return _sharedInstance;
}

- (void)initBeaconReport {
    Class beaconClass = NSClassFromString(@"BeaconReport");
    if (beaconClass == 0x0) {
        MSDKDNSLOG(@"Beacon framework is not imported");
        return;
    }
//    [BeaconReport sharedInstance];
    self.beaconInstance = [self.class reflectInvocation:beaconClass selector:NSSelectorFromString(@"sharedInstance") params:nil];
//    [BeaconReport.sharedInstance startWithAppkey:@"0DOU0FVFIN4G5KYK" config:nil];
    [self.class reflectInvocation:self.beaconInstance selector:NSSelectorFromString(@"startWithAppkey:config:") params:@[BeaconAppkey]];
//    [BeaconReport.sharedInstance setOStarO16:@"dnspod-test-o16" o36:nil];
    NSString *deviceId = [MSDKDnsUUIDManager getUUID];
    [self.class reflectInvocation:self.beaconInstance selector:NSSelectorFromString(@"setOStarO16:o36:") params:@[deviceId]];
//    [BeaconReport.sharedInstance setLogLevel:10];
    /// 设置本地调试时控制台输出的日志级别：1 fetal, 2 error, 3 warn, 4 info, debug, 5 debug, 10 all, 默认为0，不打印日志
//    [self.class reflectInvocation:self.beaconInstance selector:NSSelectorFromString(@"setLogLevel:") params:@[@2]];
    MSDKDNSLOG(@"BeaconReport init success: deviceId = %@", deviceId);
}

- (NSArray *) getHostByName:(NSString *)domain {
    // 获取当前ipv4/ipv6/双栈网络环境
    msdkdns::MSDKDNS_TLocalIPStack netStack = msdkdns::msdkdns_detect_local_ip_stack();
    __block float timeOut = 2.0;
    __block NSDictionary * cacheDomainDict = nil;
    dispatch_sync([MSDKDnsInfoTool msdkdns_queue], ^{
        if (domain && _domainDict) {
            cacheDomainDict = [[NSDictionary alloc] initWithDictionary:_domainDict];
        }
        timeOut = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMTimeOut];
    });
    //查找缓存，缓存中有HttpDns数据且ttl为超时则直接返回结果,不存在或者ttl超时则重新查询
    if (cacheDomainDict) {
        NSDictionary * domainInfo = cacheDomainDict[domain];
        if (domainInfo && [domainInfo isKindOfClass:[NSDictionary class]]) {
            NSDictionary * cacheDict = domainInfo[kMSDKHttpDnsCache_A];
            if (!cacheDict || ![cacheDict isKindOfClass:[NSDictionary class]]) {
                cacheDict = domainInfo[kMSDKHttpDnsCache_4A];
            }
            if (cacheDict && [cacheDict isKindOfClass:[NSDictionary class]]) {
                NSString * ttlExpried = cacheDict[kTTLExpired];
                double timeInterval = [[NSDate date] timeIntervalSince1970];
                if (timeInterval <= ttlExpried.doubleValue) {
                    MSDKDNSLOG(@"TTL has not expiried,return result from cache directly!");
                    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
                        [self uploadReport:YES Domain:domain NetStack:netStack];
                    });
                    NSArray * result = [self resultArray:domain DomainDic:cacheDomainDict];
                    return result;
                }
            }
        }
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
        [dnsService getHostByName:domain TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:netStack encryptType:encryptType returnIps:^() {
            __strong __typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf uploadReport:NO Domain:domain NetStack:netStack];
                [strongSelf dnsHasDone:dnsService];
            }
            dispatch_semaphore_signal(sema);
        }];
    });
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, timeOut * NSEC_PER_SEC));
    cacheDomainDict = nil;
    dispatch_sync([MSDKDnsInfoTool msdkdns_queue], ^{
        if (domain && _domainDict) {
            cacheDomainDict = [[NSDictionary alloc] initWithDictionary:_domainDict];
        }
    });
    NSArray * result = [self resultArray:domain DomainDic:cacheDomainDict];
    return result;
}

- (void) getHostByName:(NSString *)domain returnIps:(void (^)(NSArray *))handler {
    // 获取当前ipv4/ipv6/双栈网络环境
    msdkdns::MSDKDNS_TLocalIPStack netStack = msdkdns::msdkdns_detect_local_ip_stack();
    __block float timeOut = 2.0;
    __block NSDictionary * cacheDomainDict = nil;
    dispatch_sync([MSDKDnsInfoTool msdkdns_queue], ^{
        if (domain && _domainDict) {
            cacheDomainDict = [[NSDictionary alloc] initWithDictionary:_domainDict];
        }
        timeOut = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMTimeOut];
    });
    //查找缓存，缓存中有HttpDns数据且ttl为超时则直接返回结果,不存在或者ttl超时则重新查询
    if (cacheDomainDict) {
        NSDictionary * domainInfo = cacheDomainDict[domain];
        if (domainInfo && [domainInfo isKindOfClass:[NSDictionary class]]) {
            NSDictionary * cacheDict = domainInfo[kMSDKHttpDnsCache_A];
            if (!cacheDict || ![cacheDict isKindOfClass:[NSDictionary class]]) {
                cacheDict = domainInfo[kMSDKHttpDnsCache_4A];
            }
            if (cacheDict && [cacheDict isKindOfClass:[NSDictionary class]]) {
                NSString * ttlExpried = cacheDict[kTTLExpired];
                double timeInterval = [[NSDate date] timeIntervalSince1970];
                if (timeInterval <= ttlExpried.doubleValue) {
                    MSDKDNSLOG(@"TTL has not expiried,return result from cache directly!");
                    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
                        [self uploadReport:YES Domain:domain NetStack:netStack];
                    });
                    NSArray * result = [self resultArray:domain DomainDic:cacheDomainDict];
                    if (handler) {
                        handler(result);
                    }
                    return;
                }
            }
        }
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
        [dnsService getHostByName:domain TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:netStack encryptType:encryptType returnIps:^() {
            __strong __typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf uploadReport:NO Domain:domain NetStack:netStack];
                [strongSelf dnsHasDone:dnsService];
                NSArray * result = [strongSelf resultArray:domain DomainDic:_domainDict];
                if (handler) {
                    handler(result);
                }
            }
        }];
    });
}

- (void)getHostsByNames:(NSArray *)domains returnIps:(void (^)(NSDictionary * ipsDict))handler {
    // 获取当前ipv4/ipv6/双栈网络环境
    msdkdns::MSDKDNS_TLocalIPStack netStack = msdkdns::msdkdns_detect_local_ip_stack();
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
        if (![self domianCached:domain]) {
            [toCheckDomains addObject:domain];
        } else {
            MSDKDNSLOG(@"TTL has not expiried,return result from cache directly!");
            dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
                [self uploadReport:YES Domain:domain NetStack:netStack];
            });
        }
    }
    // 全部有缓存时，直接返回
    if([toCheckDomains count] == 0) {
        NSDictionary * result = [self resultDictionary:domains DomainDic:_domainDict];
        if (handler) {
            handler(result);
        }
        return;
    }
    NSString *toCheckDomainStr = [toCheckDomains componentsJoinedByString:@","];
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
                [strongSelf uploadReport:NO Domain:toCheckDomainStr NetStack:netStack];
                [strongSelf dnsHasDone:dnsService];
                NSDictionary * result = [strongSelf resultDictionary:domains DomainDic:_domainDict];
                if (handler) {
                    handler(result);
                }
            }
        }];
    });
}

- (NSDictionary *)getHostsByNames:(NSArray *)domains {
    // 获取当前ipv4/ipv6/双栈网络环境
    msdkdns::MSDKDNS_TLocalIPStack netStack = msdkdns::msdkdns_detect_local_ip_stack();
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
        if (![self domianCached:domain]) {
            [toCheckDomains addObject:domain];
        } else {
            MSDKDNSLOG(@"TTL has not expiried,return result from cache directly!");
            dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
                [self uploadReport:YES Domain:domain NetStack:netStack];
            });
        }
    }
    // 全部有缓存时，直接返回
    if([toCheckDomains count] == 0) {
        NSDictionary * result = [self resultDictionary:domains DomainDic:_domainDict];
        return result;
    }
    NSString *toCheckDomainStr = [toCheckDomains componentsJoinedByString:@","];
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
        [dnsService getHostsByNames:toCheckDomains TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:netStack encryptType:encryptType returnIps:^() {
            __strong __typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf uploadReport:NO Domain:toCheckDomainStr NetStack:netStack];
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
    NSDictionary * result = [self resultDictionary:domains DomainDic:cacheDomainDict];
    return result;
}

- (NSArray *)resultArray: (NSString *)domain DomainDic:(NSDictionary *)domainDict {
    NSMutableArray * ipResult = [@[@"0", @"0", @0] mutableCopy];
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
                    [ipResult addObject:@0];
                }
            }
            if (hresultDict_A && [hresultDict_A isKindOfClass:[NSDictionary class]]) {
                NSArray * ipsArray = hresultDict_A[kIP];
                if (ipsArray && [ipsArray isKindOfClass:[NSArray class]] && ipsArray.count > 0) {
                    ipResult[0] = ipsArray[0];
                    ipResult[2] = @1;
                }
            }
            if (hresultDict_4A && [hresultDict_4A isKindOfClass:[NSDictionary class]]) {
                NSArray * ipsArray = hresultDict_4A[kIP];
                if (ipsArray && [ipsArray isKindOfClass:[NSArray class]] && ipsArray.count > 0) {
                    ipResult[1] = ipsArray[0];
                    ipResult[2] = @1;
                }
            }
        }
    }
    return ipResult;
}

- (NSDictionary *)resultDictionary: (NSArray *)domains DomainDic:(NSDictionary *)domainDict {
    NSMutableDictionary *resultDict = [NSMutableDictionary dictionary];
    for (int i = 0; i < [domains count]; i++) {
        NSString *domain = [domains objectAtIndex:i];
        NSArray *resultArray = [self resultArray:domain DomainDic:domainDict];
        [resultDict setObject:resultArray forKey:domain];
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

#pragma mark - uploadReport
- (void)uploadReport:(BOOL)isFromCache Domain:(NSString *)domain NetStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack {
    Class eventClass = NSClassFromString(@"BeaconEvent");
    if (eventClass == 0x0) {
        MSDKDNSLOG(@"Beacon framework is not imported");
        return;
    }
    if (self.beaconInstance) {
        id tmp = [MSDKDnsManager reflectInvocation:eventClass selector:NSSelectorFromString(@"alloc") params:nil];
        NSMutableDictionary *params = [self formatParams:isFromCache Domain:domain NetStack:netStack];
        NSString *eventName = MSDKDnsEventName;
        id event = [MSDKDnsManager reflectInvocation:tmp selector:NSSelectorFromString(@"initWithAppKey:code:type:success:params:") params:@[
            BeaconAppkey,
            eventName,
            @0, // 0 BeaconEventTypeNormal 普通事件
            @YES,
            params
        ]];
        [MSDKDnsManager reflectInvocation:self.beaconInstance selector:NSSelectorFromString(@"reportEvent:") params:@[event]];
        MSDKDNSLOG(@"ReportingEvent, name:%@, events:%@", eventName, params);
    }
}

// 上报内容：clientIP、运营商、地域、何时从何IP切换到了哪个IP，
- (void)uploadDnsError {
    Class eventClass = NSClassFromString(@"BeaconEvent");
    if (eventClass == 0x0) {
        MSDKDNSLOG(@"Beacon framework is not imported");
        return;
    }
    if (self.beaconInstance) {
        id tmp = [MSDKDnsManager reflectInvocation:eventClass selector:NSSelectorFromString(@"alloc") params:nil];
        NSString *errorName = @"HDNSRequestFail";
        int dnsID = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsId];
        NSString * networkType = [[MSDKDnsNetworkManager shareInstance] networkType];
        NSString * serverIps = [[[MSDKDnsParamsManager shareInstance] msdkDnsGetServerIps] componentsJoinedByString:@","];
        NSDictionary *params = @{
            kMSDKDnsID: [NSNumber numberWithInt:dnsID], // 授权ID
            kMSDKDnsSDK_Version: MSDKDns_Version,
            kMSDKDnsNetType:networkType, // 网络类型,
            @"serverIps": serverIps, // 主备ip
            @"failIndex": [[MSDKDnsParamsManager shareInstance] msdkDnsGetServerIndex], //哪个IP解析失败了
        };
        id event = [MSDKDnsManager reflectInvocation:tmp selector:NSSelectorFromString(@"initWithAppKey:code:type:success:params:") params:@[
            BeaconAppkey,
            errorName,
            @1, // 1 BeaconEventTypeRealTime 实时事件
            @YES,
            params
        ]];
        [MSDKDnsManager reflectInvocation:self.beaconInstance selector:NSSelectorFromString(@"reportEvent:") params:@[event]];
        MSDKDNSLOG(@"ReportingError, name:%@, events:%@", errorName, params);
    }
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
    NSString * httpDnsErrMsg_A = @"";
    NSString * httpDnsErrMsg_4A = @"";
    NSString * httpDnsRetry_A = @"";
    NSString * httpDnsRetry_4A = @"";
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
    
    //ErrMsg
    [params setValue:httpDnsErrMsg_A forKey:kMSDKDns_A_ErrMsg];
    [params setValue:httpDnsErrMsg_4A forKey:kMSDKDns_4A_ErrMsg];
    
    //Retry
    [params setValue:httpDnsRetry_A forKey:kMSDKDns_A_Retry];
    [params setValue:httpDnsRetry_4A forKey:kMSDKDns_4A_Retry];
    
    //dns
    [params setValue:dns_A forKey:kMSDKDns_DNS_A_IP];
    [params setValue:dns_4A forKey:kMSDKDns_DNS_4A_IP];

    return params;
}

#pragma mark - getIPsStringFromIPsArray
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

# pragma mark - getCacheData
// 检查是否存在有效缓冲
- (BOOL) domianCached:(NSString *)domain {
    NSDictionary * domainInfo = _domainDict[domain];
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

@end
