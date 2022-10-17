//
//  AttaReport.m
//  MSDKDns
//
//  Created by vast on 2021/12/7.
//  Copyright © 2021 Tencent. All rights reserved.
//

#import "AttaReport.h"
#import "MSDKDnsLog.h"
#import "MSDKDnsNetworkManager.h"
#import "MSDKDnsParamsManager.h"
#import "MSDKDnsInfoTool.h"
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <UIKit/UIKit.h>
#import "MSDKDns.h"
#if defined(__has_include)
    #if __has_include("httpdnsIps.h")
        #include "httpdnsIps.h"
    #endif
#endif

@interface AttaReport ()
@property (strong, nonatomic) NSURLSession * session;
@property (strong, nonatomic) NSString *attaid;
@property (strong, nonatomic) NSString *token;
@property (strong, nonatomic) NSString *reportUrl;
@property (assign, nonatomic) NSUInteger limit;
@property (assign, nonatomic) NSUInteger interval;
@property (assign, nonatomic) NSUInteger count;
@property (strong, nonatomic) NSDate *lastReportTime;
@end


@implementation AttaReport

static AttaReport * _sharedInstance = nil;

+ (instancetype) sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[AttaReport alloc] init];
    });
    return _sharedInstance;
}

- (instancetype) init {
    if (self = [super init]) {
        NSURLSessionConfiguration *defaultSessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
        self.session = [NSURLSession sessionWithConfiguration:defaultSessionConfiguration delegate:nil delegateQueue:nil];
#ifdef httpdnsIps_h
        self.attaid = ATTAID;
        self.token = ATTAToken;
        self.reportUrl = ATTAReportUrl;
        self.limit = ATTAReportDnsSpendLimit;
        self.interval = ATTAReportDnsSpendInterval;
        self.count = 0;
        self.lastReportTime = [NSDate date];
#endif
    }
    return self;
}

- (NSString *)formatReportParams:(NSDictionary *)params {
    /// 客户端ip、运营商、网络类型、hdns加密方式（aes、des、https）、失败时间、请求失败的服务端ip、授权id
    NSString * carrier = [AttaReport getOperatorsType];
    NSString * networkType = [[MSDKDnsNetworkManager shareInstance] networkType];
    int dnsId = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsId];
    int encryptType = [[MSDKDnsParamsManager shareInstance] msdkDnsGetEncryptType];
    unsigned long eventTime = [[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970] * 1000] unsignedIntegerValue];
    NSString *deviceName = [[UIDevice currentDevice] name];
    NSString *systemName = [[UIDevice currentDevice] systemName];
    NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
    NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithDictionary:params];
    [dic addEntriesFromDictionary:@{
        @"carrier": carrier,
        @"networkType": networkType,
        @"dnsId": [NSNumber numberWithInt:dnsId],
        @"encryptType": encryptType == 0 ? @"DesHttp" : (encryptType == 1 ? @"AesHttp" : @"Https"),
        @"eventTime": [NSNumber numberWithLong:eventTime],
        @"deviceName": deviceName,
        @"systemName": systemName,
        @"systemVersion": systemVersion,
        @"sdkVersion": MSDKDns_Version,
        @"sessionId": [MSDKDnsInfoTool generateSessionID]
    }];
    return [self paramsToUrlString:dic];
}

- (NSString *)paramsToUrlString:(NSDictionary *)params {
    NSMutableString *res = [NSMutableString stringWithFormat:@"attaid=%@&token=%@",  _attaid, _token];
    if (params) {
        for (id key in params) {
            [res appendFormat:@"&%@=%@", key, [params objectForKey:key]];
        }
    }
    return res;
}

- (void)reportEvent:(NSDictionary *)params {
    NSURL *url = [NSURL URLWithString:_reportUrl];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    NSString *postData = [self formatReportParams:params];
    request.HTTPBody = [postData dataUsingEncoding:NSUTF8StringEncoding];
    MSDKDNSLOG(@"ATTAReport data: %@", postData);
    NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:request];
    [dataTask resume];
}

// 获取运营商类型
+ (NSString*)getOperatorsType{
    CTTelephonyNetworkInfo *telephonyInfo = [[CTTelephonyNetworkInfo alloc] init];
    CTCarrier *carrier = [telephonyInfo subscriberCellularProvider];

    NSString *currentCountryCode = [carrier mobileCountryCode];
    NSString *mobileNetWorkCode = [carrier mobileNetworkCode];

    if (currentCountryCode || mobileNetWorkCode) {
        return [NSString stringWithFormat:@"%@%@", currentCountryCode, mobileNetWorkCode];
    }
    return @"-1";
}

- (BOOL)shoulReportDnsSpend {
//    取消上报次数上限，每5分钟上报一次
//    if (self.count >= self.limit) {
//        return NO;
//    }
    NSDate *now = [NSDate date];
    if ([now timeIntervalSinceDate:self.lastReportTime] >= self.interval) {
        self.lastReportTime = now;
        self.count += 1;
        return YES;
    }
    return NO;
}

@end
