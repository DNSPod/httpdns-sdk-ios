/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import "MSDKDns.h"
#import "MSDKDnsService.h"
#import "MSDKDnsLog.h"
#import "MSDKDnsManager.h"
#import "MSDKDnsNetworkManager.h"
#import "MSDKDnsInfoTool.h"
#import "MSDKDnsParamsManager.h"
#if defined(__has_include)
    #if __has_include("httpdnsIps.h")
        #include "httpdnsIps.h"
    #endif
#endif

@interface MSDKDns ()

@end

@implementation MSDKDns

static MSDKDns * gSharedInstance = nil;
static dispatch_once_t onceToken;

#pragma mark - init
+ (instancetype) sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSharedInstance = [[MSDKDns alloc] init];
    });
    return gSharedInstance;
}

- (instancetype) init {
    if (self = [super init]) {
        //开启网络切换，及前后台切换的监听
        [MSDKDnsNetworkManager start];
    }
    return self;
}

- (BOOL) initConfig:(DnsConfig *)config {
#if IS_INTL
    if (config->encryptType == HttpDnsEncryptTypeHTTPS) {
        //国际站SDK不能进行HTTPS解析，直接报错提示用户
        @throw [NSException exceptionWithName:@"MSDKDns wrong use of encryptType"
                                           reason:@"HttpDnsEncryptTypeHTTPS cannot be used because httpdns-sdk-intl version still doesn't support, it is recommended to use HttpDnsEncryptTypeDES or HttpDnsEncryptTypeAES"
                                         userInfo:nil];
        return NO;
    }
#endif
    [[MSDKDnsLog sharedInstance] setEnableLog:config->debug];
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetMAppId:config->appId timeOut:config->timeout encryptType:config->encryptType];
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetMDnsId:config->dnsId dnsKey:config->dnsKey token:config->token];
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetAddressType:config->addressType];
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetRouteIp: config->routeIp];
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetHttpOnly: config->httpOnly];
    if (config->retryTimesBeforeSwitchServer) {
        [[MSDKDnsParamsManager shareInstance] msdkDnsSetRetryTimesBeforeSwitchServer: config->retryTimesBeforeSwitchServer];
    }
    if (config->minutesBeforeSwitchToMain) {
        [[MSDKDnsParamsManager shareInstance] msdkDnsSetMinutesBeforeSwitchToMain:config->minutesBeforeSwitchToMain];
    }
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetEnableReport:config->enableReport];
    [[MSDKDnsManager shareInstance] fetchConfig:config->dnsId encryptType:config->encryptType dnsKey:config->dnsKey token:config->token];
    MSDKDNSLOG(@"MSDKDns init success.");
    
#ifdef httpdnsIps_h
    dispatch_once(&onceToken, ^{
        NSString * componentId = Bugly_APPID;
        NSString * version = MSDKDns_Version;
        if (componentId && version) {
            NSMutableDictionary * dictionary = [NSMutableDictionary dictionary];
            // 读取已有信息并记录
            NSDictionary * dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"BuglySDKInfos"];
            if (dict) {
                [dictionary addEntriesFromDictionary:dict];
            }
            if (config->enableExperimentalBugly) {
                // 添加当前组件的唯⼀标识和版本
                [dictionary setValue:version forKey:componentId];
                // 写⼊更新的信息
                [[NSUserDefaults standardUserDefaults] setObject:[NSDictionary dictionaryWithDictionary:dictionary] forKey:@"BuglySDKInfos"];
            } else {
                if ([dictionary objectForKey:componentId] != nil) {
                    // 删除当前组件的唯⼀标识和版本
                    [dictionary removeObjectForKey:componentId];
                    // 写⼊更新的信息
                    [[NSUserDefaults standardUserDefaults] setObject:[NSDictionary dictionaryWithDictionary:dictionary] forKey:@"BuglySDKInfos"];
                }
            }
        }
    });
#endif
    
    return YES;
}

- (BOOL) initConfigWithDictionary:(NSDictionary *)config {
    DnsConfig *conf = new DnsConfig();
    conf->appId = [config objectForKey:@"appId"];
    conf->debug = [[config objectForKey:@"debug"] boolValue];
    conf->dnsId = [[config objectForKey:@"dnsId"] intValue];
    conf->dnsKey = [config objectForKey:@"dnsKey"];
    conf->token = [config objectForKey:@"token"];
    conf->encryptType =(HttpDnsEncryptType)[[config objectForKey:@"encryptType"] intValue];
    conf->routeIp = [config objectForKey:@"routeIp"];
    conf->timeout = [[config objectForKey:@"timeout"] intValue];
    conf->httpOnly = [[config objectForKey:@"httpOnly"] boolValue];
    conf->retryTimesBeforeSwitchServer = [[config objectForKey:@"retryTimesBeforeSwitchServer"] intValue];
    conf->minutesBeforeSwitchToMain = [[config objectForKey:@"minutesBeforeSwitchToMain"] intValue];
    conf->enableReport = [[config objectForKey:@"enableReport"] boolValue];
    conf->addressType = (HttpDnsAddressType)[[config objectForKey:@"addressType"] intValue];
    return [self initConfig:conf];
}

