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

@property (strong, nonatomic, readwrite) NSString * msdkDnsOpenId;
@property (strong, nonatomic, readwrite) NSString * msdkDnsAppId;
@property (strong, nonatomic, readwrite) NSString * msdkDnsToken;
@property (assign, nonatomic, readwrite) int msdkDnsId;
@property (strong, nonatomic, readwrite) NSString * msdkDnsKey;
@property (assign, nonatomic, readwrite) int msdkDnsTimeOut;
@property (assign, nonatomic, readwrite) HttpDnsEncryptType msdkEncryptType;
@property (strong, nonatomic, readwrite) NSString *msdkDnsRouteIp;
@property (assign, nonatomic, readwrite) BOOL httpOnly;
@property (assign, nonatomic, readwrite) NSUInteger retryTimesBeforeSwitchServer;
@property (assign, nonatomic, readwrite) NSUInteger minutesBeforeSwitchToMain;
@property (assign, nonatomic, readwrite) BOOL enableReport;
@property (strong, nonatomic, readwrite) NSArray* preResolvedDomains;
@property (assign, nonatomic, readwrite) HttpDnsAddressType msdkAddressType;
@end

@implementation MSDKDnsParamsManager

static MSDKDnsParamsManager * _sharedInstance = nil;

+ (instancetype)shareInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[MSDKDnsParamsManager alloc] init];
    });
    return _sharedInstance;
}

- (id) init {
    if (self = [super init]) {
        _msdkDnsOpenId = HTTP_DNS_UNKNOWN_STR;
        _msdkDnsAppId = HTTP_DNS_UNKNOWN_STR;
        _retryTimesBeforeSwitchServer = 3;
        _minutesBeforeSwitchToMain = 10;
        _enableReport = NO;
        _msdkAddressType = HttpDnsAddressTypeAuto;
    }
    return self;
}

#pragma mark - setter

- (void)msdkDnsSetMOpenId:(NSString *) mdnsOpenId {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.msdkDnsOpenId = mdnsOpenId;
    });
}

- (void)msdkDnsSetMAppId:(NSString *) mdnsAppId MTimeOut:(int)mdnsTimeOut MEncryptType:(HttpDnsEncryptType)mdnsEncryptType
{
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.msdkDnsAppId = mdnsAppId;
        self.msdkDnsTimeOut = mdnsTimeOut;
        self.msdkEncryptType = mdnsEncryptType;
    });
}


- (void)msdkDnsSetMDnsId:(int) mdnsId MDnsKey:(NSString *)mdnsKey MToken:(NSString* )mdnsToken{
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

// 设置切回主ip间隔时长
- (void)msdkDnsSetMinutesBeforeSwitchToMain:(NSUInteger)minutes {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.minutesBeforeSwitchToMain = minutes;
    });
}

- (void)msdkDnsSetEnableReport: (BOOL)enableReport {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.enableReport = enableReport;
    });
}

- (void)msdkDnsSetPreResolvedDomains: (NSArray *)domains {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.preResolvedDomains = [domains copy];
    });
}

- (void)msdkDnsSetAddressType: (HttpDnsAddressType)addressType {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.msdkAddressType = addressType;
    });
}

#pragma mark - getter

- (BOOL)msdkDnsGetHttpOnly {
    return _httpOnly;
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

- (NSUInteger)msdkDnsGetRetryTimesBeforeSwitchServer {
    return _retryTimesBeforeSwitchServer;
}

- (NSUInteger)msdkDnsGetMinutesBeforeSwitchToMain {
    return _minutesBeforeSwitchToMain;
}

- (BOOL)msdkDnsGetEnableReport {
    return _enableReport;
}

- (NSArray *)msdkDnsGetPreResolvedDomains {
    return _preResolvedDomains;
}

- (HttpDnsAddressType)msdkDnsGetAddressType {
    return _msdkAddressType;
}

@end
