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

@interface MSDKDns ()

@property (assign, nonatomic) BOOL msdkDnsReady;

@end

@implementation MSDKDns

static MSDKDns * _sharedInstance = nil;

#pragma mark - init
+ (instancetype) sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[MSDKDns alloc] init];
    });
    return _sharedInstance;
}

- (instancetype) init {
    if (self = [super init]) {
        _msdkDnsReady = NO;
        //开启网络切换，及前后台切换的监听
        [MSDKDnsNetworkManager start];
    }
    return self;
}

- (BOOL) initConfig:(DnsConfig *)config {
    [[MSDKDnsLog sharedInstance] setEnableLog:config->debug];
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetMAppId:config->appId MTimeOut:config->timeout MEncryptType:config->encryptType];
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetMDnsId:config->dnsId MDnsKey:config->dnsKey MToken:config->token];
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetAddressType:config->addressType];
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetMDnsIp:config->dnsIp];
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetRouteIp: config->routeIp];
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetHttpOnly: config->httpOnly];
    if (config->retryTimesBeforeSwitchServer) {
        [[MSDKDnsParamsManager shareInstance] msdkDnsSetRetryTimesBeforeSwitchServer: config->retryTimesBeforeSwitchServer];
    }
    if (config->minutesBeforeSwitchToMain) {
        [[MSDKDnsParamsManager shareInstance] msdkDnsSetMinutesBeforeSwitchToMain:config->minutesBeforeSwitchToMain];
    }
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetEnableReport:config->enableReport];
    [[MSDKDnsManager shareInstance] switchToMainServer];
    self.msdkDnsReady = YES;
    MSDKDNSLOG(@"MSDKDns init success.");
    return YES;
}

- (BOOL) initConfigWithDictionary:(NSDictionary *)config {
    DnsConfig *conf = new DnsConfig();
    conf->appId = [config objectForKey:@"appId"];
    conf->debug = [[config objectForKey:@"debug"] boolValue];
    conf->dnsId = [[config objectForKey:@"dnsId"] intValue];
    conf->dnsIp = [config objectForKey:@"dnsIp"];
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

- (void) WGSetDnsBackupServerIps:(NSArray *)ips {
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetBackupServerIps:ips];
    [[MSDKDnsManager shareInstance] switchToMainServer];
}

- (void) WGSetPreResolvedDomains:(NSArray *)domains {
    [[MSDKDnsParamsManager shareInstance] msdkDnsSetPreResolvedDomains:domains];
    [[MSDKDnsManager shareInstance] preResolveDomains];
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
        dnsResult = [[MSDKDnsManager shareInstance] getHostByName:domain];
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
        NSMutableArray *lowerCaseArray = [NSMutableArray array];
        for(int i = 0; i < [domains count]; i++) {
            NSString *d = [domains objectAtIndex:i];
            if (d && d.length > 0) {
                [lowerCaseArray addObject:[d lowercaseString]];
            }
        }
        domains = lowerCaseArray;
        //进行httpdns请求
        NSDate * date = [NSDate date];
        //进行httpdns请求
        dnsResult = [[MSDKDnsManager shareInstance] getHostsByNames:domains];
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
        NSMutableArray *lowerCaseArray = [NSMutableArray array];
        for(int i = 0; i < [domains count]; i++) {
            NSString *d = [domains objectAtIndex:i];
            if (d && d.length > 0) {
                [lowerCaseArray addObject:[d lowercaseString]];
            }
        }
        domains = lowerCaseArray;
        //进行httpdns请求
        NSDate * date = [NSDate date];
        //进行httpdns请求
        dnsResult = [[MSDKDnsManager shareInstance] getAllHostsByNames:domains];
        NSTimeInterval time_consume = [[NSDate date] timeIntervalSinceDate:date] * 1000;
        MSDKDNSLOG(@"%@, MSDKDns Result is:%@",domains, dnsResult);
        MSDKDNSLOG(@"MSDKDns WGGetHostByName Total Time Consume is %.1fms", time_consume);
        return dnsResult;
    }
}

- (void)WGGetHostByNameAsync:(NSString *)domain returnIps:(void (^)(NSArray *))handler {
    @synchronized(self) {
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
        [[MSDKDnsManager shareInstance] getHostByName:domain returnIps:^(NSArray *ipsArray) {
            NSTimeInterval time_consume = [[NSDate date] timeIntervalSinceDate:date] * 1000;
            MSDKDNSLOG(@"MSDKDns WGGetHostByNameAsync Total Time Consume is %.1fms", time_consume);
            if (ipsArray) {
                NSArray * dnsResult = [[NSArray alloc] initWithArray:ipsArray];
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
        NSMutableArray *lowerCaseArray = [NSMutableArray array];
        for(int i = 0; i < [domains count]; i++) {
            NSString *d = [domains objectAtIndex:i];
            if (d && d.length > 0) {
                [lowerCaseArray addObject:[d lowercaseString]];
            }
        }
        domains = lowerCaseArray;
        NSDate * date = [NSDate date];
        [[MSDKDnsManager shareInstance] getHostsByNames:domains returnIps:^(NSDictionary *ipsDict) {
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
        NSMutableArray *lowerCaseArray = [NSMutableArray array];
        for(int i = 0; i < [domains count]; i++) {
            NSString *d = [domains objectAtIndex:i];
            if (d && d.length > 0) {
                [lowerCaseArray addObject:[d lowercaseString]];
            }
        }
        domains = lowerCaseArray;
        NSDate * date = [NSDate date];
        [[MSDKDnsManager shareInstance] getAllHostsByNames:domains returnIps:^(NSDictionary *ipsDict) {
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

- (NSDictionary *) WGGetDnsDetail:(NSString *) domain {
    return [[MSDKDnsManager shareInstance] getDnsDetail:domain];
}

#pragma mark - others

- (void)clearCache {
    [[MSDKDnsManager shareInstance] clearAllCache];
}

@end