#pragma mark - setting

- (BOOL) WGSetDnsOpenId:(NSString *)openId {
    if (!openId || ([openId length] == 0)) {
        [[MSDKDnsParamsManager shareInstance] msdkDnsSetMOpenId:HTTP_DNS_UNKNOWN_STR];
        return NO;
    }
    // 保存openid
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetMOpenId:openId];
    return YES;
}

- (void) WGSetPreResolvedDomains:(NSArray *)domains {
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetPreResolvedDomains:domains];
    [[MSDKDnsManager shareInstance] preResolveDomains];
}

- (void) WGSetKeepAliveDomains:(NSArray *)domains {
    if (domains) {
        [[MSDKDnsParamsManager shareInstance] msdkDnsSetKeepAliveDomains:domains];
    }
}

- (void) WGSetIPRankData:(NSDictionary *)IPRankData {
    if (IPRankData) {
        [[MSDKDnsParamsManager shareInstance] msdkDnsSetIPRankData:IPRankData];
    }
}

- (void) WGSetEnableKeepDomainsAlive: (BOOL)enableKeepDomainsAlive {
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetEnableKeepDomainsAlive:enableKeepDomainsAlive];
}

- (void) WGSetHijackDomainArray:(NSArray *)hijackDomainArray {
    if (hijackDomainArray) {
        [[MSDKDnsParamsManager shareInstance] setHijackDomainArray:[hijackDomainArray copy]];
    }
}

- (void) WGSetNoHijackDomainArray:(NSArray *)noHijackDomainArray {
    if (noHijackDomainArray) {
        [[MSDKDnsParamsManager shareInstance] setNoHijackDomainArray:[noHijackDomainArray copy]];
    }
}

- (void) WGSetExpiredIPEnabled:(BOOL)enable {
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetExpiredIPEnabled:enable];
}

- (void) WGSetPersistCacheIPEnabled:(BOOL)enable {
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetPersistCacheIPEnabled:enable];
    [[MSDKDnsManager shareInstance] loadIPsFromPersistCacheAsync];
}

#pragma mark - get host by name

- (NSArray *) WGGetHostByName:(NSString *)domain {
    @synchronized(self) {
        NSArray * dnsResult = @[@"0", @"0"];
        MSDKDNSLOG(@"GetHostByName:%@",domain);
        if (!domain || domain.length == 0) {
            //请求域名为空，返回空
            MSDKDNSLOG(@"MSDKDns Result is Empty!");
            return dnsResult;
        }
        // 转换成小写
        domain = [domain lowercaseString];
        //进行httpdns请求
        NSDate * date = [NSDate date];
        //进行httpdns请求
        NSDictionary * res = @{};
        BOOL expiredIPEnabled = [[MSDKDnsParamsManager shareInstance] msdkDnsGetExpiredIPEnabled];
        if (expiredIPEnabled) {
            res = [[MSDKDnsManager shareInstance] getHostsByNamesEnableExpired:@[domain] verbose:NO];
        } else {
            res = [[MSDKDnsManager shareInstance] getHostsByNames:@[domain] verbose:NO];
        }
        dnsResult = [res objectForKey:domain];
        NSTimeInterval time_consume = [[NSDate date] timeIntervalSinceDate:date] * 1000;
        MSDKDNSLOG(@"MSDKDns WGGetHostByName Total Time Consume is %.1fms", time_consume);
        NSMutableString * ipsStr = [NSMutableString stringWithString:@""];
        for (int i = 0; i < dnsResult.count; i++) {
            NSString * ip = dnsResult[i];
            [ipsStr appendFormat:@"%@,",ip];
        }
        MSDKDNSLOG(@"%@, MSDKDns Result is:%@",domain, ipsStr);
        return dnsResult;
    }
}

