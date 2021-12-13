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
    NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            MSDKDNSLOG(@"ATTAReport response: %@",json);
        }];

    [dataTask resume];
}

// 获取运营商类型
+ (NSString*)getOperatorsType{
    CTTelephonyNetworkInfo *telephonyInfo = [[CTTelephonyNetworkInfo alloc] init];
    CTCarrier *carrier = [telephonyInfo subscriberCellularProvider];

    NSString *currentCountryCode = [carrier mobileCountryCode];
    NSString *mobileNetWorkCode = [carrier mobileNetworkCode];

    if (![currentCountryCode isEqualToString:@"460"]) {
        return @"unknown";
    }

    if ([mobileNetWorkCode isEqualToString:@"00"] ||
        [mobileNetWorkCode isEqualToString:@"02"] ||
        [mobileNetWorkCode isEqualToString:@"07"]) {

        // 中国移动
        return @"China Mobile";
    }

    if ([mobileNetWorkCode isEqualToString:@"01"] ||
        [mobileNetWorkCode isEqualToString:@"06"] ||
        [mobileNetWorkCode isEqualToString:@"09"]) {

        // 中国联通
        return @"China Unicom";
    }

    if ([mobileNetWorkCode isEqualToString:@"03"] ||
        [mobileNetWorkCode isEqualToString:@"05"] ||
        [mobileNetWorkCode isEqualToString:@"11"]) {

        // 中国电信
        return @"China Telecom";
    }

    if ([mobileNetWorkCode isEqualToString:@"20"]) {

        // 中国铁通
        return @"China Tietong";
    }

    return @"unknown";
}

@end