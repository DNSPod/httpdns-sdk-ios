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
#import "MSDKDnsParamsManager.h"
#import "AttaReport.h"

@interface MSDKDnsService () <MSDKDnsResolverDelegate>

@property (strong, nonatomic) NSArray * toCheckDomains;
@property (strong, nonatomic) HttpsDnsResolver * httpDnsResolver_A;
@property (strong, nonatomic) HttpsDnsResolver * httpDnsResolver_4A;
@property (strong, nonatomic) HttpsDnsResolver * httpDnsResolver_BOTH;
@property (strong, nonatomic) LocalDnsResolver * localDnsResolver;
@property (nonatomic, strong) void (^ completionHandler)();
@property (atomic, assign) BOOL isCallBack;
@property (nonatomic) msdkdns::MSDKDNS_TLocalIPStack netStack;
@property (nonatomic, assign) int httpdnsFailCount;
@property (nonatomic, assign) float timeOut;
@property (nonatomic, assign) int dnsId;
@property (nonatomic, strong) NSString* dnsKey;
@property (nonatomic, assign) NSUInteger encryptType;
@end

@implementation MSDKDnsService

- (void)dealloc {
    [self setToCheckDomains:nil];
    [self setHttpDnsResolver_A:nil];
    [self setHttpDnsResolver_4A:nil];
    [self setLocalDnsResolver:nil];
    [self setCompletionHandler:nil];
}


- (void)getHostByName:(NSString *)domain TimeOut:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey NetStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack encryptType:(NSInteger)encryptType returnIps:(void (^)())handler
{
    [self getHostsByNames:@[domain] TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:netStack encryptType:encryptType returnIps:handler];
}

- (void)getHostsByNames:(NSArray *)domains TimeOut:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey NetStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack encryptType:(NSInteger)encryptType returnIps:(void (^)())handler
{
    self.completionHandler = handler;
    self.toCheckDomains = domains;
    self.isCallBack = NO;
    self.netStack = netStack;
    [self startCheck:timeOut DnsId:dnsId DnsKey:dnsKey encryptType:encryptType];
}

#pragma mark - startCheck

- (void)startCheck:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey encryptType:(NSInteger)encryptType
{
    MSDKDNSLOG(@"%@, MSDKDns startCheck", self.toCheckDomains);
    //?????????????????????
    [[MSDKDnsManager shareInstance] clearCacheForDomains:self.toCheckDomains];
    
    //?????????????????????
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
    
    self.timeOut = timeOut;
    self.dnsId = dnsId;
    self.dnsKey = dnsKey;
    self.encryptType = encryptType;
    
    if (_netStack == msdkdns::MSDKDNS_ELocalIPStack_IPv6) {
        dispatch_async([MSDKDnsInfoTool msdkdns_resolver_queue], ^{
            [self startHttpDns_4A:timeOut DnsId:dnsId DnsKey:dnsKey encryptType:encryptType];
        });
    }
    
    if (_netStack == msdkdns::MSDKDNS_ELocalIPStack_IPv4) {
        dispatch_async([MSDKDnsInfoTool msdkdns_resolver_queue], ^{
            [self startHttpDns:timeOut DnsId:dnsId DnsKey:dnsKey encryptType:encryptType];
        });
    }
    
    if (_netStack == msdkdns::MSDKDNS_ELocalIPStack_Dual) {
        dispatch_async([MSDKDnsInfoTool msdkdns_resolver_queue], ^{
            [self startHttpDnsBoth:timeOut DnsId:dnsId DnsKey:dnsKey encryptType:encryptType];
        });
    }
    
    BOOL httpOnly = [[MSDKDnsParamsManager shareInstance] msdkDnsGetHttpOnly];
    if (!httpOnly) {
        dispatch_async([MSDKDnsInfoTool msdkdns_resolver_queue], ^{
            [self startLocalDns:timeOut DnsId:dnsId DnsKey:dnsKey];
        });
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, timeOut * NSEC_PER_SEC), [MSDKDnsInfoTool msdkdns_queue], ^{
        if(!self.isCallBack) {
            MSDKDNSLOG(@"DnsService TimeOut!");
            [self callNotify];
        }
    });
}