- (NSDictionary *) WGGetHostsByNames:(NSArray *)domains {
    @synchronized(self) {
        NSDictionary * dnsResult = @{};
        MSDKDNSLOG(@"GetHostByName:%@",domains);
        if (!domains || [domains count] == 0) {
            //请求域名为空，返回空
            MSDKDNSLOG(@"MSDKDns Result is Empty!");
            return dnsResult;
        }
        // 转换成小写
        domains = [MSDKDnsInfoTool arrayTransLowercase:domains];
        //进行httpdns请求
        NSDate * date = [NSDate date];
        //进行httpdns请求
        BOOL expiredIPEnabled = [[MSDKDnsParamsManager shareInstance] msdkDnsGetExpiredIPEnabled];
        if (expiredIPEnabled) {
            dnsResult = [[MSDKDnsManager shareInstance] getHostsByNamesEnableExpired:domains verbose:NO];
        } else {
            dnsResult = [[MSDKDnsManager shareInstance] getHostsByNames:domains verbose:NO];
        }
        NSTimeInterval time_consume = [[NSDate date] timeIntervalSinceDate:date] * 1000;
        MSDKDNSLOG(@"%@, MSDKDns Result is:%@",domains, dnsResult);
        MSDKDNSLOG(@"MSDKDns WGGetHostByName Total Time Consume is %.1fms", time_consume);
        return dnsResult;
    }
}

- (NSDictionary *) WGGetAllHostsByNames:(NSArray *)domains {
    @synchronized(self) {
        NSDictionary * dnsResult = @{};
        MSDKDNSLOG(@"GetAllHostByName:%@",domains);
        if (!domains || [domains count] == 0) {
            //请求域名为空，返回空
            MSDKDNSLOG(@"MSDKDns Result is Empty!");
            return dnsResult;
        }
        // 转换成小写
        domains = [MSDKDnsInfoTool arrayTransLowercase:domains];
        //进行httpdns请求
        NSDate * date = [NSDate date];
        //进行httpdns请求
        BOOL expiredIPEnabled = [[MSDKDnsParamsManager shareInstance] msdkDnsGetExpiredIPEnabled];
        if (expiredIPEnabled) {
            dnsResult = [[MSDKDnsManager shareInstance] getHostsByNamesEnableExpired:domains verbose:YES];
        } else {
            dnsResult = [[MSDKDnsManager shareInstance] getHostsByNames:domains verbose:YES];
        }
        NSTimeInterval time_consume = [[NSDate date] timeIntervalSinceDate:date] * 1000;
        MSDKDNSLOG(@"%@, MSDKDns Result is:%@",domains, dnsResult);
        MSDKDNSLOG(@"MSDKDns WGGetHostByName Total Time Consume is %.1fms", time_consume);
        return dnsResult;
    }
}

- (void)WGGetHostByNameAsync:(NSString *)domain returnIps:(void (^)(NSArray *))handler {
    @synchronized(self) {
        BOOL expiredIPEnabled = [[MSDKDnsParamsManager shareInstance] msdkDnsGetExpiredIPEnabled];
        if (expiredIPEnabled) {
            //开启了使用过期缓存功能，给出提示建议使用同步接口进行解析
            @throw [NSException exceptionWithName:@"MSDKDns wrong use of api"
                                               reason:@"WGGetHostByNameAsync cannot be used when useExpiredIpEnable is set to true, it is recommended to switch to the WGGetHostByName"
                                             userInfo:nil];
            return;
        }
        MSDKDNSLOG(@"GetHostByNameAsync:%@",domain);
        if (!domain || domain.length == 0) {
            //请求域名为空，返回空
            MSDKDNSLOG(@"MSDKDns Result is Empty!");
            NSArray * dnsResult = @[@"0", @"0"];
            if (handler) {
                handler(dnsResult);
                handler = nil;
            }
            return;
        }
        // 转换成小写
        domain = [domain lowercaseString];
        NSDate * date = [NSDate date];
        [[MSDKDnsManager shareInstance] getHostsByNames:@[domain] verbose:NO returnIps:^(NSDictionary *ipsDict) {
            NSTimeInterval time_consume = [[NSDate date] timeIntervalSinceDate:date] * 1000;
            MSDKDNSLOG(@"MSDKDns WGGetHostByNameAsync Total Time Consume is %.1fms", time_consume);
            if (ipsDict) {
                NSArray * dnsResult = [ipsDict objectForKey:domain];
                NSMutableString * ipsStr = [NSMutableString stringWithString:@""];
                for (int i = 0; i < dnsResult.count; i++) {
                    NSString * ip = dnsResult[i];
                    [ipsStr appendFormat:@"%@,",ip];
                }
                MSDKDNSLOG(@"%@, MSDKDns Result is:%@",domain, ipsStr);
                if (handler) {
                    handler(dnsResult);
                }
            } else {
                NSArray * dnsResult = @[@"0", @"0"];
                if (handler) {
                    handler(dnsResult);
                }
            }
        }];
    }
}

