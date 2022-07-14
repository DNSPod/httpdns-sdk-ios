/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import "MSDKDns.h"

@interface MSDKDnsParamsManager : NSObject

@property (nonatomic, strong, readwrite)NSArray * hijackDomainArray;
@property (nonatomic, strong, readwrite)NSArray * noHijackDomainArray;

+ (instancetype)shareInstance;

- (void)msdkDnsSetMDnsIp:(NSString *) mdnsIp;
- (void)msdkDnsSetMOpenId:(NSString *) mdnsOpenId;
- (void)msdkDnsSetMAppId:(NSString *) mdnsAppId MTimeOut:(int)mdnsTimeOut MEncryptType:(HttpDnsEncryptType)mdnsEncryptType;
- (void)msdkDnsSetMDnsId:(int) mdnsId MDnsKey:(NSString *)mdnsKey MToken:(NSString* )mdnsToken;
- (void)msdkDnsSetRouteIp:(NSString *)routeIp;
- (void)msdkDnsSetHttpOnly:(BOOL)httpOnly;
// 设置切换ip之前重试次数
- (void)msdkDnsSetRetryTimesBeforeSwitchServer:(NSUInteger)times;
// 设置切回主ip间隔时长
- (void)msdkDnsSetMinutesBeforeSwitchToMain:(NSUInteger)minutes;
// 设置备份ip
- (void)msdkDnsSetBackupServerIps: (NSArray *)ips;
- (void)msdkDnsSetEnableReport: (BOOL)enableReport;
- (void)msdkDnsSetPreResolvedDomains: (NSArray *)domains;
- (void)msdkDnsSetAddressType: (HttpDnsAddressType)addressType;
- (void)msdkDnsSetKeepAliveDomains: (NSArray *)domains;
- (void)msdkDnsSetEnableKeepDomainsAlive: (BOOL)enableKeepDomainsAlive;

- (NSString *) msdkDnsGetMDnsIp;
- (NSString *) msdkDnsGetMOpenId;
- (NSString *) msdkDnsGetMAppId;
- (int) msdkDnsGetMDnsId;
- (NSString *) msdkDnsGetMDnsKey;
- (float) msdkDnsGetMTimeOut;
- (HttpDnsEncryptType)msdkDnsGetEncryptType;
- (NSString *)msdkDnsGetMToken;
- (NSString *)msdkDnsGetRouteIp;
- (BOOL)msdkDnsGetHttpOnly;
- (NSArray *)msdkDnsGetServerIps;
- (NSUInteger)msdkDnsGetRetryTimesBeforeSwitchServer;
- (NSUInteger)msdkDnsGetMinutesBeforeSwitchToMain;
- (BOOL)msdkDnsGetEnableReport;
- (NSArray *)msdkDnsGetPreResolvedDomains;
- (HttpDnsAddressType)msdkDnsGetAddressType;
- (NSArray *)msdkDnsGetKeepAliveDomains;
- (BOOL)msdkDnsGetEnableKeepDomainsAlive;
@end
