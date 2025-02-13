/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import "MSDKDnsParamsManager.h"
#import "MSDKDnsInfoTool.h"
#import "MSDKDnsPrivate.h"
#import "MSDKDnsLog.h"
#if defined(__has_include)
    #if __has_include("httpdnsIps.h")
        #include "httpdnsIps.h"
    #endif
#endif


@interface MSDKDnsParamsManager()

@property (strong, nonatomic, readwrite) NSString * msdkDnsIp;
@property (strong, nonatomic, readwrite) NSString * msdkDnsOpenId;
@property (strong, nonatomic, readwrite) NSString * msdkDnsAppId;
@property (strong, nonatomic, readwrite) NSString * msdkDnsToken;
@property (assign, nonatomic, readwrite) int msdkDnsId;
@property (strong, nonatomic, readwrite) NSString * msdkDnsKey;
@property (assign, nonatomic, readwrite) int msdkDnsTimeOut;
@property (assign, nonatomic, readwrite) HttpDnsEncryptType msdkEncryptType;
@property (strong, nonatomic, readwrite) NSString *msdkDnsRouteIp;
@property (assign, nonatomic, readwrite) BOOL httpOnly;
@property (strong, nonatomic, readwrite) NSArray* serverArray;
@property (assign, nonatomic, readwrite) NSUInteger retryTimesBeforeSwitchServer;
@property (strong, nonatomic, readwrite) NSArray * backupServerIps;
@property (assign, nonatomic, readwrite) BOOL enableReport;
@property (strong, nonatomic, readwrite) NSArray* preResolvedDomains;
@property (assign, nonatomic, readwrite) HttpDnsAddressType msdkAddressType;
@property (strong, nonatomic, readwrite) NSArray* keepAliveDomains;
@property (strong, nonatomic, readwrite) NSDictionary* ipRankData;
@property (assign, nonatomic, readwrite) BOOL enableKeepDomainsAlive;
@property (assign, nonatomic, readwrite) BOOL expiredIPEnabled;
@property (assign, nonatomic, readwrite) BOOL persistCacheIPEnabled;
@property (assign, nonatomic, readwrite) BOOL enableDetectHostServer;

@end

@implementation MSDKDnsParamsManager

static MSDKDnsParamsManager * gSharedInstance = nil;

+ (instancetype)shareInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSharedInstance = [[MSDKDnsParamsManager alloc] init];
    });
    return gSharedInstance;
}

- (id) init {
    if (self = [super init]) {
        _msdkDnsOpenId = HTTP_DNS_UNKNOWN_STR;
        _msdkDnsAppId = HTTP_DNS_UNKNOWN_STR;
        _retryTimesBeforeSwitchServer = 3;
        _enableReport = NO;
        _msdkAddressType = HttpDnsAddressTypeAuto;
        _enableKeepDomainsAlive = YES;
        _expiredIPEnabled = NO;
        _persistCacheIPEnabled = NO;
        _enableDetectHostServer = NO;
    }
    return self;
}

#pragma mark - setter

- (void)msdkDnsSetMOpenId:(NSString *) mdnsOpenId {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.msdkDnsOpenId = mdnsOpenId;
    });
}

- (void)msdkDnsSetMAppId:(NSString *) mdnsAppId timeOut:(int)mdnsTimeOut encryptType:(HttpDnsEncryptType)mdnsEncryptType
{
    self.msdkDnsAppId = mdnsAppId;
    self.msdkDnsTimeOut = mdnsTimeOut;
    self.msdkEncryptType = mdnsEncryptType;
}


- (void)msdkDnsSetMDnsId:(int) mdnsId dnsKey:(NSString *)mdnsKey token:(NSString* )mdnsToken{
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.msdkDnsId = mdnsId;
        self.msdkDnsKey = mdnsKey;
        self.msdkDnsToken = mdnsToken;
    });
}

- (void)msdkDnsSetRouteIp:(NSString *)routeIp {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.msdkDnsRouteIp = routeIp;
    });
}

- (void)msdkDnsSetHttpOnly:(BOOL)httpOnly {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.httpOnly = httpOnly;
    });
}

// 设置切换ip之前重试次数
- (void)msdkDnsSetRetryTimesBeforeSwitchServer:(NSUInteger)times {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.retryTimesBeforeSwitchServer = times;
    });
}