- (void)WGGetHostsByNamesAsync:(NSArray *)domains returnIps:(void (^)(NSDictionary *))handler {
    @synchronized(self) {
        BOOL expiredIPEnabled = [[MSDKDnsParamsManager shareInstance] msdkDnsGetExpiredIPEnabled];
        if (expiredIPEnabled) {
            //开启了使用过期缓存功能，给出提示建议使用同步接口进行解析
            @throw [NSException exceptionWithName:@"MSDKDns wrong use of api"
                                               reason:@"WGGetHostsByNamesAsync cannot be used when useExpiredIpEnable is set to true, it is recommended to switch to the WGGetHostsByNames"
                                             userInfo:nil];
            return;
        }
        MSDKDNSLOG(@"GetHostByNameAsync:%@",domains);
        if (!domains || [domains count] == 0) {
            //请求域名为空，返回空
            MSDKDNSLOG(@"MSDKDns Result is Empty!");
            NSDictionary * dnsResult = @{};
            if (handler) {
                handler(dnsResult);
                handler = nil;
            }
            return;
        }
        // 转换成小写
        domains = [MSDKDnsInfoTool arrayTransLowercase:domains];
        NSDate * date = [NSDate date];
        [[MSDKDnsManager shareInstance] getHostsByNames:domains verbose:NO returnIps:^(NSDictionary *ipsDict) {
            NSTimeInterval time_consume = [[NSDate date] timeIntervalSinceDate:date] * 1000;
            MSDKDNSLOG(@"MSDKDns WGGetHostByNameAsync Total Time Consume is %.1fms", time_consume);
            if (ipsDict) {
                NSDictionary * dnsResult = [[NSDictionary alloc] initWithDictionary:ipsDict];
                MSDKDNSLOG(@"%@, MSDKDns Result is:%@",domains, ipsDict);
                if (handler) {
                    handler(dnsResult);
                }
            } else {
                NSDictionary * dnsResult = @{};
                if (handler) {
                    handler(dnsResult);
                }
            }
        }];
    }
}

- (void)WGGetAllHostsByNamesAsync:(NSArray *)domains returnIps:(void (^)(NSDictionary *))handler {
    @synchronized(self) {
        BOOL expiredIPEnabled = [[MSDKDnsParamsManager shareInstance] msdkDnsGetExpiredIPEnabled];
        if (expiredIPEnabled) {
            //开启了使用过期缓存功能，给出提示建议使用同步接口进行解析
            @throw [NSException exceptionWithName:@"MSDKDns wrong use of api"
                                               reason:@"WGGetAllHostsByNamesAsync cannot be used when useExpiredIpEnable is set to true, it is recommended to switch to the WGGetAllHostsByNames"
                                             userInfo:nil];
            return;
        }
        MSDKDNSLOG(@"GetAllHostsByNamesAsync:%@",domains);
        if (!domains || [domains count] == 0) {
            //请求域名为空，返回空
            MSDKDNSLOG(@"MSDKDns Result is Empty!");
            NSDictionary * dnsResult = @{};
            if (handler) {
                handler(dnsResult);
                handler = nil;
            }
            return;
        }
        // 转换成小写
        domains = [MSDKDnsInfoTool arrayTransLowercase:domains];
        NSDate * date = [NSDate date];
        [[MSDKDnsManager shareInstance] getHostsByNames:domains verbose:YES returnIps:^(NSDictionary *ipsDict) {
            NSTimeInterval time_consume = [[NSDate date] timeIntervalSinceDate:date] * 1000;
            MSDKDNSLOG(@"MSDKDns WGGetAllHostsByNamesAsync Total Time Consume is %.1fms", time_consume);
            if (ipsDict) {
                NSDictionary * dnsResult = [[NSDictionary alloc] initWithDictionary:ipsDict];
                MSDKDNSLOG(@"%@, MSDKDns Result is:%@",domains, ipsDict);
                if (handler) {
                    handler(dnsResult);
                }
            } else {
                NSDictionary * dnsResult = @{};
                if (handler) {
                    handler(dnsResult);
                }
            }
        }];
    }
}

- (NSDictionary *) WGGetDnsDetail:(NSString *) domain {
    return [[MSDKDnsManager shareInstance] getDnsDetail:domain];
}

- (int) WGGetNetworkStack {
    return [[MSDKDnsManager shareInstance] getAddressType];
}

#pragma mark - others

- (void)clearCache {
    [[MSDKDnsManager shareInstance] clearAllCache];
}

- (void)clearHostCache:(NSArray *)hostArray {
    if (hostArray == nil || ([hostArray isKindOfClass:[NSArray class]] && hostArray.count == 0)) {
        [[MSDKDnsManager shareInstance] clearAllCache];
    }else if ([hostArray isKindOfClass:[NSArray class]] && hostArray.count > 0){
        [[MSDKDnsManager shareInstance] clearCacheForDomains:hostArray];
    }
}

@end
