/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import "MSDKDnsService.h"
#import "HttpsDnsResolver.h"
#import "LocalDnsResolver.h"
#import "MSDKDnsInfoTool.h"
#import "MSDKDnsLog.h"
#import "MSDKDnsManager.h"
#import "MSDKDnsNetworkManager.h"
#import "AttaReport.h"

@interface MSDKDnsService () <MSDKDnsResolverDelegate>

@property (strong, nonatomic) NSArray * toCheckDomains;
@property (strong, nonatomic) HttpsDnsResolver * httpDnsResolver_A;
@property (strong, nonatomic) HttpsDnsResolver * httpDnsResolver_4A;
@property (strong, nonatomic) LocalDnsResolver * localDnsResolver;
@property (nonatomic, strong) void (^ completionHandler)();
@property (atomic, assign) BOOL isCallBack;
@property (nonatomic) msdkdns::MSDKDNS_TLocalIPStack netStack;
@property (nonatomic, assign) int httpdnsFailCount;
@property (nonatomic, assign) float timeOut;
@property (nonatomic, assign) int dnsId;
@property (nonatomic, strong) NSString* dnsServer;
@property (nonatomic, strong) NSString* dnsRouter;
@property (nonatomic, strong) NSString* dnsKey;
@property (nonatomic, strong) NSString* dnsToken;
@property (nonatomic, assign) NSUInteger encryptType;
@property (nonatomic, assign) BOOL httpOnly;
@property (nonatomic, assign) BOOL enableReport;
@property (nonatomic, assign) NSUInteger retryCount;
@end

@implementation MSDKDnsService

- (void)dealloc {
    [self setToCheckDomains:nil];
    [self setHttpDnsResolver_A:nil];
    [self setHttpDnsResolver_4A:nil];
    [self setLocalDnsResolver:nil];
    [self setCompletionHandler:nil];
}

- (void)getHostsByNames:(NSArray *)domains
                TimeOut:(float)timeOut
                  DnsId:(int)dnsId
              DnsServer:(NSString *)dnsServer
              DnsRouter:(NSString *)dnsRouter
                 DnsKey:(NSString *)dnsKey
               DnsToken:(NSString *)dnsToken
               NetStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack
            encryptType:(NSInteger)encryptType
               httpOnly:(BOOL)httpOnly
           enableReport:(BOOL)enableReport
             retryCount:(NSUInteger)retryCount
              returnIps:(void (^)())handler
{
    self.completionHandler = handler;
    self.toCheckDomains = domains;
    self.isCallBack = NO;
    self.netStack = netStack;
    self.timeOut = timeOut;
    self.dnsId = dnsId;
    self.dnsServer = dnsServer;
    self.dnsRouter = dnsRouter;
    self.dnsKey = dnsKey;
    self.dnsToken = dnsToken;
    self.encryptType = encryptType;
    self.httpOnly = httpOnly;
    self.enableReport = enableReport;
    self.retryCount = retryCount;
    self.httpdnsFailCount = 0;
    [self startCheck];
}

#pragma mark - startCheck