//??????httpdns ipv4???ipv6????????????
- (void)startHttpDnsBoth:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey encryptType:(NSInteger)encryptType
{
    MSDKDNSLOG(@"%@ StartHttpDns!", self.toCheckDomains);
    self.httpDnsResolver_BOTH = [[HttpsDnsResolver alloc] init];
    self.httpDnsResolver_BOTH.delegate = self;
    [self.httpDnsResolver_BOTH startWithDomains:self.toCheckDomains TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:msdkdns::MSDKDNS_ELocalIPStack_Dual encryptType:encryptType];
}

//??????httpdns ipv4??????
- (void)startHttpDns:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey encryptType:(NSInteger)encryptType
{
    MSDKDNSLOG(@"%@ StartHttpDns!", self.toCheckDomains);
    self.httpDnsResolver_A = [[HttpsDnsResolver alloc] init];
    self.httpDnsResolver_A.delegate = self;
    [self.httpDnsResolver_A startWithDomains:self.toCheckDomains TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:msdkdns::MSDKDNS_ELocalIPStack_IPv4 encryptType:encryptType];
}

//??????httpdns ipv6??????
- (void)startHttpDns_4A:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey encryptType:(NSInteger)encryptType
{
    MSDKDNSLOG(@"%@ StartHttpDns!", self.toCheckDomains);
    self.httpDnsResolver_4A = [[HttpsDnsResolver alloc] init];
    self.httpDnsResolver_4A.delegate = self;
    [self.httpDnsResolver_4A startWithDomains:self.toCheckDomains TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:msdkdns::MSDKDNS_ELocalIPStack_IPv6 encryptType:encryptType];
}

//??????localdns??????
- (void)startLocalDns:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey {
    MSDKDNSLOG(@"%@ startLocalDns!", self.toCheckDomains);
    self.localDnsResolver = [[LocalDnsResolver alloc] init];
    self.localDnsResolver.delegate = self;
    [self.localDnsResolver startWithDomains:self.toCheckDomains TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:_netStack];
}

#pragma mark - MSDKDnsResolverDelegate

