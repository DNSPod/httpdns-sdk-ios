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
@property (nonatomic, assign, readwrite) int serverIndex;
@property (nonatomic, strong, readwrite) NSArray* serverArray;
@property (nonatomic, strong, readwrite) NSDate *firstFailTime; // 记录首次失败的时间
@property (nonatomic, assign, readwrite) BOOL waitToSwitch; // 防止连续多次切换
@property (nonatomic, assign, readwrite) NSUInteger retryTimesBeforeSwitchServer;
@property (nonatomic, assign, readwrite) NSUInteger minutesBeforeSwitchToMain;
@property (nonatomic, strong, readwrite) NSArray * backupServerIps;
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
        _serverIndex = 0;
        _waitToSwitch = NO;
        _retryTimesBeforeSwitchServer = 3;
        _minutesBeforeSwitchToMain = 10;
    }
    return self;
}

- (void)switchDnsServer {
    if (self.waitToSwitch) {
        return;
    }
    self.waitToSwitch = YES;
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.serverIndex += 1;
        if (!self.firstFailTime) {
            self.firstFailTime = [NSDate date];
            // 一定时间后自动切回主ip
            __weak __typeof__(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, self.minutesBeforeSwitchToMain * 60 * NSEC_PER_SEC), [MSDKDnsInfoTool msdkdns_queue], ^{
                MSDKDNSLOG(@"auto reset server index, use main ip now.");
                weakSelf.serverIndex = 0;
                weakSelf.firstFailTime = nil;
            });
        }
        if (self.serverIndex >= [self.serverArray count]) {
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

#pragma mark - setter

- (void)msdkDnsSetMDnsIp:(NSString *) msdkDnsIp {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.msdkDnsIp = msdkDnsIp;
        self.serverArray = [NSArray arrayWithObjects:msdkDnsIp, nil];
#ifdef httpdnsIps_h
        if (self.msdkEncryptType == HttpDnsEncryptTypeHTTPS) {
            self.serverArray = [self.serverArray arrayByAddingObjectsFromArray:httpsServerIps];
        } else {
            self.serverArray = [self.serverArray arrayByAddingObjectsFromArray:httpServerIps];
        }
#endif
    });
}

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
        if (self.msdkDnsIp) {
            self.serverArray = [NSArray arrayWithObjects:self.msdkDnsIp, nil];
#ifdef httpdnsIps_h
            if (mdnsEncryptType == HttpDnsEncryptTypeHTTPS) {
                self.serverArray = [self.serverArray arrayByAddingObjectsFromArray:httpsServerIps];
            } else {
                self.serverArray = [self.serverArray arrayByAddingObjectsFromArray:httpServerIps];
            }
#endif
        }
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

// 设置备份ip
- (void)msdkDnsSetBackupServerIps: (NSArray *)ips {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.backupServerIps = ips;
        self.serverArray = [NSArray arrayWithObjects:self.msdkDnsIp, nil];
        self.serverArray = [self.serverArray arrayByAddingObjectsFromArray:ips];
    });
}

#pragma mark - getter

- (BOOL)msdkDnsGetHttpOnly {
    return _httpOnly;
}

- (NSString *) msdkDnsGetMDnsIp {
    return [_serverArray objectAtIndex:_serverIndex];
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

- (NSNumber*)msdkDnsGetServerIndex {
    return [NSNumber numberWithInt:_serverIndex];
}

- (NSUInteger)msdkDnsGetRetryTimesBeforeSwitchServer {
    return _retryTimesBeforeSwitchServer;
}

- (NSUInteger)msdkDnsGetMinutesBeforeSwitchToMain {
    return _minutesBeforeSwitchToMain;
}

@end