- (void)startCheck {
    MSDKDNSLOG(@"%@, MSDKDns startCheck", self.toCheckDomains);
    //查询前清除缓存
    [[MSDKDnsManager shareInstance] clearCacheForDomains:self.toCheckDomains];
    
    //无网络直接返回
    if (![[MSDKDnsNetworkManager shareInstance] networkAvailable]) {
        MSDKDNSLOG(@"No network,please check your network setting!");
        [self callNotify];
        return;
    }

    if (_netStack == msdkdns::MSDKDNS_ELocalIPStack_None) {
        MSDKDNSLOG(@"No network stack, please check your network setting!");
        [self callNotify];
        return;
    }
    
    
    if (_netStack != msdkdns::MSDKDNS_ELocalIPStack_IPv4) {
        dispatch_async([MSDKDnsInfoTool msdkdns_resolver_queue], ^{
            [self startHttpDns_4A:_timeOut
                            DnsId:_dnsId
                        DnsServer:_dnsServer
                        DnsRouter:_dnsRouter
                           DnsKey:_dnsKey
                         DnsToken:_dnsToken
                      encryptType:_encryptType];
        });
    }
    
    if (_netStack != msdkdns::MSDKDNS_ELocalIPStack_IPv6) {
        dispatch_async([MSDKDnsInfoTool msdkdns_resolver_queue], ^{
            [self startHttpDns:_timeOut
                            DnsId:_dnsId
                        DnsServer:_dnsServer
                        DnsRouter:_dnsRouter
                           DnsKey:_dnsKey
                         DnsToken:_dnsToken
                      encryptType:_encryptType];
        });
    }
    
    if (!_httpOnly) {
        dispatch_async([MSDKDnsInfoTool msdkdns_resolver_queue], ^{
            [self startLocalDns:_timeOut DnsId:_dnsId DnsKey:_dnsKey];
        });
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, _timeOut * NSEC_PER_SEC), [MSDKDnsInfoTool msdkdns_queue], ^{
        if(!self.isCallBack) {
            MSDKDNSLOG(@"DnsService TimeOut!");
            [self callNotify];
        }
    });
}

//进行httpdns请求
- (void)startHttpDns:(float)timeOut
               DnsId:(int)dnsId
           DnsServer:(NSString *)dnsServer
           DnsRouter:(NSString *)dnsRouter
              DnsKey:(NSString *)dnsKey
            DnsToken:(NSString *)dnsToken
         encryptType:(NSInteger)encryptType
{
    MSDKDNSLOG(@"%@ StartHttpDns!", self.toCheckDomains);
    self.httpDnsResolver_A = [[HttpsDnsResolver alloc] init];
    self.httpDnsResolver_A.delegate = self;
    [self.httpDnsResolver_A startWithDomains:self.toCheckDomains
                                     TimeOut:timeOut
                                       DnsId:dnsId
                                   DnsServer:dnsServer
                                   DnsRouter:dnsRouter
                                      DnsKey:dnsKey
                                    DnsToken:dnsToken
                                    NetStack:msdkdns::MSDKDNS_ELocalIPStack_IPv4
                                 encryptType:encryptType];
}


- (void)startHttpDns_4A:(float)timeOut
                  DnsId:(int)dnsId
              DnsServer:(NSString *)dnsServer
              DnsRouter:(NSString *)dnsRouter
                 DnsKey:(NSString *)dnsKey
               DnsToken:(NSString *)dnsToken
            encryptType:(NSInteger)encryptType
{
    MSDKDNSLOG(@"%@ StartHttpDns!", self.toCheckDomains);
    self.httpDnsResolver_4A = [[HttpsDnsResolver alloc] init];
    self.httpDnsResolver_4A.delegate = self;
    [self.httpDnsResolver_4A startWithDomains:self.toCheckDomains
                                     TimeOut:timeOut
                                       DnsId:dnsId
                                   DnsServer:dnsServer
                                   DnsRouter:dnsRouter
                                      DnsKey:dnsKey
                                    DnsToken:dnsToken
                                    NetStack:msdkdns::MSDKDNS_ELocalIPStack_IPv6
                                 encryptType:encryptType];
}

//进行localdns请求
- (void)startLocalDns:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey {
    MSDKDNSLOG(@"%@ startLocalDns!", self.toCheckDomains);
    self.localDnsResolver = [[LocalDnsResolver alloc] init];
    self.localDnsResolver.delegate = self;
    [self.localDnsResolver startWithDomains:self.toCheckDomains
                                    TimeOut:timeOut
                                      DnsId:0
                                  DnsServer:nil
                                  DnsRouter:nil
                                     DnsKey:nil
                                   DnsToken:nil
                                   NetStack:_netStack
                                encryptType:_encryptType];
}

#pragma mark - MSDKDnsResolverDelegate