- (void)resolver:(MSDKDnsResolver *)resolver didGetDomainInfo:(NSDictionary *)domainInfo {
    MSDKDNSLOG(@"%@ %@ domainInfo = %@", self.toCheckDomains, [resolver class], domainInfo);
    // ???????????????
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        [self cacheDomainInfo:resolver];
        NSDictionary * info = @{kDnsErrCode:MSDKDns_Success, kDnsErrMsg:@"", kDnsRetry:@"0"};
        [self callBack:resolver Info:info];
        if (resolver == self.httpDnsResolver_A || resolver == self.httpDnsResolver_4A || resolver == self.httpDnsResolver_BOTH) {
            NSArray *keepAliveDomains = [[MSDKDnsParamsManager shareInstance] msdkDnsGetKeepAliveDomains];
            // ????????????????????????
            NSMutableDictionary *domainISOpenDelayDispatch = [[MSDKDnsManager shareInstance] msdkDnsGetDomainISOpenDelayDispatch];
            [domainInfo enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull domain, id  _Nonnull obj, BOOL * _Nonnull stop) {
                // NSLog(@"domain = %@", domain);
                // NSLog(@"domainInfo = %@", domainInfo);
                
                // ???????????????????????????????????????????????????????????????????????????????????????????????????????????????
                if (keepAliveDomains && domain && [keepAliveDomains containsObject:domain]) {

                    NSMutableString * afterTime = [[NSMutableString alloc] init];
                    
                    if(resolver == self.httpDnsResolver_BOTH){
                        NSDictionary *domainResult = domainInfo[domain];
                        if (domainResult) {
                            NSDictionary *ipv4Value = [domainResult objectForKey:@"ipv4"];
                            NSDictionary *ipv6Value = [domainResult objectForKey:@"ipv6"];
                            if (ipv6Value) {
                                NSString *ttl = [ipv6Value objectForKey:kTTL];
                                afterTime = [[NSMutableString alloc]initWithString:ttl];
                            }
                            if (ipv4Value) {
                                NSString *ttl = [ipv4Value objectForKey:kTTL];
                                afterTime = [[NSMutableString alloc]initWithString:ttl];
                            }
                        }
                    }else{
                        NSDictionary *domainResult = domainInfo[domain];
                        if (domainResult) {
                            NSString *ttl = [domainResult objectForKey:kTTL];
                            afterTime = [[NSMutableString alloc]initWithString:ttl];
                        }
                    }
                    
                    //  NSLog(@"4444444????????????????????????????????????%f????????????!???????????????%@",afterTime.floatValue,domain);
                    if (!domainISOpenDelayDispatch[domain] && afterTime) {
                        // ???????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
                        [[MSDKDnsManager shareInstance] msdkDnsAddDomainOpenDelayDispatch:domain];
                        MSDKDNSLOG(@"Start the delayed execution task, it is expected to start requesting the domain name %@ after %f seconds", domain, afterTime.floatValue);
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,afterTime.floatValue* NSEC_PER_SEC), [MSDKDnsInfoTool msdkdns_queue], ^{
                            //  NSLog(@"????????????????????????!???????????????%@",domain);
                            MSDKDNSLOG(@"The cache update request start! request domain:%@",domain);
                            [[MSDKDnsManager shareInstance] refreshCacheDelay:@[domain] clearDispatchTag:YES];
                        });
                    }
                    
                }
            }];
        }
    });
    // ?????????????????????????????????????????????
    if (resolver == self.httpDnsResolver_A || resolver == self.httpDnsResolver_4A || resolver == self.httpDnsResolver_BOTH) {
        if ([[MSDKDnsParamsManager shareInstance] msdkDnsGetEnableReport] && [[AttaReport sharedInstance] shoulReportDnsSpend]) {
            NSDictionary *domainDic = [domainInfo objectForKey:[self.toCheckDomains firstObject]];
            NSString* routeip = [[MSDKDnsParamsManager shareInstance] msdkDnsGetRouteIp];
            if (!routeip) {
                routeip = @"";
            }
            HttpsDnsResolver *httpResolver = (HttpsDnsResolver *)resolver;
            [[AttaReport sharedInstance] reportEvent:@{
                @"eventName": MSDKDnsEventHttpDnsSpend,
                @"dnsIp": [[MSDKDnsManager shareInstance] currentDnsServer],
                @"req_dn": [self.toCheckDomains componentsJoinedByString:@","],
                @"req_type": resolver == self.httpDnsResolver_4A ? @"aaaa" : @"a",
                @"req_timeout": @(self.timeOut * 1000),
                @"req_ttl": @1,
                @"req_query": @1,
                @"req_ip": routeip,
                @"spend": [domainDic objectForKey:kDnsTimeConsuming],
                @"statusCode": @(httpResolver.statusCode),
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
            NSDictionary * info = @{kDnsErrCode:MSDKDns_Fail, kDnsErrMsg:@"", kDnsRetry:@"0"};
            [self callBack:resolver Info:info];
        });
    }
    
}