// 设置备份ip
- (void)msdkDnsSetBackupServerIps: (NSArray *)ips {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.backupServerIps = ips;
        self.serverArray = [NSArray arrayWithObjects:self.msdkDnsIp, nil];
        self.serverArray = [self.serverArray arrayByAddingObjectsFromArray:ips];
    });
}

- (void)msdkDnsSetEnableReport: (BOOL)enableReport {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.enableReport = enableReport;
    });
}

- (void)msdkDnsSetEnableDetectHostServer: (BOOL)enableDetectHostServer {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.enableDetectHostServer = enableDetectHostServer;
    });
}

- (void)msdkDnsSetPreResolvedDomains: (NSArray *)domains {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.preResolvedDomains = [domains copy];
    });
}

- (void)msdkDnsSetHijackDomainArray: (NSArray *)domains {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.hijackDomainArray = [domains copy];
    });
}

- (void)msdkDnsSetNoHijackDomainArray: (NSArray *)domains {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.noHijackDomainArray = [domains copy];
    });
}

- (void)msdkDnsSetAddressType: (HttpDnsAddressType)addressType {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.msdkAddressType = addressType;
    });
}

- (void)msdkDnsSetKeepAliveDomains: (NSArray *)domains {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.keepAliveDomains = [domains copy];
    });
}

- (void)msdkDnsSetIPRankData: (NSDictionary *)ipRankData {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.ipRankData = [ipRankData copy];
    });
}

- (void)msdkDnsSetEnableKeepDomainsAlive: (BOOL)enableKeepDomainsAlive {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.enableKeepDomainsAlive = enableKeepDomainsAlive;
    });
}

- (void)msdkDnsSetExpiredIPEnabled: (BOOL)enable {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
       self.expiredIPEnabled = enable;
    });
}

- (void)msdkDnsSetPersistCacheIPEnabled: (BOOL)enable {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
       self.persistCacheIPEnabled = enable;
    });
}

#pragma mark - getter

- (BOOL)msdkDnsGetHttpOnly {
    return _httpOnly;
}

- (NSString *) msdkDnsGetMDnsIp {
    return _msdkDnsIp;
}

- (NSString *) msdkDnsGetMOpenId {
    return [_msdkDnsOpenId copy];
}

- (NSString *) msdkDnsGetMAppId {
    return [_msdkDnsAppId copy];
}

- (NSString *) msdkDnsGetMToken {
    return [_msdkDnsToken copy];
}

- (int) msdkDnsGetMDnsId {
    return _msdkDnsId;
}

- (NSString *) msdkDnsGetMDnsKey {
    return [_msdkDnsKey copy];
}

- (float) msdkDnsGetMTimeOut {
    float timeOut = 0;
    if (_msdkDnsTimeOut > 0) {
        timeOut = _msdkDnsTimeOut / 1000.0;
    } else {
        timeOut = 2.0;
    }
    return timeOut;
}

- (HttpDnsEncryptType)msdkDnsGetEncryptType
{
    return _msdkEncryptType;
}

- (NSString *)msdkDnsGetRouteIp {
    return _msdkDnsRouteIp;
}

- (NSArray *)msdkDnsGetServerIps {
    return _serverArray;
}

- (NSUInteger)msdkDnsGetRetryTimesBeforeSwitchServer {
    return _retryTimesBeforeSwitchServer;
}

- (BOOL)msdkDnsGetEnableReport {
    return _enableReport;
}

- (BOOL)msdkDnsGetEnableDetectHostServer {
    return _enableDetectHostServer;
}

- (NSArray *)msdkDnsGetPreResolvedDomains {
    return _preResolvedDomains;
}

- (NSArray *)msdkDnsGetHijackDomainArray {
    return _hijackDomainArray;
}

- (NSArray *)msdkDnsGetNoHijackDomainArray {
    return _noHijackDomainArray;
}

- (HttpDnsAddressType)msdkDnsGetAddressType {
    return _msdkAddressType;
}

- (NSArray *)msdkDnsGetKeepAliveDomains {
    return _keepAliveDomains;
}

- (NSDictionary *)msdkDnsGetIPRankData {
    return _ipRankData;
}

- (BOOL)msdkDnsGetEnableKeepDomainsAlive {
    return _enableKeepDomainsAlive;
}

- (BOOL)msdkDnsGetExpiredIPEnabled {
    return _expiredIPEnabled;
}

- (BOOL)msdkDnsGetPersistCacheIPEnabled {
    return _persistCacheIPEnabled;
}
 
@end