- (void)resolver:(MSDKDnsResolver *)resolver didGetDomainInfo:(NSDictionary *)domainInfo {
    MSDKDNSLOG(@"%@ %@ domainInfo = %@", self.toCheckDomains, [resolver class], domainInfo);
    // 结果存缓存
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        [self cacheDomainInfo:resolver];
        NSDictionary * info = @{
            kDnsErrCode:MSDKDns_Success,
            kDnsErrMsg:@"",
            kDnsRetry: @(self.httpdnsFailCount)
        };
        [self callBack:resolver Info:info];
    });
    // 正常解析结果上报，上报解析耗时
    if(resolver == self.httpDnsResolver_A || resolver == self.httpDnsResolver_4A) {
        if (_enableReport && [[AttaReport sharedInstance] shoulReportDnsSpend]) {
            NSDictionary *domainDic = [domainInfo objectForKey:[self.toCheckDomains firstObject]];
            NSString* routeip = _dnsRouter;
            if (!routeip) {
                routeip = @"";
            }
            [[AttaReport sharedInstance] reportEvent:@{
                @"eventName": MSDKDnsEventHttpDnsSpend,
                @"dnsIp": _dnsServer,
                @"req_dn": [self.toCheckDomains componentsJoinedByString:@","],
                @"req_type": resolver == self.httpDnsResolver_4A ? @"aaaa" : @"a",
                @"req_timeout": @(self.timeOut * 1000),
                @"req_ttl": @1,
                @"req_query": @1,
                @"req_ip": routeip,
                @"spend": [domainDic objectForKey:kDnsTimeConsuming],
            }];
        }
    }
}

- (void)resolver:(MSDKDnsResolver *)resolver getDomainError:(NSString *)error retry:(BOOL)retry {
    MSDKDNSLOG(@"%@ %@ error = %@",self.toCheckDomains, [resolver class], error);
    if (retry) {
        [self retryHttpDns:resolver];
    } else {
        dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
            NSDictionary * info = @{
                kDnsErrCode:MSDKDns_Fail,
                kDnsErrMsg:error,
                kDnsRetry:@(self.httpdnsFailCount)
            };
            [self callBack:resolver Info:info];
        });
    }
    
}

#pragma mark - retry
- (void) retryHttpDns:(MSDKDnsResolver *)resolver {
    self.httpdnsFailCount += 1;
    if (self.httpdnsFailCount < _retryCount) {
        if (resolver == self.httpDnsResolver_A) {
            dispatch_async([MSDKDnsInfoTool msdkdns_retry_queue], ^{
                [self startHttpDns:_timeOut
                                DnsId:_dnsId
                            DnsServer:_dnsServer
                            DnsRouter:_dnsRouter
                               DnsKey:_dnsKey
                             DnsToken:_dnsToken
                          encryptType:_encryptType];
            });
        } else if (resolver == self.httpDnsResolver_4A) {
            dispatch_async([MSDKDnsInfoTool msdkdns_retry_queue], ^{
                [self startHttpDns_4A:_timeOut
                                DnsId:_dnsId
                            DnsServer:_dnsServer
                            DnsRouter:_dnsRouter
                               DnsKey:_dnsKey
                             DnsToken:_dnsToken
                          encryptType:_encryptType];
            });
        }
    } else {
        MSDKDNSLOG(@"fail %lu times, switch server!", (unsigned long)_retryCount);
        // 失败超过三次，返回错误结果并切换备份ip
        dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
            NSDictionary * info = @{
                kDnsErrCode:MSDKDns_Fail,
                kDnsErrMsg:[NSString stringWithFormat:@"request fail %lu times", (unsigned long)_retryCount],
                kDnsRetry:@(self.httpdnsFailCount)
            };
            [self callBack:resolver Info:info];
        });
        if (_enableReport) {
            NSString* routeip = _dnsRouter;
            if (!routeip) {
                routeip = @"";
            }
            [[AttaReport sharedInstance] reportEvent:@{
                @"eventName": MSDKDnsEventHttpDnsfail,
                @"dnsIp": _dnsServer,
                @"req_dn": [self.toCheckDomains componentsJoinedByString:@","],
                @"req_type": resolver == self.httpDnsResolver_4A ? @"aaaa" : @"a",
                @"req_timeout": @(self.timeOut * 1000),
                @"req_ttl": @1,
                @"req_query": @1,
                @"req_ip": routeip,
            }];
        }
        [[MSDKDnsManager shareInstance] switchDnsServer];
    }
}