#pragma mark - retry
- (void) retryHttpDns:(MSDKDnsResolver *)resolver {
    self.httpdnsFailCount += 1;
    if (self.httpdnsFailCount < [[MSDKDnsParamsManager shareInstance] msdkDnsGetRetryTimesBeforeSwitchServer]) {
        if (resolver == self.httpDnsResolver_A) {
            dispatch_async([MSDKDnsInfoTool msdkdns_retry_queue], ^{
                [self startHttpDns:self.timeOut DnsId:self.dnsId DnsKey:self.dnsKey encryptType:self.encryptType];
            });
        } else if (resolver == self.httpDnsResolver_4A) {
            dispatch_async([MSDKDnsInfoTool msdkdns_retry_queue], ^{
                [self startHttpDns_4A:self.timeOut DnsId:self.dnsId DnsKey:self.dnsKey encryptType:self.encryptType];
            });
        } else if (resolver == self.httpDnsResolver_BOTH) {
            dispatch_async([MSDKDnsInfoTool msdkdns_retry_queue], ^{
                [self startHttpDnsBoth:self.timeOut DnsId:self.dnsId DnsKey:self.dnsKey encryptType:self.encryptType];
            });
        }
    } else {
        MSDKDNSLOG(@"fail %lu times, switch server!", (unsigned long)[[MSDKDnsParamsManager shareInstance] msdkDnsGetRetryTimesBeforeSwitchServer]);
        // ??????????????????????????????????????????????????????ip
        dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
            NSDictionary * info = @{kDnsErrCode:MSDKDns_Fail, kDnsErrMsg:@"", kDnsRetry:@"0"};
            [self callBack:resolver Info:info];
        });
        if ([[MSDKDnsParamsManager shareInstance] msdkDnsGetEnableReport]) {
            NSString* routeip = [[MSDKDnsParamsManager shareInstance] msdkDnsGetRouteIp];
            if (!routeip) {
                routeip = @"";
            }
            HttpsDnsResolver *httpResolver = (HttpsDnsResolver *)resolver;
            [[AttaReport sharedInstance] reportEvent:@{
                @"eventName": MSDKDnsEventHttpDnsfail,
                @"dnsIp": [[MSDKDnsManager shareInstance] currentDnsServer],
                @"req_dn": [self.toCheckDomains componentsJoinedByString:@","],
                @"req_type": resolver == self.httpDnsResolver_4A ? @"aaaa" : @"a",
                @"req_timeout": @(self.timeOut * 1000),
                @"req_ttl": @1,
                @"req_query": @1,
                @"req_ip": routeip,
                @"statusCode": @(httpResolver.statusCode),
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
    
    // ??????????????????????????????
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
            
        } else if (resolver && (resolver == self.httpDnsResolver_BOTH)) {
            
            [cacheDict setObject:info forKey:kMSDKHttpDnsInfo_BOTH];
            
        }
        
        if (cacheDict && domain) {
            [[MSDKDnsManager shareInstance] cacheDomainInfo:cacheDict Domain:domain];
        }
    }
    
    MSDKDNSLOG(@"callBack! :%@", self.toCheckDomains);
    BOOL httpOnly = [[MSDKDnsParamsManager shareInstance] msdkDnsGetHttpOnly];
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
    } else if (self.httpDnsResolver_BOTH) {
        if (self.httpDnsResolver_BOTH.isFinished) {
            [self callNotify];
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

// ?????????????????????
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
        
        if (resolver && (resolver == self.httpDnsResolver_A) && self.httpDnsResolver_A.domainInfo) {
            
            NSDictionary *cacheValue = [self.httpDnsResolver_A.domainInfo objectForKey:domain];
            if (cacheValue) {
                [cacheDict setObject:cacheValue forKey:kMSDKHttpDnsCache_A];
            }
            
        } else if (resolver && (resolver == self.httpDnsResolver_4A) && self.httpDnsResolver_4A.domainInfo) {
            
            NSDictionary *cacheValue = [self.httpDnsResolver_4A.domainInfo objectForKey:domain];
            if (cacheValue) {
                [cacheDict setObject:cacheValue forKey:kMSDKHttpDnsCache_4A];
            }
            
        } else if (resolver && (resolver == self.localDnsResolver) && self.localDnsResolver.domainInfo) {
            
            NSDictionary *cacheValue = [self.localDnsResolver.domainInfo objectForKey:domain];
            if (cacheValue) {
                [cacheDict setObject:cacheValue forKey:kMSDKLocalDnsCache];
            }
        } else if (resolver && (resolver == self.httpDnsResolver_BOTH) && self.httpDnsResolver_BOTH.domainInfo) {
            NSDictionary *cacheValue = [self.httpDnsResolver_BOTH.domainInfo objectForKey:domain];
            if (cacheValue) {
                NSDictionary *ipv4CacheValue = [cacheValue objectForKey:@"ipv4"];
                NSDictionary *ipv6CacheValue = [cacheValue objectForKey:@"ipv6"];
                if (ipv4CacheValue) {
                    [cacheDict setObject:ipv4CacheValue forKey:kMSDKHttpDnsCache_A];
                }
                if (ipv6CacheValue) {
                    [cacheDict setObject:ipv6CacheValue forKey:kMSDKHttpDnsCache_4A];
                }
            }
        }
        
        if (cacheDict && domain) {
            [[MSDKDnsManager shareInstance] cacheDomainInfo:cacheDict Domain:domain];
        }
    }
}

@end
