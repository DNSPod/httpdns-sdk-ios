/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import "MSDKDnsParamsManager.h"
#import "MSDKDnsInfoTool.h"
#import "MSDKDnsPrivate.h"

NSString *DES_CHANNEL = @"DesChannel";
NSString *AES_CHANNEL = @"AesChannel";
NSString *HTTPS_CHANNEL = @"HttpsChannel";

@interface MSDKDnsParamsManager()

@property (strong, nonatomic, readwrite) NSString * msdkDnsIp;
@property (strong, nonatomic, readwrite) NSString * msdkDnsOpenId;
@property (strong, nonatomic, readwrite) NSString * msdkDnsAppId;
@property (strong, nonatomic, readwrite) NSString * msdkDnsToken;
@property (assign, nonatomic, readwrite) int msdkDnsId;
@property (strong, nonatomic, readwrite) NSString * msdkDnsKey;
@property (assign, nonatomic, readwrite) int msdkDnsTimeOut;
@property (strong, nonatomic) NSString *msdkDnsChannel;

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
    }
    return self;
}

- (void)msdkDnsSetMDnsIp:(NSString *) msdkDnsIp {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.msdkDnsIp = msdkDnsIp;
    });
}

- (void)msdkDnsSetMOpenId:(NSString *) mdnsOpenId {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.msdkDnsOpenId = mdnsOpenId;
    });
}

- (void)msdkDnsSetMAppId:(NSString *) mdnsAppId MTimeOut:(int)mdnsTimeOut
{
    [self msdkDnsSetMAppId:mdnsAppId MTimeOut:mdnsTimeOut MChannel:DES_CHANNEL];
}

- (void)msdkDnsSetMAppId:(NSString *) mdnsAppId MTimeOut:(int)mdnsTimeOut MChannel:(NSString *)mdnsChannel
{
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.msdkDnsAppId = mdnsAppId;
        self.msdkDnsTimeOut = mdnsTimeOut;
        self.msdkDnsChannel = mdnsChannel;
    });
}

- (void)msdkDnsSetMAppId:(NSString *) mdnsAppId MToken:(NSString* )mdnsToken MTimeOut:(int)mdnsTimeOut MChannel:(NSString *)mdnsChannel
{
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.msdkDnsAppId = mdnsAppId;
        self.msdkDnsTimeOut = mdnsTimeOut;
        self.msdkDnsChannel = mdnsChannel;
        self.msdkDnsToken = mdnsToken;
    });
}

- (void)msdkDnsSetMDnsId:(int) mdnsId MDnsKey:(NSString *)mdnsKey {
    dispatch_async([MSDKDnsInfoTool msdkdns_queue], ^{
        self.msdkDnsId = mdnsId;
        self.msdkDnsKey = mdnsKey;
    });
}

- (NSString *) msdkDnsGetMDnsIp {
    return [_msdkDnsIp copy];
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

- (NSString *)msdkDnsGetChannel
{
    return _msdkDnsChannel;
}

@end
