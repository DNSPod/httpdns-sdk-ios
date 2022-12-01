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

@property (assign, nonatomic) BOOL msdkDnsReady;
@property (strong, nonatomic) NSMutableURLRequest *request;

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
#if IS_INTL
    if (config->encryptType == HttpDnsEncryptTypeHTTPS) {
        //开启了使用过期缓存功能，给出提示建议使用同步接口进行解析
        @throw [NSException exceptionWithName:@"MSDKDns wrong use of encryptType"
                                           reason:@"HttpDnsEncryptTypeHTTPS cannot be used because httpdns-sdk-intl version still doesn't support, it is recommended to use HttpDnsEncryptTypeDES or HttpDnsEncryptTypeAES"
                                         userInfo:nil];
        return NO;
    }
#endif
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
    [self fetchConfig:config->dnsId MEncryptType:config->encryptType MDnsKey:config->dnsKey MToken:config->token];
    self.msdkDnsReady = YES;
    MSDKDNSLOG(@"MSDKDns init success.");
    return YES;
}

- (void)fetchConfig:(int) mdnsId MEncryptType:(HttpDnsEncryptType)mdnsEncryptType MDnsKey:(NSString *)mdnsKey MToken:(NSString* )mdnsToken {
    
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
            }else {
            // 数据为空暂时不做处理
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

    // 对于其他的 challenges 直接使用默认的验证方案
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
        NSMutableArray *lowerCaseArray = [NSMutableArray array];
        for(int i = 0; i < [domains count]; i++) {
            NSString *d = [domains objectAtIndex:i];
            if (d && d.length > 0) {
                [lowerCaseArray addObject:[d lowercaseString]];
            }
        }
        domains = lowerCaseArray;
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
        [[MSDKDnsManager shareInstance] getHostsByNames:domains verbose:YES returnIps:^(NSDictionary *ipsDict) {
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

- (NSArray *) WGGetHostByNameEnableExpired:(NSString *)domain {
    @synchronized(self) {
        NSArray * dnsResult = @[@"0", @"0"];
        MSDKDNSLOG(@"GetHostByNameEnableExpired:%@",domain);
        if (!domain || domain.length == 0) {
            //请求域名为空，返回空
            MSDKDNSLOG(@"MSDKDns Result is Empty!");
            return dnsResult;
        }
        // 转换成小写
        domain = [domain lowercaseString];
        NSDate * date = [NSDate date];
        //进行httpdns请求
        NSDictionary *res = [[MSDKDnsManager shareInstance] getHostsByNamesEnableExpired:@[domain] verbose:NO];
        dnsResult = [res objectForKey:domain];
        NSTimeInterval time_consume = [[NSDate date] timeIntervalSinceDate:date] * 1000;
        MSDKDNSLOG(@"MSDKDns WGGetHostByNameEnableExpired Total Time Consume is %.1fms", time_consume);
        NSMutableString * ipsStr = [NSMutableString stringWithString:@""];
        for (int i = 0; i < dnsResult.count; i++) {
            NSString * ip = dnsResult[i];
            [ipsStr appendFormat:@"%@,",ip];
        }
        MSDKDNSLOG(@"%@, MSDKDns Result is:%@",domain, ipsStr);
        return dnsResult;
    }
}

- (NSDictionary *) WGGetHostsByNamesEnableExpired:(NSArray *)domains {
    @synchronized(self) {
        NSDictionary * dnsResult = @{};
        MSDKDNSLOG(@"GetHostsByNamesEnableExpired:%@",domains);
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
        NSDate * date = [NSDate date];
        //进行httpdns请求
        dnsResult = [[MSDKDnsManager shareInstance] getHostsByNamesEnableExpired:domains verbose:NO];
        NSTimeInterval time_consume = [[NSDate date] timeIntervalSinceDate:date] * 1000;
        MSDKDNSLOG(@"%@, MSDKDns Result is:%@",domains, dnsResult);
        MSDKDNSLOG(@"MSDKDns WGGetHostsByNamesEnableExpired Total Time Consume is %.1fms", time_consume);
        return dnsResult;
    }
}

- (NSDictionary *) WGGetAllHostsByNamesEnableExpired:(NSArray *)domains {
    @synchronized(self) {
        NSDictionary * dnsResult = @{};
        MSDKDNSLOG(@"GetAllHostsByNamesEnableExpired:%@",domains);
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
        NSDate * date = [NSDate date];
        //进行httpdns请求
        dnsResult = [[MSDKDnsManager shareInstance] getHostsByNamesEnableExpired:domains verbose:YES];
        NSTimeInterval time_consume = [[NSDate date] timeIntervalSinceDate:date] * 1000;
        MSDKDNSLOG(@"%@, MSDKDns Result is:%@",domains, dnsResult);
        MSDKDNSLOG(@"MSDKDns WGGetAllHostsByNamesEnableExpired Total Time Consume is %.1fms", time_consume);
        return dnsResult;
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
