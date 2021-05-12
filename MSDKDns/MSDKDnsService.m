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

@interface MSDKDnsService () <MSDKDnsResolverDelegate>

@property (strong, nonatomic) NSArray * toCheckDomains;
@property (strong, nonatomic) HttpsDnsResolver * httpDnsResolver_A;
@property (strong, nonatomic) HttpsDnsResolver * httpDnsResolver_4A;
@property (strong, nonatomic) LocalDnsResolver * localDnsResolver;
@property (nonatomic, strong) void (^ completionHandler)();
@property (atomic, assign) BOOL isCallBack;
@property (nonatomic) msdkdns::MSDKDNS_TLocalIPStack netStack;

@end

@implementation MSDKDnsService

- (void)dealloc {
    [self setToCheckDomains:nil];
    [self setHttpDnsResolver_A:nil];
    [self setHttpDnsResolver_4A:nil];
    [self setLocalDnsResolver:nil];
    [self setCompletionHandler:nil];
}

- (void)getHostByName:(NSString *)domain TimeOut:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey NetStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack returnIps:(void (^)())handler
{
    [self getHostByName:domain TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:netStack encryptType:0 returnIps:handler];
}

- (void)getHostByName:(NSString *)domain TimeOut:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey NetStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack encryptType:(NSInteger)encryptType returnIps:(void (^)())handler
{
    self.completionHandler = handler;
    self.toCheckDomains = @[domain];
    self.isCallBack = NO;
    self.netStack = netStack;
    [self startCheck:timeOut DnsId:dnsId DnsKey:dnsKey encryptType:encryptType];
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

- (void)startCheck:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey
{
    [self startCheck:timeOut DnsId:dnsId DnsKey:dnsKey encryptType:0];
}

- (void)startCheck:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey encryptType:(NSInteger)encryptType
{
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
            [self startHttpDns_4A:timeOut DnsId:dnsId DnsKey:dnsKey encryptType:encryptType];
        });
    }
    
    if (_netStack != msdkdns::MSDKDNS_ELocalIPStack_IPv6) {
        dispatch_async([MSDKDnsInfoTool msdkdns_resolver_queue], ^{
            [self startHttpDns:timeOut DnsId:dnsId DnsKey:dnsKey encryptType:encryptType];
        });
    }
    
    dispatch_async([MSDKDnsInfoTool msdkdns_resolver_queue], ^{
        [self startLocalDns:timeOut DnsId:dnsId DnsKey:dnsKey];
    });
}

//进行httpdns请求
- (void)startHttpDns:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey
{
    [self startHttpDns:timeOut DnsId:dnsId DnsKey:dnsKey encryptType:0];
}

- (void)startHttpDns:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey encryptType:(NSInteger)encryptType
{
    MSDKDNSLOG(@"%@ StartHttpDns!", self.toCheckDomains);
    self.httpDnsResolver_A = [[HttpsDnsResolver alloc] init];
    self.httpDnsResolver_A.delegate = self;
    [self.httpDnsResolver_A startWithDomains:self.toCheckDomains TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:msdkdns::MSDKDNS_ELocalIPStack_IPv4 encryptType:encryptType];
}

- (void)startHttpDns_4A:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey
{
    [self startHttpDns_4A:timeOut DnsId:dnsId DnsKey:dnsKey encryptType:0];
}

- (void)startHttpDns_4A:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey encryptType:(NSInteger)encryptType
{
    MSDKDNSLOG(@"%@ StartHttpDns!", self.toCheckDomains);
    self.httpDnsResolver_4A = [[HttpsDnsResolver alloc] init];
    self.httpDnsResolver_4A.delegate = self;
    [self.httpDnsResolver_4A startWithDomains:self.toCheckDomains TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:msdkdns::MSDKDNS_ELocalIPStack_IPv6 encryptType:encryptType];
}

//进行localdns请求
- (void)startLocalDns:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey {
    MSDKDNSLOG(@"%@ startLocalDns!", self.toCheckDomains);
    self.localDnsResolver = [[LocalDnsResolver alloc] init];
    self.localDnsResolver.delegate = self;
    [self.localDnsResolver startWithDomains:self.toCheckDomains TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:_netStack];
}

#pragma mark - MSDKDnsResolverDelegate

- (void)resolver:(MSDKDnsResolver *)resolver didGetDomainInfo:(NSDictionary *)domainInfo {
    MSDKDNSLOG(@"%@ %@ domainInfo = %@", self.toCheckDomains, [resolver class], domainInfo);
    //结果存缓存
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        [self cacheDomainInfo:resolver];
        NSDictionary * info = @{kDnsErrCode:MSDKDns_Success, kDnsErrMsg:@"", kDnsRetry:@"0"};
        [self callBack:resolver Info:info];
    });
}

- (void)resolver:(MSDKDnsResolver *)resolver getDomainError:(NSString *)error {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        MSDKDNSLOG(@"%@ %@ error = %@",self.toCheckDomains, [resolver class], error);
        NSDictionary * info = @{kDnsErrCode:MSDKDns_Fail, kDnsErrMsg:@"", kDnsRetry:@"0"};
        [self callBack:resolver Info:info];
    });
}

#pragma mark - CallBack

- (void)callBack:(MSDKDnsResolver *)resolver Info:(NSDictionary *)info {
    if (self.isCallBack) {
        return;
    }
    
    for(int i = 0; i < [self.toCheckDomains count]; i++) {
        NSString *domain = [self.toCheckDomains objectAtIndex:i];
        //信息存缓存
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
    if (self.localDnsResolver.isFinished) {
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

- (void)cacheDomainInfo:(MSDKDnsResolver *)resolver {
    MSDKDNSLOG(@"cacheDomainInfo: %@", self.toCheckDomains);
    //结果存缓存
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
        }
        
        if (cacheDict && domain) {
            [[MSDKDnsManager shareInstance] cacheDomainInfo:cacheDict Domain:domain];
        }
    }
}

@end