#pragma mark - CallBack

- (void)callBack:(MSDKDnsResolver *)resolver Info:(NSDictionary *)info {
    if (self.isCallBack) {
        return;
    }
    
    // 解析请求返回状态缓存
    for(int i = 0; i < [self.toCheckDomains count]; i++) {
        NSString *domain = [self.toCheckDomains objectAtIndex:i];
        NSDictionary * tempDict = [[[MSDKDnsManager shareInstance] domainDict] objectForKey:domain];
        NSMutableDictionary *cacheDict;
        
        if (tempDict) {
            cacheDict = [NSMutableDictionary dictionaryWithDictionary:tempDict];
        } else {
            cacheDict = [[NSMutableDictionary alloc] init];
        }
        
        if (resolver && (resolver == self.httpDnsResolver_A)) {
            
            [cacheDict setObject:info forKey:kMSDKHttpDnsInfo_A];
            
        } else if (resolver && (resolver == self.httpDnsResolver_4A)) {
            
            [cacheDict setObject:info forKey:kMSDKHttpDnsInfo_4A];

        }
        
        if (cacheDict && domain) {
            [[MSDKDnsManager shareInstance] cacheDomainInfo:cacheDict Domain:domain];
        }
    }
    
    MSDKDNSLOG(@"callBack! :%@", self.toCheckDomains);
    //LocalHttp 和 HttpDns均完成，则返回结果
    if (_httpOnly || self.localDnsResolver.isFinished) {
        if (self.httpDnsResolver_A && self.httpDnsResolver_4A) {
            if (self.httpDnsResolver_A.isFinished && self.httpDnsResolver_4A.isFinished) {
                [self callNotify];
            }
        } else if (self.httpDnsResolver_A && !self.httpDnsResolver_4A) {
            if (self.httpDnsResolver_A.isFinished) {
                [self callNotify];
            }
        } else if (!self.httpDnsResolver_A && self.httpDnsResolver_4A) {
            if (self.httpDnsResolver_4A.isFinished) {
                [self callNotify];
            }
        }
    }
}

- (void)callNotify {
    MSDKDNSLOG(@"callNotify! :%@", self.toCheckDomains);
    self.isCallBack = YES;
    if (self.completionHandler) {
        self.completionHandler();
        self.completionHandler = nil;
    }
}

#pragma mark - cacheDomainInfo

// 解析结果存缓存
- (void)cacheDomainInfo:(MSDKDnsResolver *)resolver {
    MSDKDNSLOG(@"cacheDomainInfo: %@", self.toCheckDomains);
    for(int i = 0; i < [self.toCheckDomains count]; i++) {
        NSString *domain = [self.toCheckDomains objectAtIndex:i];
        NSDictionary * tempDict = [[[MSDKDnsManager shareInstance] domainDict] objectForKey:domain];
        NSMutableDictionary *cacheDict;
        
        if (tempDict) {
            cacheDict = [NSMutableDictionary dictionaryWithDictionary:tempDict];
        } else {
            cacheDict = [[NSMutableDictionary alloc] init];
        }
        
        if (resolver && resolver.domainInfo && resolver.cacheKey) {
            NSDictionary *cacheValue = [resolver.domainInfo objectForKey:domain];
            if (cacheValue) {
                [cacheDict setObject:cacheValue forKey:resolver.cacheKey];
            }
        }
        
        if (cacheDict && domain) {
            [[MSDKDnsManager shareInstance] cacheDomainInfo:cacheDict Domain:domain];
        }
    }
}

@end
